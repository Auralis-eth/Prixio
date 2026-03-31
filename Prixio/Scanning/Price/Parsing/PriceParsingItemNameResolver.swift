//
//  PriceParsingItemNameResolver.swift
//  Prixio
//

import Foundation

private struct PriceParsingItemNameResolver {
    func extractItemNameHint(
        from observations: [OCRTextObservation],
        priceCandidates: [PriceCandidate]
    ) -> String? {
        let candidateLineIndexes = observations.enumerated().compactMap { index, observation in
            scoredItemNameCandidate(
                for: observation.string,
                lineIndex: index,
                priceCandidates: priceCandidates,
                observations: observations
            )
        }

        return candidateLineIndexes.max { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            return lhs.lineIndex > rhs.lineIndex
        }?.line
    }

    func scoredItemNameCandidate(
        for line: String,
        lineIndex: Int,
        priceCandidates: [PriceCandidate],
        observations: [OCRTextObservation]
    ) -> PriceParsingService.ItemNameCandidate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard !PriceParsingService.containsPriceSignal(in: trimmed) else {
            return nil
        }
        let hasExplicitSizeToken = PriceParsingService.containsExplicitSizeToken(in: trimmed)
        guard !PriceParsingService.isLikelyShelfCode(trimmed) else {
            return nil
        }
        guard !looksLikeReceiptFragment(trimmed) else {
            return nil
        }
        guard !looksLikePromoBanner(trimmed) else {
            return nil
        }

        let words = trimmed.normalizedWords()
        let hasOCRVariantEvidence = trimmed.digitsAsLettersCount() >= 2
        guard !(PriceParsingService.isLikelySKU(trimmed) && !hasExplicitSizeToken && words.count <= 3 && !hasOCRVariantEvidence) else {
            return nil
        }
        let alphabeticalTokens = words.filter { token in
            token.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
        }
        guard !alphabeticalTokens.isEmpty else {
            return nil
        }

        let descriptiveTokens = alphabeticalTokens.filter { token in
            !PriceParsingService.itemNameIgnoredTokens.contains(token) && !isPureUnitToken(token)
        }
        guard !descriptiveTokens.isEmpty else {
            return nil
        }

        let digitMixPenalty = trimmed.contains(where: \.isNumber) && !PriceParsingService.containsExplicitSizeToken(in: trimmed) && !hasOCRVariantEvidence ? 1 : 0
        let sizePenalty = hasExplicitSizeToken ? 1 : 0
        let promoPenalty = PriceParsingService.promotionalPriorityBoost(for: trimmed) > 0 ? 2 : 0
        let regularPenalty = PriceParsingService.regularPricePenalty(for: trimmed)
        let depositPenalty = PriceParsingService.depositPenalty(for: trimmed)
        let unitOnlyPenalty = PriceParsingService.detectUnit(in: trimmed) != nil && descriptiveTokens.count == 1 ? 1 : 0
        let ocrVariantBoost = hasOCRVariantEvidence && descriptiveTokens.count >= 2 ? 2 : 0

        let proximityBoost = topCandidateProximityBoost(
            lineIndex: lineIndex,
            priceCandidates: priceCandidates,
            observations: observations
        )
        let confidenceBoost = Int((observations[lineIndex].confidence * 10).rounded(.down))
        let descriptiveScore = descriptiveTokens.count * 4
        let wordCountScore = min(3, words.count)
        let uppercaseBrandBoost = trimmed.contains { $0.isUppercase } ? 1 : 0

        let score = descriptiveScore
            + wordCountScore
            + proximityBoost
            + confidenceBoost
            + uppercaseBrandBoost
            + ocrVariantBoost
            - digitMixPenalty
            - sizePenalty
            - promoPenalty
            - regularPenalty
            - depositPenalty
            - unitOnlyPenalty

        return PriceParsingService.ItemNameCandidate(line: trimmed, score: score, lineIndex: lineIndex)
    }

    func topCandidateProximityBoost(
        lineIndex: Int,
        priceCandidates: [PriceCandidate],
        observations: [OCRTextObservation]
    ) -> Int {
        guard let topCandidate = priceCandidates.first else {
            return 0
        }

        let priceLineIndexes = PriceParsingService.sourceLineIndexes(for: topCandidate, in: observations)
        guard let nearestDistance = priceLineIndexes.map({ abs($0 - lineIndex) }).min() else {
            return 0
        }

        switch nearestDistance {
        case 0:
            return 2
        case 1:
            return 4
        case 2:
            return 2
        default:
            return 0
        }
    }

    func looksLikeReceiptFragment(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if PriceParsingService.receiptMarkers.contains(where: lowered.contains) {
            return true
        }
        if PriceParsingService.containsPhoneNumber(in: lowered) || PriceParsingService.looksLikeDateLine(lowered) {
            return true
        }
        if looksLikePromoBanner(lowered) {
            return true
        }
        return false
    }

    func looksLikePromoBanner(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let words = lowered.normalizedWords()
        guard !words.isEmpty else {
            return true
        }

        let ignoredTokens = PriceParsingService.itemNameIgnoredTokens
            .union(["mbr", "save", "valid", "weekly", "fri", "sat", "sun", "mon", "tue", "wed", "thu"])

        let allTokensIgnored = words.allSatisfy { ignoredTokens.contains($0) }
        if allTokensIgnored {
            return true
        }

        if lowered.contains("weekly special") || lowered.contains("valid ") || lowered.hasPrefix("save ") {
            return true
        }

        return false
    }

    func isPureUnitToken(_ token: String) -> Bool {
        ["ea", "each", "lb", "lbs", "kg", "l", "liter", "litre", "g", "ml"].contains(token)
    }
}

extension PriceParsingService {
    static func extractItemNameHint(
        from observations: [OCRTextObservation],
        priceCandidates: [PriceCandidate]
    ) -> String? {
        PriceParsingItemNameResolver().extractItemNameHint(
            from: observations,
            priceCandidates: priceCandidates
        )
    }

    static func scoredItemNameCandidate(
        for line: String,
        lineIndex: Int,
        priceCandidates: [PriceCandidate],
        observations: [OCRTextObservation]
    ) -> ItemNameCandidate? {
        PriceParsingItemNameResolver().scoredItemNameCandidate(
            for: line,
            lineIndex: lineIndex,
            priceCandidates: priceCandidates,
            observations: observations
        )
    }

    static func topCandidateProximityBoost(
        lineIndex: Int,
        priceCandidates: [PriceCandidate],
        observations: [OCRTextObservation]
    ) -> Int {
        PriceParsingItemNameResolver().topCandidateProximityBoost(
            lineIndex: lineIndex,
            priceCandidates: priceCandidates,
            observations: observations
        )
    }

    static func looksLikeReceiptFragment(_ text: String) -> Bool {
        PriceParsingItemNameResolver().looksLikeReceiptFragment(text)
    }

    static func looksLikePromoBanner(_ text: String) -> Bool {
        PriceParsingItemNameResolver().looksLikePromoBanner(text)
    }

    static func isPureUnitToken(_ token: String) -> Bool {
        PriceParsingItemNameResolver().isPureUnitToken(token)
    }
}
