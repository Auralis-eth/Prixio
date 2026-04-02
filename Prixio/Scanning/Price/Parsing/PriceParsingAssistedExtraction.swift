//
//  PriceParsingAssistedExtraction.swift
//  Prixio
//

import Foundation
import FoundationModels

struct PriceParsingAssistedExtractor {
    let instructions = """
    Help with ambiguous grocery shelf-tag OCR.
    Select only from the provided OCR lines and provided price candidates.
    Prefer one target product, not the whole frame.
    Never invent prices, line indexes, quantities, or product names.
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
        return makeAssistedExtractionResult(
            from: response.content,
            lineCount: snapshot.consolidatedObservations.count,
            candidateCount: snapshot.priceCandidates.count
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
                sourceLineIndexes: PriceParsingConfidenceResolver().sourceLineIndexes(for: candidate, in: snapshot)
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

        Response contract:
        - `targetLineIndexes` must be existing OCR line indexes only, sorted ascending, and limited to lines for one product.
        - `selectedPriceCandidateIndex` must be an existing candidate index or `nil`.
        - `selectedPriceKind` must classify the selected candidate. Use `unknown` when no candidate should be selected.
        - `canonicalItemName` must be `nil` unless the chosen lines support a clear product name.
        - `ambiguityNotes` should be short phrases, not prose.
        - Never invent missing values.
        """
    }

    func mergeAssistedExtraction(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        assisted: PriceParsingService.AssistedExtractionResult
    ) -> OCRResult {
        let heuristicResult = PriceParsingConfidenceResolver().makeOCRResult(from: snapshot)
        let ambiguity = PriceParsingConfidenceResolver().analyzeAmbiguity(in: snapshot)
        let selectedCandidate = assisted.selectedPriceCandidateIndex.flatMap { index in
            snapshot.priceCandidates.indices.contains(index) ? snapshot.priceCandidates[index] : nil
        }
        let shouldTrustModelCandidate = assisted.confidenceBucket != .low
            && selectedCandidate != nil
            && isTrustedPriceKind(assisted.selectedPriceKind)
        let shouldTrustModelName = assisted.confidenceBucket != .low

        let finalPrice = shouldTrustModelCandidate ? selectedCandidate?.value : heuristicResult.price
        let finalQuantity = shouldTrustModelCandidate
            ? (selectedCandidate?.quantity ?? snapshot.resolvedQuantity)
            : heuristicResult.quantity
        let finalItemName = shouldTrustModelName
            ? (normalizedCanonicalItemName(
                from: assisted,
                snapshot: snapshot
            ) ?? heuristicResult.itemNameHint)
            : heuristicResult.itemNameHint
        let finalLines = supportingLines(from: assisted.targetLineIndexes, snapshot: snapshot)
        let agreementAdjustment = agreementConfidenceAdjustment(
            heuristicResult: heuristicResult,
            selectedCandidate: selectedCandidate,
            finalItemName: finalItemName,
            finalLines: finalLines,
            replacedPrice: shouldTrustModelCandidate
        )
        let finalConfidence = mergedConfidence(
            heuristicConfidence: heuristicResult.confidence ?? snapshot.heuristicConfidence,
            assistedConfidence: assisted.confidenceBucket,
            replacedPrice: shouldTrustModelCandidate,
            agreementAdjustment: agreementAdjustment
        )

        return OCRResult(
            rawText: snapshot.rawText,
            itemNameHint: finalItemName,
            price: finalPrice,
            unit: snapshot.detectedUnit,
            quantity: finalQuantity,
            confidence: finalConfidence,
            priceCandidates: snapshot.priceCandidates,
            review: OCRReview(
                ambiguity: ambiguity,
                usedFoundationModel: true,
                ambiguityNotes: assisted.ambiguityNotes
            ),
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

    func makeAssistedExtractionResult(
        from response: PriceParsingService.AssistedExtractionResponse,
        lineCount: Int,
        candidateCount: Int
    ) -> PriceParsingService.AssistedExtractionResult {
        let selectedPriceCandidateIndex = normalizedSelectedCandidateIndex(
            response.selectedPriceCandidateIndex,
            candidateCount: candidateCount
        )
        let selectedPriceKind: PriceParsingService.AssistedPriceKind = {
            guard selectedPriceCandidateIndex != nil else {
                return .unknown
            }
            return response.selectedPriceKind
        }()

        return PriceParsingService.AssistedExtractionResult(
            targetLineIndexes: normalizedLineIndexes(response.targetLineIndexes, lineCount: lineCount),
            selectedPriceCandidateIndex: selectedPriceCandidateIndex,
            selectedPriceKind: selectedPriceKind,
            canonicalItemName: normalizedCanonicalItemName(response.canonicalItemName),
            ambiguityNotes: normalizedAmbiguityNotes(response.ambiguityNotes),
            confidenceBucket: response.confidenceBucket
        )
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
        replacedPrice: Bool,
        agreementAdjustment: Float
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
        return min(1, max(0.1, heuristicConfidence + modelAdjustment + replacementAdjustment + agreementAdjustment))
    }

    func normalizedLineIndexes(_ indexes: [Int], lineCount: Int) -> [Int] {
        Array(Set(indexes.filter { (0..<lineCount).contains($0) })).sorted()
    }

    func normalizedSelectedCandidateIndex(_ index: Int?, candidateCount: Int) -> Int? {
        guard let index, (0..<candidateCount).contains(index) else {
            return nil
        }
        return index
    }

    func normalizedCanonicalItemName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    func normalizedAmbiguityNotes(_ notes: [String]) -> [String] {
        let trimmed = notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(trimmed.prefix(3))
    }

    func isTrustedPriceKind(_ kind: PriceParsingService.AssistedPriceKind) -> Bool {
        switch kind {
        case .sale, .regular, .unitPrice:
            return true
        case .deposit, .noise, .unknown:
            return false
        }
    }

    func agreementConfidenceAdjustment(
        heuristicResult: OCRResult,
        selectedCandidate: PriceCandidate?,
        finalItemName: String?,
        finalLines: [String],
        replacedPrice: Bool
    ) -> Float {
        var adjustment: Float = 0

        if let selectedCandidate {
            if selectedCandidate.value == heuristicResult.price {
                adjustment += 0.03
            } else {
                adjustment -= replacedPrice ? 0.04 : 0.08
            }
        }

        if normalizedComparisonText(finalItemName) == normalizedComparisonText(heuristicResult.itemNameHint) {
            adjustment += 0.02
        } else if finalItemName != nil, heuristicResult.itemNameHint != nil {
            adjustment -= 0.02
        }

        if finalLines == heuristicResult.supportingLines {
            adjustment += 0.01
        } else if !finalLines.isEmpty {
            adjustment -= 0.01
        }

        return adjustment
    }

    func normalizedComparisonText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let lowered = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lowered.isEmpty ? nil : lowered
    }
}

extension PriceParsingService {
    @Generable(description: "How the chosen price candidate should be interpreted")
    enum AssistedPriceKind: String, Codable, Sendable {
        case sale
        case regular
        case unitPrice
        case deposit
        case noise
        case unknown
    }

    @Generable(description: "How strongly the model believes the constrained answer is supported by the OCR evidence")
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

    @Generable(description: "Constrained assisted extraction result for one ambiguous grocery shelf tag")
    struct AssistedExtractionResponse: Sendable {
        @Guide(description: "Existing OCR line indexes that belong to one target product")
        let targetLineIndexes: [Int]

        @Guide(description: "Existing price candidate index to trust, or nil if none should be selected")
        let selectedPriceCandidateIndex: Int?

        @Guide(description: "How to interpret the selected price candidate")
        let selectedPriceKind: AssistedPriceKind

        @Guide(description: "Canonical product name only when supported by the selected OCR lines")
        let canonicalItemName: String?

        @Guide(description: "Up to three short ambiguity notes")
        let ambiguityNotes: [String]

        @Guide(description: "How confident the model is in this constrained extraction")
        let confidenceBucket: AssistedConfidenceBucket
    }

    struct AssistedExtractionResult: Sendable {
        let targetLineIndexes: [Int]
        let selectedPriceCandidateIndex: Int?
        let selectedPriceKind: AssistedPriceKind
        let canonicalItemName: String?
        let ambiguityNotes: [String]
        let confidenceBucket: AssistedConfidenceBucket
    }

    static func _test_makeAssistedExtractionResult(
        from response: AssistedExtractionResponse,
        lineCount: Int,
        candidateCount: Int
    ) -> AssistedExtractionResult {
        PriceParsingAssistedExtractor().makeAssistedExtractionResult(
            from: response,
            lineCount: lineCount,
            candidateCount: candidateCount
        )
    }
}
