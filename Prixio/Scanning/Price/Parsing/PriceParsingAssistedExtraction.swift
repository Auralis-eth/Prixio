//
//  PriceParsingAssistedExtraction.swift
//  Prixio
//

import Foundation
import FoundationModels

private struct PriceParsingAssistedExtractor {
    let instructions = """
    You are helping parse OCR text from grocery shelf labels into structured product pricing data.
    Pick the OCR lines most likely to describe one target product.
    Choose only from the provided price candidates.
    Prefer product-level prices over deposits, fees, or unrelated numbers.
    Do not invent prices, line indexes, or product names that are not supported by the OCR evidence.
    """

    func resolveWithFoundationModel(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        ambiguity: PriceParsingService.ExtractionAmbiguityReport
    ) async throws -> PriceParsingService.AssistedExtractionResult? {
        guard SystemLanguageModel.default.availability == .available else {
            return nil
        }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = buildAssistedExtractionPrompt(snapshot: snapshot, ambiguity: ambiguity)
        let response = try await session.respond(to: prompt, generating: PriceParsingService.AssistedExtractionResponse.self)
        return PriceParsingService.AssistedExtractionResult(
            targetLineIndexes: response.content.targetLineIndexes,
            selectedPriceCandidateIndex: response.content.selectedPriceCandidateIndex,
            selectedPriceKind: PriceParsingService.AssistedPriceKind(rawValue: response.content.selectedPriceKind) ?? .unknown,
            canonicalItemName: response.content.canonicalItemName,
            ambiguityNotes: response.content.ambiguityNotes,
            confidenceBucket: PriceParsingService.AssistedConfidenceBucket(rawValue: response.content.confidenceBucket) ?? .low
        )
    }

    func buildAssistedExtractionPrompt(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        ambiguity: PriceParsingService.ExtractionAmbiguityReport
    ) -> String {
        let lineContext = snapshot.consolidatedObservations.enumerated().map { index, observation in
            PriceParsingService.PromptLineContext(index: index, text: observation.string, confidence: observation.confidence)
        }
        let candidateContext = snapshot.priceCandidates.enumerated().map { index, candidate in
            PriceParsingService.PromptPriceCandidateContext(
                index: index,
                value: "\(candidate.value)",
                quantity: candidate.quantity.map { "\($0)" },
                confidence: candidate.confidence,
                priority: candidate.priority,
                label: candidate.label,
                sourceText: candidate.sourceText,
                sourceLineIndexes: PriceParsingService.sourceLineIndexes(for: candidate, in: snapshot)
            )
        }

        let encodedLines = encodeForPrompt(lineContext)
        let encodedCandidates = encodeForPrompt(candidateContext)
        let weaknessList = ambiguity.weaknesses.map(\.rawValue).joined(separator: ", ")

        return """
        OCR lines:
        \(encodedLines)

        Price candidates:
        \(encodedCandidates)

        Current heuristic item name hint: \(snapshot.itemNameHint ?? "nil")
        Current heuristic unit: \(snapshot.detectedUnit?.rawValue ?? "nil")
        Current heuristic quantity: \(snapshot.resolvedQuantity.map { "\($0)" } ?? "nil")
        Current heuristic confidence: \(snapshot.heuristicConfidence)
        Ambiguity reasons: \(weaknessList.isEmpty ? "none" : weaknessList)

        Select the OCR lines most likely to describe the target grocery product. Choose at most one existing price candidate index.
        Classify the chosen price candidate as sale, regular, unitPrice, deposit, noise, or unknown.
        Return a canonical item name only if the OCR evidence supports it.
        Do not invent new prices, new lines, or missing values. If the data is unclear, leave fields empty and explain ambiguity in ambiguityNotes.
        """
    }

    func mergeAssistedExtraction(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        assisted: PriceParsingService.AssistedExtractionResult
    ) -> OCRResult {
        let heuristicResult = PriceParsingService.makeOCRResult(from: snapshot)
        let selectedCandidate = assisted.selectedPriceCandidateIndex.flatMap { index in
            snapshot.priceCandidates.indices.contains(index) ? snapshot.priceCandidates[index] : nil
        }
        let shouldTrustModelCandidate = assisted.confidenceBucket != .low
            && selectedCandidate != nil
            && assisted.selectedPriceKind != .noise

        let finalPrice = shouldTrustModelCandidate ? selectedCandidate?.value : heuristicResult.price
        let finalQuantity = shouldTrustModelCandidate
            ? (selectedCandidate?.quantity ?? snapshot.resolvedQuantity)
            : heuristicResult.quantity
        let finalItemName = normalizedCanonicalItemName(
            from: assisted,
            snapshot: snapshot
        ) ?? heuristicResult.itemNameHint
        let finalLines = supportingLines(from: assisted.targetLineIndexes, snapshot: snapshot)
        let finalConfidence = mergedConfidence(
            heuristicConfidence: snapshot.heuristicConfidence,
            assistedConfidence: assisted.confidenceBucket,
            replacedPrice: shouldTrustModelCandidate
        )

        return OCRResult(
            rawText: snapshot.rawText,
            itemNameHint: finalItemName,
            price: finalPrice,
            unit: snapshot.detectedUnit,
            quantity: finalQuantity,
            confidence: finalConfidence,
            priceCandidates: snapshot.priceCandidates,
            supportingLines: finalLines
        )
    }

    func encodeForPrompt<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard
            let data = try? encoder.encode(value),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return string
    }

    func normalizedCanonicalItemName(
        from assisted: PriceParsingService.AssistedExtractionResult,
        snapshot: PriceParsingService.HeuristicExtractionSnapshot
    ) -> String? {
        if let name = assisted.canonicalItemName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        let selectedLines = supportingLines(from: assisted.targetLineIndexes, snapshot: snapshot)
        return selectedLines.first { line in
            !line.contains("$") && !line.contains(where: \.isNumber)
        }
    }

    func supportingLines(
        from targetLineIndexes: [Int],
        snapshot: PriceParsingService.HeuristicExtractionSnapshot
    ) -> [String] {
        let lines = targetLineIndexes.compactMap { index in
            snapshot.consolidatedObservations.indices.contains(index)
                ? snapshot.consolidatedObservations[index].string
                : nil
        }

        return lines.isEmpty ? snapshot.consolidatedObservations.map(\.string) : lines
    }

    func mergedConfidence(
        heuristicConfidence: Float,
        assistedConfidence: PriceParsingService.AssistedConfidenceBucket,
        replacedPrice: Bool
    ) -> Float {
        let modelAdjustment: Float
        switch assistedConfidence {
        case .low:
            modelAdjustment = -0.05
        case .medium:
            modelAdjustment = 0.03
        case .high:
            modelAdjustment = 0.08
        }

        let replacementAdjustment: Float = replacedPrice ? 0.02 : 0
        return min(1, max(0.1, heuristicConfidence + modelAdjustment + replacementAdjustment))
    }
}

extension PriceParsingService {
    enum AssistedPriceKind: String, Codable, Sendable {
        case sale
        case regular
        case unitPrice
        case deposit
        case noise
        case unknown
    }

    enum AssistedConfidenceBucket: String, Codable, Sendable {
        case low
        case medium
        case high
    }

    struct PromptLineContext: Codable, Sendable {
        let index: Int
        let text: String
        let confidence: Float
    }

    struct PromptPriceCandidateContext: Codable, Sendable {
        let index: Int
        let value: String
        let quantity: String?
        let confidence: Float
        let priority: Int
        let label: String
        let sourceText: String
        let sourceLineIndexes: [Int]
    }

    @Generable
    struct AssistedExtractionResponse: Sendable {
        let targetLineIndexes: [Int]
        let selectedPriceCandidateIndex: Int?
        let selectedPriceKind: String
        let canonicalItemName: String?
        let ambiguityNotes: [String]
        let confidenceBucket: String
    }

    struct AssistedExtractionResult: Sendable {
        let targetLineIndexes: [Int]
        let selectedPriceCandidateIndex: Int?
        let selectedPriceKind: AssistedPriceKind
        let canonicalItemName: String?
        let ambiguityNotes: [String]
        let confidenceBucket: AssistedConfidenceBucket
    }

    static func resolveWithFoundationModel(
        snapshot: HeuristicExtractionSnapshot,
        ambiguity: ExtractionAmbiguityReport
    ) async throws -> AssistedExtractionResult? {
        try await PriceParsingAssistedExtractor().resolveWithFoundationModel(
            snapshot: snapshot,
            ambiguity: ambiguity
        )
    }

    static func buildAssistedExtractionPrompt(
        snapshot: HeuristicExtractionSnapshot,
        ambiguity: ExtractionAmbiguityReport
    ) -> String {
        PriceParsingAssistedExtractor().buildAssistedExtractionPrompt(
            snapshot: snapshot,
            ambiguity: ambiguity
        )
    }

    static func mergeAssistedExtraction(
        snapshot: HeuristicExtractionSnapshot,
        assisted: AssistedExtractionResult
    ) -> OCRResult {
        PriceParsingAssistedExtractor().mergeAssistedExtraction(
            snapshot: snapshot,
            assisted: assisted
        )
    }

    static func encodeForPrompt<T: Encodable>(_ value: T) -> String {
        PriceParsingAssistedExtractor().encodeForPrompt(value)
    }

    static func normalizedCanonicalItemName(
        from assisted: AssistedExtractionResult,
        snapshot: HeuristicExtractionSnapshot
    ) -> String? {
        PriceParsingAssistedExtractor().normalizedCanonicalItemName(
            from: assisted,
            snapshot: snapshot
        )
    }

    static func supportingLines(
        from targetLineIndexes: [Int],
        snapshot: HeuristicExtractionSnapshot
    ) -> [String] {
        PriceParsingAssistedExtractor().supportingLines(
            from: targetLineIndexes,
            snapshot: snapshot
        )
    }

    static func mergedConfidence(
        heuristicConfidence: Float,
        assistedConfidence: AssistedConfidenceBucket,
        replacedPrice: Bool
    ) -> Float {
        PriceParsingAssistedExtractor().mergedConfidence(
            heuristicConfidence: heuristicConfidence,
            assistedConfidence: assistedConfidence,
            replacedPrice: replacedPrice
        )
    }
}
