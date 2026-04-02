//
//  PriceParsingConfidenceResolver.swift
//  Prixio
//

import Foundation

struct PriceParsingConfidenceResolver {
    func analyzeAmbiguity(in snapshot: PriceParsingService.HeuristicExtractionSnapshot) -> PriceParsingService.ExtractionAmbiguityReport {
        var weaknesses: [PriceParsingService.ExtractionWeakness] = []

        if snapshot.priceCandidates.isEmpty {
            weaknesses.append(.noPriceCandidates)
        }

        if PriceCandidateScorer().hasCompetingTopCandidates(snapshot.priceCandidates) {
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

        return PriceParsingService.ExtractionAmbiguityReport(weaknesses: weaknesses)
    }

    func makeOCRResult(from snapshot: PriceParsingService.HeuristicExtractionSnapshot) -> OCRResult {
        let ambiguity = analyzeAmbiguity(in: snapshot)
        return OCRResult(
            rawText: snapshot.rawText,
            itemNameHint: snapshot.itemNameHint,
            price: snapshot.priceCandidates.first?.value,
            unit: snapshot.detectedUnit,
            quantity: snapshot.resolvedQuantity,
            confidence: assembleHeuristicConfidence(snapshot: snapshot, ambiguity: ambiguity),
            priceCandidates: snapshot.priceCandidates,
            review: OCRReview(ambiguity: ambiguity, usedFoundationModel: false),
            supportingLines: snapshot.consolidatedObservations.map(\.string)
        )
    }

    func looksLikeMultiProductScan(_ snapshot: PriceParsingService.HeuristicExtractionSnapshot) -> Bool {
        let meaningfulSpatialGroups = snapshot.spatialGroups.filter { group in
            let hasPrice = group.observations.contains { PriceParsingService.containsPriceSignal(in: $0.string) }
            let hasDescription = group.observations.contains { observation in
                isProductDescriptor(observation.string)
            }
            return group.observations.count >= 2 && hasPrice && hasDescription
        }
        if meaningfulSpatialGroups.count >= 2 {
            return true
        }

        let descriptiveLines = snapshot.lines.filter { line in
            isProductDescriptor(line)
        }
        let distinctPriceSources = Set(snapshot.priceCandidates.map(\.sourceText))
        return descriptiveLines.count >= 2 && distinctPriceSources.count >= 2
    }

    func sourceLineIndexes(
        for candidate: PriceCandidate,
        in snapshot: PriceParsingService.HeuristicExtractionSnapshot
    ) -> [Int] {
        sourceLineIndexes(for: candidate, in: snapshot.consolidatedObservations)
    }

    func sourceLineIndexes(
        for candidate: PriceCandidate,
        in observations: [OCRTextObservation]
    ) -> [Int] {
        observations.enumerated().compactMap { index, observation in
            let line = observation.string.lowercased()
            let source = candidate.sourceText.lowercased()
            return line.contains(source) || source.contains(line) ? index : nil
        }
    }

    func assembleHeuristicConfidence(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        ambiguity: PriceParsingService.ExtractionAmbiguityReport
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
        if !PriceCandidateScorer().hasCompetingTopCandidates(snapshot.priceCandidates) {
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

    func confidencePenalty(for weakness: PriceParsingService.ExtractionWeakness) -> Float {
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

    func containsPhoneNumber(in text: String) -> Bool {
        text.range(of: #"\d{10,}"#, options: .regularExpression) != nil
    }

    func looksLikeDateLine(_ text: String) -> Bool {
        guard text.range(of: PriceParsingService.monthNamePattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return false
        }

        let hasDay = text.range(of: #"\b([12]?\d|3[01])\b"#, options: .regularExpression) != nil
        let hasYear = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        return hasDay || hasYear
    }

    func isProductDescriptor(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        guard !PriceParsingService.containsPriceSignal(in: trimmed) else {
            return false
        }
        guard !PriceParsingItemNameResolver().looksLikeReceiptFragment(trimmed) else {
            return false
        }
        guard !PriceParsingItemNameResolver().looksLikePromoBanner(trimmed) else {
            return false
        }
        guard trimmed.range(of: PriceParsingService.depositMarkerPattern, options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }
        guard trimmed.range(of: PriceParsingService.regularPriceMarkerPattern, options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }

        let words = trimmed.normalizedWords()
        let descriptiveTokens = words.filter { token in
            token.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
                && !PriceParsingService.itemNameIgnoredTokens.contains(token)
                && !PriceParsingItemNameResolver().isPureUnitToken(token)
        }

        return descriptiveTokens.count >= 1
    }
}
