//
//  PriceParsingService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreGraphics
import Foundation
import FoundationModels

enum PriceParsingService {

    private struct VocabularySignal {
        var frequency: Int
        var lineIndexes: [Int]
    }

    struct SpatialObservationGroup: Sendable {
        let observations: [OCRTextObservation]
        let score: Float
    }

    struct HeuristicExtractionSnapshot: Sendable {
        let supportedObservations: [OCRTextObservation]
        let spatialGroups: [SpatialObservationGroup]
        let cleanedObservations: [OCRTextObservation]
        let normalizedObservations: [OCRTextObservation]
        let consolidatedObservations: [OCRTextObservation]
        let rawText: String
        let normalizedText: String
        let lines: [String]
        let priceCandidates: [PriceCandidate]
        let detectedUnit: UnitType?
        let itemNameHint: String?
        let resolvedQuantity: Decimal?
        let heuristicConfidence: Float
    }

    enum ExtractionWeakness: String, CaseIterable, Sendable {
        case noPriceCandidates
        case multipleCompetingPrices
        case missingItemName
        case missingUnit
        case missingQuantity
        case lowConfidence
        case sparseOCR
        case possibleMultiProductScan
    }

    struct ExtractionAmbiguityReport: Sendable {
        let weaknesses: [ExtractionWeakness]

        var shouldUseFoundationModel: Bool {
            let severeWeaknesses: Set<ExtractionWeakness> = [
                .noPriceCandidates,
                .multipleCompetingPrices,
                .possibleMultiProductScan
            ]
            if !severeWeaknesses.isDisjoint(with: weaknesses) {
                return true
            }

            let moderateWeaknesses = weaknesses.filter { weakness in
                !severeWeaknesses.contains(weakness)
            }
            return moderateWeaknesses.count >= 2
        }
    }

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

    private static let currencyPattern = #"\$?\s*(\d+[.,]\d{2})"#
    private static let multiBuyPattern = #"(\d+)\s*(?:/|for)\s*\$?\s*(\d+(?:[.,]\d{2})?)"#
    private static let splitCurrencyPattern = #"(^|[^\d])(\d{1,3})\s*(?:\n|\s)\s*(\d{2})(?=$|[^\d])"#
    private static let impliedCurrencyPattern = #"(^|[^\d])(\d{3,4})(?=$|[^\d])"#
    private static let simplePricePattern = #"\$?\s*\d+[.,]\d{2}"#
    private static let quantityFractionPattern = #"\b(\d+)\s*/\s*(\d+)\s*(?:lb|lbs|kg|l|liter|litre)\b"#
    private static let quantityDecimalPattern = #"\b(\d+(?:[.,]\d+)?)\s*(?:lb|lbs|kg|l|liter|litre)\b"#
    private static let monthNamePattern = #"\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b"#
    private static let shelfCodePattern = #"^[A-Z0-9]{2,}(?:[/\-][A-Z0-9]{2,})+$"#
    private static let skuLikeTokenPattern = #"^[A-Z]*\d+[A-Z\d\-\/]*$"#
    private static let poundsPerKilogram = Decimal(string: "2.2046226218")!
    private static let supportedOCRLinePattern = #"^[\p{Latin}\p{N}\p{P}\p{Sc}\p{Zs}]+$"#
    private static let explicitTokenCorrections: [String: String] = [
        "tutch": "dutch",
        "sparkli": "sparkling",
        "chese": "cheese",
        "chees": "cheese",
        "bbqma": "bbq"
    ]
    private static let receiptMarkers = [
        "subtotal",
        "total",
        "tax",
        "hst",
        "gst",
        "change",
        "thank you",
        "receipt",
        "visa",
        "mastercard"
    ]
    private static let assistedExtractionInstructions = """
    You are helping parse OCR text from grocery shelf labels into structured product pricing data.
    Pick the OCR lines most likely to describe one target product.
    Choose only from the provided price candidates.
    Prefer product-level prices over deposits, fees, or unrelated numbers.
    Do not invent prices, line indexes, or product names that are not supported by the OCR evidence.
    """

    /// Converts raw OCR observations into a best-effort structured grocery price result.
    ///
    /// Conceptually, this method runs a parsing pipeline over noisy OCR text: it keeps
    /// lines that look relevant, removes obvious junk, applies OCR-specific
    /// normalization, and consolidates fragmented observations into more coherent text.
    /// From that cleaner input, it extracts likely price candidates, detects the unit
    /// of measure, estimates quantity, and surfaces a likely item-name hint.
    ///
    /// The final `OCRResult` preserves the raw OCR text while also returning the most
    /// plausible structured values and the supporting lines used to infer them.
    ///
    /// - Parameter observations: Raw text observations returned by the OCR layer.
    /// - Returns: A normalized `OCRResult` containing the most likely price metadata
    ///   inferred from those observations.
    static func extract(from observations: [OCRTextObservation]) async -> OCRResult {
        // Foundation Models reference notes:
        // - Use `LanguageModelSession` as a second-pass parser when heuristics produce
        //   weak or ambiguous results, not as a replacement for deterministic parsing.
        // - Prefer guided generation with a typed `@Generable` response so the model
        //   returns structured fields instead of free-form prose.
        // - Strong early use cases:
        //   1. Rank existing price candidates as sale, regular, unit, deposit, or noise.
        //   2. Select the OCR lines that belong to the target product and normalize them
        //      into a canonical item name.
        //   3. Interpret promo semantics like "2/$5", "3 for $10", BOGO, and pack sizes.
        //   4. Repair noisy OCR line-by-line while preserving a mapping to the originals.
        // - If tool calling is added later, use it only for deterministic helpers such as
        //   unit normalization, candidate scoring helpers, or known-brand lookups.
        // - Final confidence should be derived from agreement between heuristic parsing
        //   and model output, not from trusting a raw model score directly.
        let snapshot = buildHeuristicSnapshot(from: observations)
        let ambiguity = analyzeAmbiguity(in: snapshot)
        let heuristicResult = makeOCRResult(from: snapshot)

        guard ambiguity.shouldUseFoundationModel else {
            return heuristicResult
        }

        guard let assisted = try? await resolveWithFoundationModel(snapshot: snapshot, ambiguity: ambiguity) else {
            return heuristicResult
        }

        return mergeAssistedExtraction(snapshot: snapshot, assisted: assisted)
    }

    private static func buildHeuristicSnapshot(from observations: [OCRTextObservation]) -> HeuristicExtractionSnapshot {
        // TODO: Teach the snapshot phase to use bounding boxes and reading order when it
        // groups OCR lines. The current preparation step is text-only, so it can mix the
        // target label with neighboring products when OCR captures multiple shelf tags at once.
        let supportedObservations = orderObservationsInReadingOrder(observations.filter {
            isSupportedOCRLine($0.string)
        })
        let spatialGroups = makeSpatialObservationGroups(from: supportedObservations)
        let strongestGroupObservations = spatialGroups.first?.observations ?? supportedObservations
        let focusedObservations = strongestGroupObservations
        let cleanedObservations = bestAvailableObservations(
            focusedObservations: focusedObservations,
            strongestGroupObservations: strongestGroupObservations,
            supportedObservations: supportedObservations
        )
        // TODO: Expand snapshot normalization to handle more OCR confusions and locale
        // variants, especially merged tokens, missing currency symbols, and
        // decimal-thousands ambiguity.
        let normalizedObservations = applyContextualNormalization(to: cleanedObservations)
        let consolidatedObservations = normalizedObservations.consolidateObservations()
        let supportedLines = consolidatedObservations.isEmpty ? normalizedObservations : consolidatedObservations
        let rawText = supportedLines.map(\.string).joined(separator: "\n")
        let normalizedText = rawText.replacingOccurrences(of: ",", with: ".")
        let unitScopeText = supportedLines.map(\.string).joined(separator: "\n")
        // TODO: Upgrade snapshot candidate scoring with stronger context signals such as
        // proximity to product text, promotional markers, "each"/unit labels, and
        // sale-vs-regular price rules.
        let consolidatedPriceCandidates = extractPriceCandidates(from: consolidatedObservations)
        let priceCandidates = consolidatedPriceCandidates.isEmpty
            ? extractPriceCandidates(from: normalizedObservations)
            : consolidatedPriceCandidates
        // TODO: Make snapshot unit detection handle compound and normalized units more
        // robustly, including multi-pack counts, mixed-unit labels, and "price per"
        // phrases split across lines.
        let detectedUnit = detectUnit(in: unitScopeText.isEmpty ? normalizedText : unitScopeText)
        let lines = (unitScopeText.isEmpty ? normalizedText : unitScopeText)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // TODO: Replace this snapshot item-name shortcut with a scored extractor that can
        // keep branded product text even when it contains numbers, sizes, or promo words.
        let itemNameHint = lines.first { line in
            !line.contains("$") && detectUnit(in: line) == nil && !line.contains(where: { $0.isNumber })
        }
        // TODO: Let the snapshot phase infer quantities from offer patterns like "2/$5",
        // "3 for $10", "buy one get one", and pack-size notation instead of relying on a
        // single candidate or plain unit parsing.
        let resolvedQuantity = priceCandidates.first?.quantity ?? detectQuantity(
            in: unitScopeText.isEmpty ? normalizedText : unitScopeText,
            unit: detectedUnit
        )
        let heuristicConfidence = priceCandidates.first?.confidence ?? averageConfidence(in: consolidatedObservations) ?? 0.1

        return HeuristicExtractionSnapshot(
            supportedObservations: supportedObservations,
            spatialGroups: spatialGroups,
            cleanedObservations: cleanedObservations,
            normalizedObservations: normalizedObservations,
            consolidatedObservations: supportedLines,
            rawText: rawText,
            normalizedText: normalizedText,
            lines: lines,
            priceCandidates: priceCandidates,
            detectedUnit: detectedUnit,
            itemNameHint: itemNameHint,
            resolvedQuantity: resolvedQuantity,
            heuristicConfidence: heuristicConfidence
        )
    }

    private static func shouldFallbackFromFocusedObservations(
        sourceObservations: [OCRTextObservation],
        cleanedObservations: [OCRTextObservation]
    ) -> Bool {
        guard !sourceObservations.isEmpty else {
            return false
        }

        guard !cleanedObservations.isEmpty else {
            return true
        }

        let sourceHasPriceSignal = sourceObservations.contains { containsPriceSignal(in: $0.string) }
        let cleanedHasPriceSignal = cleanedObservations.contains { containsPriceSignal(in: $0.string) }
        if sourceHasPriceSignal && !cleanedHasPriceSignal {
            return true
        }

        let sourceHasDescription = sourceObservations.contains { isDescriptiveObservation($0) }
        let cleanedHasDescription = cleanedObservations.contains { isDescriptiveObservation($0) }
        if sourceHasDescription && !cleanedHasDescription {
            return true
        }

        if sourceObservations.count >= 2 && cleanedObservations.count < 2 && (sourceHasPriceSignal || sourceHasDescription) {
            return true
        }

        return false
    }

    private static func makeFallbackObservationSet(
        focusedObservations: [OCRTextObservation],
        strongestGroupObservations: [OCRTextObservation],
        supportedObservations: [OCRTextObservation]
    ) -> [(source: [OCRTextObservation], cleaned: [OCRTextObservation])] {
        [
            (
                source: focusedObservations,
                cleaned: removeObviousNoise(from: focusedObservations)
            ),
            (
                source: strongestGroupObservations,
                cleaned: removeObviousNoise(from: strongestGroupObservations)
            ),
            (
                source: supportedObservations,
                cleaned: removeObviousNoise(from: supportedObservations)
            ),
            (
                source: minimallySanitizedObservations(from: supportedObservations),
                cleaned: minimallySanitizedObservations(from: supportedObservations)
            )
        ]
    }

    private static func bestAvailableObservations(
        focusedObservations: [OCRTextObservation],
        strongestGroupObservations: [OCRTextObservation],
        supportedObservations: [OCRTextObservation]
    ) -> [OCRTextObservation] {
        let fallbackSets = makeFallbackObservationSet(
            focusedObservations: focusedObservations,
            strongestGroupObservations: strongestGroupObservations,
            supportedObservations: supportedObservations
        )

        for fallback in fallbackSets {
            if !shouldFallbackFromFocusedObservations(
                sourceObservations: fallback.source,
                cleanedObservations: fallback.cleaned
            ) {
                return fallback.cleaned
            }
        }

        return fallbackSets.last?.cleaned ?? []
    }

    private static func analyzeAmbiguity(in snapshot: HeuristicExtractionSnapshot) -> ExtractionAmbiguityReport {
        var weaknesses: [ExtractionWeakness] = []

        if snapshot.priceCandidates.isEmpty {
            weaknesses.append(.noPriceCandidates)
        }

        if hasCompetingTopCandidates(snapshot.priceCandidates) {
            weaknesses.append(.multipleCompetingPrices)
        }

        if snapshot.itemNameHint?.isEmpty != false {
            weaknesses.append(.missingItemName)
        }

        if snapshot.detectedUnit == nil {
            weaknesses.append(.missingUnit)
        }

        if snapshot.resolvedQuantity == nil && snapshot.detectedUnit != .each {
            weaknesses.append(.missingQuantity)
        }

        if snapshot.heuristicConfidence < 0.45 {
            weaknesses.append(.lowConfidence)
        }

        if snapshot.cleanedObservations.count <= 1 || snapshot.lines.count <= 1 {
            weaknesses.append(.sparseOCR)
        }

        if looksLikeMultiProductScan(snapshot) {
            weaknesses.append(.possibleMultiProductScan)
        }

        return ExtractionAmbiguityReport(weaknesses: weaknesses)
    }

    private static func makeOCRResult(from snapshot: HeuristicExtractionSnapshot) -> OCRResult {
        // TODO: Move confidence assembly beyond the top price candidate. The final result
        // should reflect agreement between snapshot data and ambiguity signals across
        // price, unit, and item parsing.
        OCRResult(
            rawText: snapshot.rawText,
            itemNameHint: snapshot.itemNameHint,
            price: snapshot.priceCandidates.first?.value,
            unit: snapshot.detectedUnit,
            quantity: snapshot.resolvedQuantity,
            confidence: snapshot.heuristicConfidence,
            priceCandidates: snapshot.priceCandidates,
            supportingLines: snapshot.consolidatedObservations.map(\.string)
        )
    }

    private static func resolveWithFoundationModel(
        snapshot: HeuristicExtractionSnapshot,
        ambiguity: ExtractionAmbiguityReport
    ) async throws -> AssistedExtractionResult? {
        guard SystemLanguageModel.default.availability == .available else {
            return nil
        }

        let session = LanguageModelSession(instructions: assistedExtractionInstructions)
        let prompt = buildAssistedExtractionPrompt(snapshot: snapshot, ambiguity: ambiguity)
        let response = try await session.respond(to: prompt, generating: AssistedExtractionResponse.self)
        return AssistedExtractionResult(
            targetLineIndexes: response.content.targetLineIndexes,
            selectedPriceCandidateIndex: response.content.selectedPriceCandidateIndex,
            selectedPriceKind: AssistedPriceKind(rawValue: response.content.selectedPriceKind) ?? .unknown,
            canonicalItemName: response.content.canonicalItemName,
            ambiguityNotes: response.content.ambiguityNotes,
            confidenceBucket: AssistedConfidenceBucket(rawValue: response.content.confidenceBucket) ?? .low
        )
    }

    private static func buildAssistedExtractionPrompt(
        snapshot: HeuristicExtractionSnapshot,
        ambiguity: ExtractionAmbiguityReport
    ) -> String {
        let lineContext = snapshot.consolidatedObservations.enumerated().map { index, observation in
            PromptLineContext(index: index, text: observation.string, confidence: observation.confidence)
        }
        let candidateContext = snapshot.priceCandidates.enumerated().map { index, candidate in
            PromptPriceCandidateContext(
                index: index,
                value: "\(candidate.value)",
                quantity: candidate.quantity.map { "\($0)" },
                confidence: candidate.confidence,
                priority: candidate.priority,
                label: candidate.label,
                sourceText: candidate.sourceText,
                sourceLineIndexes: sourceLineIndexes(for: candidate, in: snapshot)
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

    private static func mergeAssistedExtraction(
        snapshot: HeuristicExtractionSnapshot,
        assisted: AssistedExtractionResult
    ) -> OCRResult {
        let heuristicResult = makeOCRResult(from: snapshot)
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

    private static func isSupportedOCRLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        guard let regex = try? NSRegularExpression(pattern: supportedOCRLinePattern) else {
            return true
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }

    private static func orderObservationsInReadingOrder(_ observations: [OCRTextObservation]) -> [OCRTextObservation] {
        observations.enumerated().sorted { lhs, rhs in
            guard let lhsBox = lhs.element.boundingBox, let rhsBox = rhs.element.boundingBox else {
                return lhs.offset < rhs.offset
            }

            let rowTolerance = max(lhsBox.height, rhsBox.height) * 0.6
            let verticalDelta = abs(lhsBox.midY - rhsBox.midY)
            if verticalDelta > rowTolerance {
                return lhsBox.midY > rhsBox.midY
            }

            if lhsBox.minX != rhsBox.minX {
                return lhsBox.minX < rhsBox.minX
            }

            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    private static func makeSpatialObservationGroups(from observations: [OCRTextObservation]) -> [SpatialObservationGroup] {
        guard observations.contains(where: { $0.boundingBox != nil }) else {
            return observations.isEmpty ? [] : [SpatialObservationGroup(observations: observations, score: spatialGroupScore(for: observations))]
        }

        var groupedObservations: [[OCRTextObservation]] = []

        for observation in observations {
            guard let boundingBox = observation.boundingBox else {
                if groupedObservations.isEmpty {
                    groupedObservations.append([observation])
                } else {
                    groupedObservations[groupedObservations.count - 1].append(observation)
                }
                continue
            }

            if let index = groupedObservations.lastIndex(where: { shouldJoinSpatialGroup(observation: observation, boundingBox: boundingBox, group: $0) }) {
                groupedObservations[index].append(observation)
            } else {
                groupedObservations.append([observation])
            }
        }

        return groupedObservations
            .map { group in
                SpatialObservationGroup(
                    observations: group,
                    score: spatialGroupScore(for: group)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.observations.count > rhs.observations.count
            }
    }

    private static func shouldJoinSpatialGroup(
        observation: OCRTextObservation,
        boundingBox: CGRect,
        group: [OCRTextObservation]
    ) -> Bool {
        guard let groupFrame = spatialFrame(for: group) else {
            return false
        }

        let verticalGap = max(0, groupFrame.minY - boundingBox.maxY, boundingBox.minY - groupFrame.maxY)
        guard verticalGap <= 0.12 else {
            return false
        }

        let horizontalOverlap = groupFrame.intersection(boundingBox).width
        let minimumWidth = min(groupFrame.width, boundingBox.width)
        let overlapRatio = minimumWidth > 0 ? horizontalOverlap / minimumWidth : 0
        let centerDistance = abs(groupFrame.midX - boundingBox.midX)
        let sameColumn = overlapRatio >= 0.35 || centerDistance <= max(groupFrame.width, boundingBox.width) * 0.9

        return sameColumn
    }

    private static func spatialFrame(for observations: [OCRTextObservation]) -> CGRect? {
        observations.compactMap(\.boundingBox).reduce(nil) { partialResult, next in
            guard let partialResult else {
                return next
            }
            return partialResult.union(next)
        }
    }

    private static func spatialGroupScore(for observations: [OCRTextObservation]) -> Float {
        let lineScore = Float(observations.count) * 1.5
        let priceScore = Float(observations.filter { containsPriceSignal(in: $0.string) }.count) * 2
        let descriptiveScore = Float(observations.filter { observation in
            isDescriptiveObservation(observation)
        }.count) * 1.25
        let confidenceScore = observations.map(\.confidence).reduce(0, +) / Float(max(1, observations.count))
        return lineScore + priceScore + descriptiveScore + confidenceScore
    }

    private static func isDescriptiveObservation(_ observation: OCRTextObservation) -> Bool {
        let line = observation.string
        return line.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            && !containsPriceSignal(in: line)
    }

    private static func removeObviousNoise(from observations: [OCRTextObservation]) -> [OCRTextObservation] {
        var seenKeys = Set<String>()

        return observations.compactMap { observation in
            let sanitized = observation.string.sanitizeOCRLine()
            guard !sanitized.isEmpty else {
                return nil
            }

            guard !isObviousNoiseLine(sanitized) else {
                return nil
            }

            let key = sanitized.normalizedWords().joined(separator: " ")
            guard !key.isEmpty else {
                return nil
            }

            guard seenKeys.insert(key).inserted else {
                return nil
            }

            return OCRTextObservation(
                string: sanitized,
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    private static func minimallySanitizedObservations(from observations: [OCRTextObservation]) -> [OCRTextObservation] {
        var seenKeys = Set<String>()

        return observations.compactMap { observation in
            let sanitized = observation.string.sanitizeOCRLine()
            guard !sanitized.isEmpty else {
                return nil
            }

            let normalizedKey = sanitized.comparisonNormalizedWords().joined(separator: " ")
            let key = normalizedKey.isEmpty ? sanitized.lowercased() : normalizedKey
            guard seenKeys.insert(key).inserted else {
                return nil
            }

            return OCRTextObservation(
                string: sanitized,
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    private static func isObviousNoiseLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let words = trimmed.normalizedWords()
        guard !words.isEmpty else {
            return true
        }

        let hasDigits = trimmed.contains(where: \.isNumber)
        let hasLetters = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        let hasPriceSignal = containsPriceSignal(in: trimmed)
        let hasUnitSignal = detectUnit(in: trimmed) != nil || containsExplicitSizeToken(in: trimmed)

        if isLikelyShelfCode(trimmed) || isLikelySKU(trimmed) {
            return true
        }

        if !hasLetters && hasDigits && !hasPriceSignal {
            return true
        }

        if words.count == 1 && !hasPriceSignal && !hasUnitSignal {
            let token = words[0]
            if hasDigits {
                return true
            }
            if token.count <= 3 {
                return true
            }
            if token.count >= 7 && !containsVowel(token) {
                return true
            }
        }

        if words.count == 2 && !hasPriceSignal && !hasUnitSignal && words.allSatisfy({ $0.count <= 3 }) {
            return true
        }

        return false
    }

    private static func containsPriceSignal(in text: String) -> Bool {
        if text.contains("$") {
            return true
        }

        guard let regex = try? NSRegularExpression(pattern: simplePricePattern) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func isLikelyShelfCode(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: shelfCodePattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func isLikelySKU(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 4 else {
            return false
        }
        guard compact.contains(where: \.isNumber) else {
            return false
        }
        guard compact.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return false
        }
        guard let regex = try? NSRegularExpression(pattern: skuLikeTokenPattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(compact.startIndex..., in: compact)
        return regex.firstMatch(in: compact, range: range) != nil
    }

    private static func containsVowel(_ token: String) -> Bool {
        token.range(of: "[aeiou]", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func applyContextualNormalization(to observations: [OCRTextObservation]) -> [OCRTextObservation] {
        let vocabularyFrequency = contextualVocabulary(from: observations)

        return observations.enumerated().map { index, observation in
            let repairedPackText = repairPackSizeNoise(in: observation.string)
            let correctedTokens = repairedPackText
                .split(whereSeparator: \.isWhitespace)
                .map { token in
                    correctedToken(
                        String(token),
                        vocabularyFrequency: vocabularyFrequency,
                        observationConfidence: observation.confidence,
                        lineIndex: index
                    )
                }
                .joined(separator: " ")

            return OCRTextObservation(
                string: correctedTokens.sanitizeOCRLine(),
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    private static func contextualVocabulary(from observations: [OCRTextObservation]) -> [String: VocabularySignal] {
        observations.enumerated().reduce(into: [:]) { frequency, entry in
            let index = entry.offset
            let observation = entry.element
            let words = observation.string.normalizedWords()
            for word in words where word.count >= 4 {
                if var signal = frequency[word] {
                    signal.frequency += 1
                    signal.lineIndexes.append(index)
                    frequency[word] = signal
                } else {
                    frequency[word] = VocabularySignal(frequency: 1, lineIndexes: [index])
                }
            }
        }
    }

    private static func correctedToken(
        _ token: String,
        vocabularyFrequency: [String: VocabularySignal],
        observationConfidence: Float,
        lineIndex: Int
    ) -> String {
        let characterSet = CharacterSet.alphanumerics
        let prefix = String(token.prefix { scalar in
            guard let value = scalar.unicodeScalars.first else {
                return false
            }
            return !characterSet.contains(value)
        })
        let suffix = String(token.reversed().prefix { scalar in
            guard let value = scalar.unicodeScalars.first else {
                return false
            }
            return !characterSet.contains(value)
        }.reversed())
        let coreStartIndex = token.index(token.startIndex, offsetBy: prefix.count)
        let coreEndIndex = token.index(token.endIndex, offsetBy: -suffix.count)
        guard coreStartIndex <= coreEndIndex else {
            return token
        }
        let core = String(token[coreStartIndex..<coreEndIndex])
        guard !core.isEmpty else {
            return token
        }

        let normalizedCore = core.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let explicit = explicitTokenCorrections[normalizedCore.lowercased()] {
            return prefix + applyCasePattern(from: core, to: explicit) + suffix
        }

        let lowerCore = normalizedCore.lowercased()
        guard lowerCore.count >= 4 else {
            return token
        }
        guard vocabularyFrequency[lowerCore] == nil else {
            return token
        }

        let nearMatches = vocabularyFrequency.filter { candidate, signal in
            signal.frequency >= 2
                && candidate.first == lowerCore.first
                && lowerCore.editDistanceAtMostOne(candidate)
                && supportsContextualCorrection(
                    signal: signal,
                    observationConfidence: observationConfidence,
                    lineIndex: lineIndex
                )
        }
        guard let best = nearMatches.max(by: { lhs, rhs in lhs.value.frequency < rhs.value.frequency })?.key else {
            return token
        }

        return prefix + applyCasePattern(from: core, to: best) + suffix
    }

    private static func supportsContextualCorrection(
        signal: VocabularySignal,
        observationConfidence: Float,
        lineIndex: Int
    ) -> Bool {
        let hasNearbySupport = signal.lineIndexes.contains { abs($0 - lineIndex) <= 2 }

        if observationConfidence >= 0.5 {
            return hasNearbySupport || signal.frequency >= 3
        }

        return hasNearbySupport && signal.frequency >= 3
    }

    private static func applyCasePattern(from source: String, to replacement: String) -> String {
        if source == source.uppercased() {
            return replacement.uppercased()
        }
        if source == source.lowercased() {
            return replacement.lowercased()
        }
        if source.prefix(1) == source.prefix(1).uppercased() {
            return replacement.prefix(1).uppercased() + replacement.dropFirst().lowercased()
        }
        return replacement
    }

    private static func repairPackSizeNoise(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*[xX]\s*(\d{3,4})\s*m[lL]"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        var result = text
        let matches = regex.matches(in: text, range: range).reversed()

        for match in matches {
            guard
                let packRange = Range(match.range(at: 1), in: result),
                let volumeRange = Range(match.range(at: 2), in: result)
            else {
                continue
            }

            let packCount = String(result[packRange])
            let rawVolume = String(result[volumeRange])
            let correctedVolume = correctedVolumeToken(rawVolume)
            let replacement = "\(packCount) x \(correctedVolume) mL"

            let fullRange = match.range(at: 0)
            let location = fullRange.location
            let length = fullRange.length
            let current = result as NSString
            result = current.replacingCharacters(in: NSRange(location: location, length: length), with: replacement)
        }

        return result
    }

    private static func correctedVolumeToken(_ token: String) -> String {
        guard token.count == 4 else {
            return token
        }
        let chars = Array(token)
        if chars[1] == chars[2] {
            return "\(chars[0])\(chars[2])\(chars[3])"
        }
        if chars[2] == chars[3] {
            return "\(chars[0])\(chars[1])\(chars[3])"
        }
        return token
    }

    private static func isSizeToken(_ word: String) -> Bool {
        word.range(of: #"^\d{1,4}(g|kg|ml|l|oz|lb|pk|ct)$"#, options: .regularExpression) != nil
    }

    private static func containsExplicitSizeToken(in line: String) -> Bool {
        let words = line.normalizedWords()
        if words.contains(where: { isSizeToken($0) }) {
            return true
        }
        return line.range(
            of: #"\d{1,4}\s*(ml|g|kg|l|oz|lb|pk|ct)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func normalize(price: Decimal, unit: UnitType, quantity: Decimal?) -> (Decimal, UnitType)? {
        let effectivePrice = unitPrice(price: price, quantity: quantity)

        switch unit {
        case .lb:
            return (effectivePrice * poundsPerKilogram, .kg)
        case .kg:
            return (effectivePrice, .kg)
        case .each:
            return (effectivePrice, .each)
        case .liter:
            return (effectivePrice, .liter)
        case .hundredGrams:
            return (effectivePrice * 10, .kg)
        }
    }

    static func unitPrice(price: Decimal, quantity: Decimal?) -> Decimal {
        guard let quantity, quantity > 0 else {
            return price
        }
        return price / quantity
    }

    static func looksLikeReceipt(text: String) -> Bool {
        let lowered = text.lowercased()
        let markerCount = receiptMarkers.reduce(into: 0) { count, marker in
            if lowered.contains(marker) {
                count += 1
            }
        }
        return markerCount >= 2
    }

    private static func extractPriceCandidates(from observations: [OCRTextObservation]) -> [PriceCandidate] {
        var candidates: [PriceCandidate] = []
        let normalizedObservations = observations.map { observation in
            OCRTextObservation(
                string: observation.string.replacingOccurrences(of: ",", with: "."),
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }

        for observation in normalizedObservations {
            candidates.append(contentsOf: extractInlinePriceCandidates(from: observation))
        }

        if let regex = try? NSRegularExpression(pattern: splitCurrencyPattern) {
            let combinedObservations = zip(normalizedObservations, normalizedObservations.dropFirst()).map { lhs, rhs in
                OCRTextObservation(
                    string: "\(lhs.string)\n\(rhs.string)",
                    confidence: min(lhs.confidence, rhs.confidence),
                    boundingBox: nil
                )
            }

            for observation in combinedObservations {
                let text = observation.string
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    guard
                        let dollarsRange = Range(match.range(at: 2), in: text),
                        let centsRange = Range(match.range(at: 3), in: text),
                        let candidate = splitCurrencyCandidate(
                            dollarsText: String(text[dollarsRange]),
                            centsText: String(text[centsRange]),
                            sourceText: text,
                            confidence: observation.confidence
                        )
                    else {
                        continue
                    }

                    if candidates.contains(where: { $0.value == candidate.value && $0.quantity == nil }) {
                        continue
                    }

                    candidates.append(candidate)
                }
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }

            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.value > rhs.value
        }
    }

    private static func extractInlinePriceCandidates(from observation: OCRTextObservation) -> [PriceCandidate] {
        var candidates: [PriceCandidate] = []
        let text = observation.string

        if let regex = try? NSRegularExpression(pattern: multiBuyPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard
                    let quantityRange = Range(match.range(at: 1), in: text),
                    let priceRange = Range(match.range(at: 2), in: text),
                    let quantity = Decimal(string: String(text[quantityRange])),
                    let price = Decimal(string: String(text[priceRange]))
                else {
                    continue
                }

                candidates.append(
                    PriceCandidate(
                        label: "\(quantity) for $\(price)",
                        value: price,
                        quantity: quantity,
                        priority: 4,
                        sourceText: observation.string,
                        confidence: observation.confidence
                    )
                )
            }
        }

        if let regex = try? NSRegularExpression(pattern: currencyPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if shouldIgnoreDirectPriceLine(text) {
                    continue
                }

                guard
                    let range = Range(match.range(at: 1), in: text),
                    let price = Decimal(string: String(text[range]))
                else {
                    continue
                }

                if candidates.contains(where: { $0.value == price && $0.quantity == nil }) {
                    continue
                }

                candidates.append(
                    PriceCandidate(
                        label: "$\(price)",
                        value: price,
                        quantity: nil,
                        priority: contextualPricePriority(in: observation.string, basePriority: 3),
                        sourceText: observation.string,
                        confidence: observation.confidence
                    )
                )
            }
        }

        if let regex = try? NSRegularExpression(pattern: impliedCurrencyPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if shouldIgnoreImpliedCurrencyLine(text) {
                    continue
                }

                guard
                    let range = Range(match.range(at: 2), in: text),
                    let candidate = impliedCurrencyCandidate(
                        from: String(text[range]),
                        sourceText: observation.string,
                        confidence: observation.confidence
                    )
                else {
                    continue
                }

                if candidates.contains(where: { $0.value == candidate.value && $0.quantity == nil }) {
                    continue
                }

                candidates.append(candidate)
            }
        }

        return candidates
    }

    private static func splitCurrencyCandidate(
        dollarsText: String,
        centsText: String,
        sourceText: String,
        confidence: Float
    ) -> PriceCandidate? {
        guard
            let dollars = Decimal(string: dollarsText),
            let cents = Decimal(string: centsText),
            cents < 100
        else {
            return nil
        }

        let value = dollars + (cents / 100)
        return PriceCandidate(
            label: "$\(value)",
            value: value,
            quantity: nil,
            priority: 2,
            sourceText: sourceText,
            confidence: confidence
        )
    }

    private static func impliedCurrencyCandidate(
        from text: String,
        sourceText: String,
        confidence: Float
    ) -> PriceCandidate? {
        guard
            text.count >= 3,
            let integerValue = Int(text)
        else {
            return nil
        }

        let dollars = integerValue / 100
        let cents = integerValue % 100
        guard dollars > 0 else {
            return nil
        }

        let valueString = "\(dollars).\(String(format: "%02d", cents))"
        guard let value = Decimal(string: valueString) else {
            return nil
        }

        return PriceCandidate(
            label: "$\(value)",
            value: value,
            quantity: nil,
            priority: 1,
            sourceText: sourceText,
            confidence: confidence
        )
    }

    private static func averageConfidence(in observations: [OCRTextObservation]) -> Float? {
        guard !observations.isEmpty else {
            return nil
        }

        let total = observations.reduce(Float.zero) { partialResult, observation in
            partialResult + observation.confidence
        }
        return total / Float(observations.count)
    }

    private static func detectUnit(in text: String) -> UnitType? {
        let lowered = text.lowercased()

        if lowered.contains("100 g") || lowered.contains("100g") {
            return .hundredGrams
        }
        if lowered.contains(" lbs") || lowered.contains("/lb") || lowered.contains(" lb") {
            return .lb
        }
        if lowered.contains("/kg") || lowered.contains(" kg") {
            return .kg
        }
        if lowered.contains(" ea") || lowered.contains(" each") {
            return .each
        }
        if lowered.contains(" l") || lowered.contains("/l") {
            return .liter
        }

        return nil
    }

    private static func detectQuantity(in text: String, unit: UnitType?) -> Decimal? {
        guard let unit else {
            return nil
        }

        let lowered = text.lowercased().replacingOccurrences(of: ",", with: ".")

        if unit == .lb {
            if lowered.contains("/lb") || lowered.contains(" per lb") || lowered.contains(" lbs") {
                return Decimal(1)
            }
        } else if unit == .kg, lowered.contains("/kg") || lowered.contains(" per kg") {
            return Decimal(1)
        } else if unit == .liter, lowered.contains("/l") || lowered.contains(" per l") {
            return Decimal(1)
        }

        if let regex = try? NSRegularExpression(pattern: quantityFractionPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
            for match in matches {
                guard
                    let numeratorRange = Range(match.range(at: 1), in: lowered),
                    let denominatorRange = Range(match.range(at: 2), in: lowered),
                    let numerator = Decimal(string: String(lowered[numeratorRange])),
                    let denominator = Decimal(string: String(lowered[denominatorRange])),
                    denominator > 0
                else {
                    continue
                }
                return numerator / denominator
            }
        }

        if let regex = try? NSRegularExpression(pattern: quantityDecimalPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
            for match in matches {
                guard
                    let quantityRange = Range(match.range(at: 1), in: lowered),
                    let quantity = Decimal(string: String(lowered[quantityRange])),
                    quantity > 0
                else {
                    continue
                }
                return quantity
            }
        }

        return nil
    }

    private static func contextualPricePriority(in text: String, basePriority: Int) -> Int {
        let lowered = text.lowercased()

        if lowered.contains("member") || lowered.contains("club") || lowered.contains("loyalty") {
            return min(4, basePriority + 1)
        }
        if lowered.contains("regular") || lowered.contains(" was ") || lowered.hasPrefix("was ") {
            return max(1, basePriority - 1)
        }

        return basePriority
    }

    private static func shouldIgnoreDirectPriceLine(_ text: String) -> Bool {
        let lowered = text.lowercased()

        if lowered.contains("save") {
            return true
        }
        if containsPhoneNumber(in: lowered) {
            return true
        }
        if looksLikeDateLine(lowered) {
            return true
        }

        return false
    }

    private static func shouldIgnoreImpliedCurrencyLine(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return containsPhoneNumber(in: lowered) || looksLikeDateLine(lowered)
    }

    private static func hasCompetingTopCandidates(_ candidates: [PriceCandidate]) -> Bool {
        guard candidates.count >= 2 else {
            return false
        }

        let top = candidates[0]
        let runnerUp = candidates[1]
        if top.priority != runnerUp.priority {
            return false
        }

        let confidenceGap = abs(top.confidence - runnerUp.confidence)
        if confidenceGap > 0.08 {
            return false
        }

        return top.sourceText != runnerUp.sourceText || top.value != runnerUp.value
    }

    private static func looksLikeMultiProductScan(_ snapshot: HeuristicExtractionSnapshot) -> Bool {
        let meaningfulSpatialGroups = snapshot.spatialGroups.filter { group in
            let hasPrice = group.observations.contains { containsPriceSignal(in: $0.string) }
            let hasDescription = group.observations.contains { observation in
                isDescriptiveObservation(observation)
            }
            return group.observations.count >= 2 && hasPrice && hasDescription
        }
        if meaningfulSpatialGroups.count >= 2 {
            return true
        }

        let descriptiveLines = snapshot.lines.filter { line in
            !line.contains(where: \.isNumber) && !line.contains("$")
        }
        let distinctPriceSources = Set(snapshot.priceCandidates.map(\.sourceText))
        return descriptiveLines.count >= 2 && distinctPriceSources.count >= 2
    }

    private static func sourceLineIndexes(
        for candidate: PriceCandidate,
        in snapshot: HeuristicExtractionSnapshot
    ) -> [Int] {
        snapshot.consolidatedObservations.enumerated().compactMap { index, observation in
            let line = observation.string.lowercased()
            let source = candidate.sourceText.lowercased()
            return line.contains(source) || source.contains(line) ? index : nil
        }
    }

    private static func encodeForPrompt<T: Encodable>(_ value: T) -> String {
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

    private static func normalizedCanonicalItemName(
        from assisted: AssistedExtractionResult,
        snapshot: HeuristicExtractionSnapshot
    ) -> String? {
        if let name = assisted.canonicalItemName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        let selectedLines = supportingLines(from: assisted.targetLineIndexes, snapshot: snapshot)
        return selectedLines.first { line in
            !line.contains("$") && !line.contains(where: \.isNumber)
        }
    }

    private static func supportingLines(
        from targetLineIndexes: [Int],
        snapshot: HeuristicExtractionSnapshot
    ) -> [String] {
        let lines = targetLineIndexes.compactMap { index in
            snapshot.consolidatedObservations.indices.contains(index)
                ? snapshot.consolidatedObservations[index].string
                : nil
        }

        return lines.isEmpty ? snapshot.consolidatedObservations.map(\.string) : lines
    }

    private static func mergedConfidence(
        heuristicConfidence: Float,
        assistedConfidence: AssistedConfidenceBucket,
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

    private static func containsPhoneNumber(in text: String) -> Bool {
        text.range(of: #"\d{10,}"#, options: .regularExpression) != nil
    }

    private static func looksLikeDateLine(_ text: String) -> Bool {
        guard text.range(of: monthNamePattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return false
        }

        let hasDay = text.range(of: #"\b([12]?\d|3[01])\b"#, options: .regularExpression) != nil
        let hasYear = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        return hasDay || hasYear
    }

#if DEBUG
    static func _test_buildHeuristicSnapshot(_ observations: [OCRTextObservation]) -> HeuristicExtractionSnapshot {
        buildHeuristicSnapshot(from: observations)
    }

    static func _test_analyzeAmbiguity(_ observations: [OCRTextObservation]) -> ExtractionAmbiguityReport {
        analyzeAmbiguity(in: buildHeuristicSnapshot(from: observations))
    }

    static func _test_assistedExtractionResult(
        targetLineIndexes: [Int],
        selectedPriceCandidateIndex: Int?,
        selectedPriceKind: AssistedPriceKind,
        canonicalItemName: String?,
        ambiguityNotes: [String],
        confidenceBucket: AssistedConfidenceBucket
    ) -> AssistedExtractionResult {
        AssistedExtractionResult(
            targetLineIndexes: targetLineIndexes,
            selectedPriceCandidateIndex: selectedPriceCandidateIndex,
            selectedPriceKind: selectedPriceKind,
            canonicalItemName: canonicalItemName,
            ambiguityNotes: ambiguityNotes,
            confidenceBucket: confidenceBucket
        )
    }

    static func _test_mergeAssistedExtraction(
        observations: [OCRTextObservation],
        assisted: AssistedExtractionResult
    ) -> OCRResult {
        let snapshot = buildHeuristicSnapshot(from: observations)
        return mergeAssistedExtraction(snapshot: snapshot, assisted: assisted)
    }

    static func _test_consolidateObservations(_ observations: [OCRTextObservation]) -> [OCRTextObservation] {
        observations.consolidateObservations()
    }
#endif
}





