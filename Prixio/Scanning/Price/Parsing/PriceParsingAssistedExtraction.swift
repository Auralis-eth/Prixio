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
        let clusterContext = snapshot.evidenceClusters.enumerated().map { index, cluster in
            PriceParsingService.PromptClusterContext(
                index: index,
                role: cluster.role.rawValue,
                score: cluster.score,
                itemNameHint: cluster.itemNameHint,
                lineIndexes: sourceLineIndexes(for: cluster, in: snapshot),
                lines: cluster.lines,
                priceCandidateValues: cluster.priceCandidates.map { "\($0.value)" }
            )
        }

        let encodedLines = encodeForPrompt(lineContext)
        let encodedCandidates = encodeForPrompt(candidateContext)
        let encodedClusters = encodeForPrompt(clusterContext)
        let weaknessList = ambiguity.weaknesses.map(\.rawValue).joined(separator: ", ")

        return """
        OCR lines:
        \(encodedLines)

        Price candidates:
        \(encodedCandidates)

        Evidence clusters:
        \(encodedClusters)

        Current heuristic item name hint: \(snapshot.itemNameHint ?? "nil")
        Current heuristic unit: \(snapshot.detectedUnit?.rawValue ?? "nil")
        Current heuristic quantity: \(snapshot.resolvedQuantity.map { "\($0)" } ?? "nil")
        Current heuristic confidence: \(snapshot.heuristicConfidence)
        Scene classification: \(snapshot.sceneClassification.rawValue)
        Winning cluster index: \(snapshot.winningClusterIndex.map(String.init) ?? "nil")
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

    func shouldSkipFoundationModelEscalation(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        ambiguity: PriceParsingService.ExtractionAmbiguityReport
    ) -> Bool {
        let severeWeaknesses: Set<PriceParsingService.ExtractionWeakness> = [
            .noPriceCandidates,
            .multipleCompetingPrices,
            .possibleMultiProductScan
        ]
        guard severeWeaknesses.isDisjoint(with: ambiguity.weaknesses) else {
            return false
        }

        guard snapshot.sceneClassification == .singleTag else {
            return false
        }
        guard snapshot.itemNameHint?.isEmpty == false else {
            return false
        }
        guard !snapshot.priceCandidates.isEmpty else {
            return false
        }
        guard let winningClusterIndex = snapshot.winningClusterIndex,
              snapshot.evidenceClusters.indices.contains(winningClusterIndex) else {
            return false
        }
        guard snapshot.evidenceClusters[winningClusterIndex].role == .productText else {
            return false
        }

        let confidence = PriceParsingConfidenceResolver().assembleHeuristicConfidence(
            snapshot: snapshot,
            ambiguity: ambiguity,
            ocrConfidence: PriceParsingConfidenceResolver().ocrEvidenceConfidence(snapshot: snapshot),
            parseConfidence: PriceParsingConfidenceResolver().parseStructureConfidence(snapshot: snapshot)
        )
        return confidence >= 0.8
    }

    func mergeAssistedExtraction(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        assisted: PriceParsingService.AssistedExtractionResult
    ) -> OCRResult {
        let heuristicResult = PriceParsingConfidenceResolver().makeOCRResult(from: snapshot)
        let ambiguity = PriceParsingConfidenceResolver().analyzeAmbiguity(in: snapshot)
        let topHeuristicCandidate = snapshot.priceCandidates.first
        let selectedCandidate = assisted.selectedPriceCandidateIndex.flatMap { index in
            snapshot.priceCandidates.indices.contains(index) ? snapshot.priceCandidates[index] : nil
        }
        let shouldTrustModelCandidate = assisted.confidenceBucket != .low
            && selectedCandidate != nil
            && isTrustedPriceKind(assisted.selectedPriceKind)
            && shouldPreferModelCandidate(
                selectedCandidate: selectedCandidate,
                heuristicCandidate: topHeuristicCandidate,
                targetLineIndexes: assisted.targetLineIndexes,
                snapshot: snapshot
            )
        let shouldTrustModelName = assisted.confidenceBucket != .low

        let finalPrice = shouldTrustModelCandidate ? selectedCandidate?.value : heuristicResult.price
        let finalQuantity = shouldTrustModelCandidate
            ? (selectedCandidate?.quantity ?? snapshot.resolvedQuantity)
            : heuristicResult.quantity
        let modelItemName = shouldTrustModelName
            ? (normalizedCanonicalItemName(
                from: assisted,
                snapshot: snapshot
            ) ?? heuristicResult.itemNameHint)
            : heuristicResult.itemNameHint
        let finalItemName = preferredItemName(
            heuristicItemName: heuristicResult.itemNameHint,
            modelItemName: modelItemName
        )
        let finalLines = supportingLines(from: assisted.targetLineIndexes, snapshot: snapshot)
        let filteredFinalLines = filteredSupportingLines(
            finalLines,
            canonicalItemName: assisted.canonicalItemName
        )
        let agreementAdjustment = agreementConfidenceAdjustment(
            heuristicResult: heuristicResult,
            selectedCandidate: selectedCandidate,
            finalItemName: finalItemName,
            finalLines: filteredFinalLines,
            trustedModelCandidate: shouldTrustModelCandidate,
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
            itemNameEvidence: snapshot.itemNameEvidence,
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
            supportingLines: filteredFinalLines
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
        return mergedSupportedItemName(from: selectedLines)
            ?? selectedLines.first { line in
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

    func sourceLineIndexes(
        for cluster: PriceParsingService.EvidenceCluster,
        in snapshot: PriceParsingService.HeuristicExtractionSnapshot
    ) -> [Int] {
        cluster.lines.compactMap { line in
            snapshot.consolidatedObservations.firstIndex { $0.string == line }
        }
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

    func shouldPreferModelCandidate(
        selectedCandidate: PriceCandidate?,
        heuristicCandidate: PriceCandidate?,
        targetLineIndexes: [Int],
        snapshot: PriceParsingService.HeuristicExtractionSnapshot
    ) -> Bool {
        guard let selectedCandidate else {
            return false
        }
        guard let heuristicCandidate else {
            return true
        }
        guard selectedCandidate != heuristicCandidate else {
            return true
        }

        let scorer = PriceCandidateScorer()
        let selectedIndexes = PriceParsingConfidenceResolver().sourceLineIndexes(
            for: selectedCandidate,
            in: snapshot.consolidatedObservations
        )
        if scorer.nearbySavePenalty(
            candidate: selectedCandidate,
            sourceLineIndexes: selectedIndexes,
            observations: snapshot.consolidatedObservations
        ) > 0 {
            return false
        }

        let heuristicIndexes = PriceParsingConfidenceResolver().sourceLineIndexes(
            for: heuristicCandidate,
            in: snapshot.consolidatedObservations
        )
        let targetLineSet = Set(targetLineIndexes)
        let selectedAlignedWithTarget = !targetLineSet.isDisjoint(with: selectedIndexes)
        let heuristicAlignedWithTarget = !targetLineSet.isDisjoint(with: heuristicIndexes)
        if selectedAlignedWithTarget && !heuristicAlignedWithTarget {
            return true
        }

        if selectedCandidate.priority < heuristicCandidate.priority {
            return false
        }
        if selectedCandidate.priority == heuristicCandidate.priority,
           selectedCandidate.confidence < heuristicCandidate.confidence {
            return false
        }

        return true
    }

    func agreementConfidenceAdjustment(
        heuristicResult: OCRResult,
        selectedCandidate: PriceCandidate?,
        finalItemName: String?,
        finalLines: [String],
        trustedModelCandidate: Bool,
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

        if trustedModelCandidate {
            adjustment += 0.03
        } else if selectedCandidate != nil {
            adjustment -= 0.02
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

    func filteredSupportingLines(
        _ lines: [String],
        canonicalItemName: String?
    ) -> [String] {
        guard canonicalItemName != nil else {
            return lines
        }

        let filtered = lines.filter { line in
            let trimmed = line.sanitizeOCRLine()
            if PriceParsingService.containsPriceSignal(in: trimmed) {
                return true
            }
            if PriceParsingService.containsExplicitSizeToken(in: trimmed) {
                return true
            }
            return trimmed.digitsAsLettersCount() < 2
        }

        return filtered.isEmpty ? lines : filtered
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

    func preferredItemName(
        heuristicItemName: String?,
        modelItemName: String?
    ) -> String? {
        guard let heuristicNormalized = normalizedComparisonText(heuristicItemName) else {
            return modelItemName
        }
        guard let modelNormalized = normalizedComparisonText(modelItemName) else {
            return heuristicItemName
        }

        if heuristicNormalized == modelNormalized {
            return heuristicItemName ?? modelItemName
        }

        if heuristicNormalized.contains(modelNormalized),
           heuristicNormalized.count > modelNormalized.count {
            return heuristicItemName
        }

        return modelItemName
    }

    func mergedSupportedItemName(from lines: [String]) -> String? {
        let fragments = lines.compactMap(cleanItemNameFragment)
        guard let firstFragment = fragments.first else {
            return nil
        }

        return fragments.dropFirst().reduce(firstFragment) { partialResult, fragment in
            mergeNameFragments(partialResult, fragment)
        }
    }

    func cleanItemNameFragment(_ line: String) -> String? {
        let trimmed = line.sanitizeOCRLine()
        guard !trimmed.isEmpty else {
            return nil
        }
        guard !PriceParsingService.containsPriceSignal(in: trimmed) else {
            return nil
        }

        let itemResolver = PriceParsingItemNameResolver()
        guard !itemResolver.looksLikeReceiptFragment(trimmed) else {
            return nil
        }
        guard !itemResolver.looksLikePromoBanner(trimmed) else {
            return nil
        }

        let strippedSizeSuffix = trimmed.replacingOccurrences(
            of: #"\s+\d{1,4}(?:[.,]\d+)?\s*(g|kg|ml|l|oz|lb|pk|ct|count|pack)\b.*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let cleaned = PriceParsingItemNameResolver().cleanedProductPhrase(from: strippedSizeSuffix)
        guard cleaned.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return nil
        }

        return cleaned
    }

    func mergeNameFragments(_ lhs: String, _ rhs: String) -> String {
        let lhsTokens = lhs.split(whereSeparator: \.isWhitespace).map(String.init)
        let rhsTokens = rhs.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !lhsTokens.isEmpty else {
            return rhs
        }
        guard !rhsTokens.isEmpty else {
            return lhs
        }

        let overlap = maximumTokenOverlap(lhsTokens: lhsTokens, rhsTokens: rhsTokens)
        let mergedTokens = lhsTokens + rhsTokens.dropFirst(overlap)
        return mergedTokens.joined(separator: " ")
    }

    func maximumTokenOverlap(lhsTokens: [String], rhsTokens: [String]) -> Int {
        let maxOverlap = min(lhsTokens.count, rhsTokens.count)
        guard maxOverlap > 0 else {
            return 0
        }

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let lhsSuffix = lhsTokens.suffix(overlap).map {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
            }
            let rhsPrefix = rhsTokens.prefix(overlap).map {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
            }
            if lhsSuffix == rhsPrefix {
                return overlap
            }
        }

        return 0
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

    struct PromptClusterContext: Codable, Sendable {
        let index: Int
        let role: String
        let score: Float
        let itemNameHint: String?
        let lineIndexes: [Int]
        let lines: [String]
        let priceCandidateValues: [String]
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

    static func _test_shouldSkipFoundationModelEscalation(
        _ observations: [OCRTextObservation]
    ) -> Bool {
        let snapshot = PriceParsingSnapshotBuilder().buildHeuristicSnapshot(from: observations)
        let ambiguity = PriceParsingConfidenceResolver().analyzeAmbiguity(in: snapshot)
        return PriceParsingAssistedExtractor().shouldSkipFoundationModelEscalation(
            snapshot: snapshot,
            ambiguity: ambiguity
        )
    }
}
