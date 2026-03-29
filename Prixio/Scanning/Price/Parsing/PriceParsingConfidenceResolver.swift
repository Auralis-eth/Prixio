//
//  PriceParsingConfidenceResolver.swift
//  Prixio
//

import Foundation

extension PriceParsingService {
    static func analyzeAmbiguity(in snapshot: HeuristicExtractionSnapshot) -> ExtractionAmbiguityReport {
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

    static func makeOCRResult(from snapshot: HeuristicExtractionSnapshot) -> OCRResult {
        let ambiguity = analyzeAmbiguity(in: snapshot)
        return OCRResult(
            rawText: snapshot.rawText,
            itemNameHint: snapshot.itemNameHint,
            price: snapshot.priceCandidates.first?.value,
            unit: snapshot.detectedUnit,
            quantity: snapshot.resolvedQuantity,
            confidence: assembleHeuristicConfidence(snapshot: snapshot, ambiguity: ambiguity),
            priceCandidates: snapshot.priceCandidates,
            supportingLines: snapshot.consolidatedObservations.map(\.string)
        )
    }

    static func looksLikeMultiProductScan(_ snapshot: HeuristicExtractionSnapshot) -> Bool {
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

    static func sourceLineIndexes(
        for candidate: PriceCandidate,
        in snapshot: HeuristicExtractionSnapshot
    ) -> [Int] {
        sourceLineIndexes(for: candidate, in: snapshot.consolidatedObservations)
    }

    static func sourceLineIndexes(
        for candidate: PriceCandidate,
        in observations: [OCRTextObservation]
    ) -> [Int] {
        observations.enumerated().compactMap { index, observation in
            let line = observation.string.lowercased()
            let source = candidate.sourceText.lowercased()
            return line.contains(source) || source.contains(line) ? index : nil
        }
    }

    static func assembleHeuristicConfidence(
        snapshot: HeuristicExtractionSnapshot,
        ambiguity: ExtractionAmbiguityReport
    ) -> Float {
        var confidence = max(0.15, snapshot.heuristicConfidence)

        if !snapshot.priceCandidates.isEmpty {
            confidence += 0.06
        }
        if snapshot.itemNameHint?.isEmpty == false {
            confidence += 0.06
        }
        if snapshot.detectedUnit != nil {
            confidence += 0.05
        }
        if snapshot.resolvedQuantity != nil || snapshot.detectedUnit == .each {
            confidence += 0.05
        }
        if snapshot.cleanedObservations.count >= 2 && snapshot.lines.count >= 2 {
            confidence += 0.04
        }
        if !hasCompetingTopCandidates(snapshot.priceCandidates) {
            confidence += 0.04
        }
        if !looksLikeMultiProductScan(snapshot) {
            confidence += 0.03
        }

        for weakness in ambiguity.weaknesses {
            confidence -= confidencePenalty(for: weakness)
        }

        return min(0.99, max(0.1, confidence))
    }

    static func confidencePenalty(for weakness: ExtractionWeakness) -> Float {
        switch weakness {
        case .noPriceCandidates:
            return 0.28
        case .multipleCompetingPrices:
            return 0.18
        case .missingItemName:
            return 0.12
        case .missingUnit:
            return 0.12
        case .missingQuantity:
            return 0.08
        case .lowConfidence:
            return 0.10
        case .sparseOCR:
            return 0.10
        case .possibleMultiProductScan:
            return 0.16
        }
    }

    static func containsPhoneNumber(in text: String) -> Bool {
        text.range(of: #"\d{10,}"#, options: .regularExpression) != nil
    }

    static func looksLikeDateLine(_ text: String) -> Bool {
        guard text.range(of: monthNamePattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return false
        }

        let hasDay = text.range(of: #"\b([12]?\d|3[01])\b"#, options: .regularExpression) != nil
        let hasYear = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        return hasDay || hasYear
    }
}
