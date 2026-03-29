//
//  PriceParsingItemNameResolver.swift
//  Prixio
//

import Foundation

extension PriceParsingService {
    static func extractItemNameHint(
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

    static func scoredItemNameCandidate(
        for line: String,
        lineIndex: Int,
        priceCandidates: [PriceCandidate],
        observations: [OCRTextObservation]
    ) -> ItemNameCandidate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard !containsPriceSignal(in: trimmed) else {
            return nil
        }
        let hasExplicitSizeToken = containsExplicitSizeToken(in: trimmed)
        guard !isLikelyShelfCode(trimmed) else {
            return nil
        }
        guard !looksLikeReceiptFragment(trimmed) else {
            return nil
        }

        let words = trimmed.normalizedWords()
        guard !(isLikelySKU(trimmed) && !hasExplicitSizeToken && words.count <= 3) else {
            return nil
        }
        let alphabeticalTokens = words.filter { token in
            token.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
        }
        guard !alphabeticalTokens.isEmpty else {
            return nil
        }

        let descriptiveTokens = alphabeticalTokens.filter { token in
            !itemNameIgnoredTokens.contains(token) && !isPureUnitToken(token)
        }
        guard !descriptiveTokens.isEmpty else {
            return nil
        }

        let digitMixPenalty = trimmed.contains(where: \.isNumber) && !containsExplicitSizeToken(in: trimmed) ? 1 : 0
        let sizePenalty = hasExplicitSizeToken ? 1 : 0
        let promoPenalty = promotionalPriorityBoost(for: trimmed) > 0 ? 1 : 0
        let regularPenalty = regularPricePenalty(for: trimmed)
        let depositPenalty = depositPenalty(for: trimmed)
        let unitOnlyPenalty = detectUnit(in: trimmed) != nil && descriptiveTokens.count == 1 ? 1 : 0

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
            - digitMixPenalty
            - sizePenalty
            - promoPenalty
            - regularPenalty
            - depositPenalty
            - unitOnlyPenalty

        return ItemNameCandidate(line: trimmed, score: score, lineIndex: lineIndex)
    }

    static func topCandidateProximityBoost(
        lineIndex: Int,
        priceCandidates: [PriceCandidate],
        observations: [OCRTextObservation]
    ) -> Int {
        guard let topCandidate = priceCandidates.first else {
            return 0
        }

        let priceLineIndexes = sourceLineIndexes(for: topCandidate, in: observations)
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

    static func looksLikeReceiptFragment(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if receiptMarkers.contains(where: lowered.contains) {
            return true
        }
        if containsPhoneNumber(in: lowered) || looksLikeDateLine(lowered) {
            return true
        }
        return false
    }

    static func isPureUnitToken(_ token: String) -> Bool {
        ["ea", "each", "lb", "lbs", "kg", "l", "liter", "litre", "g", "ml"].contains(token)
    }
}
