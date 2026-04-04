//
//  PriceParsingItemNameResolver.swift
//  Prixio
//

import Foundation

struct PriceParsingItemNameResolver {
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

        guard let bestCandidate = candidateLineIndexes.max(by: { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            return lhs.lineIndex > rhs.lineIndex
        }) else {
            return nil
        }

        return mergedItemName(
            around: bestCandidate,
            candidates: candidateLineIndexes,
            observations: observations
        ) ?? bestCandidate.line
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
        guard !looksLikeDescriptiveCopy(trimmed) else {
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
        let priceCandidateScorer = PriceCandidateScorer()
        let unitResolver = PriceParsingUnitResolver()
        let promoPenalty = priceCandidateScorer.promotionalPriorityBoost(for: trimmed) > 0 ? 2 : 0
        let regularPenalty = priceCandidateScorer.regularPricePenalty(for: trimmed)
        let depositPenalty = priceCandidateScorer.depositPenalty(for: trimmed)
        let unitOnlyPenalty = unitResolver.detectUnit(in: trimmed) != nil && descriptiveTokens.count == 1 ? 1 : 0
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

        let priceLineIndexes = PriceParsingConfidenceResolver().sourceLineIndexes(for: topCandidate, in: observations)
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
        if PriceParsingConfidenceResolver().containsPhoneNumber(in: lowered)
            || PriceParsingConfidenceResolver().looksLikeDateLine(lowered) {
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

    func looksLikeDescriptiveCopy(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.normalizedWords()
        guard words.count >= 2 else {
            return false
        }

        let descriptiveStopwords: Set<String> = [
            "a",
            "an",
            "and",
            "for",
            "fresh",
            "from",
            "helps",
            "high",
            "hydrated",
            "in",
            "it",
            "keep",
            "of",
            "perfect",
            "snacking",
            "the",
            "to",
            "with",
            "you",
            "your"
        ]
        let stopwordCount = words.filter { descriptiveStopwords.contains($0) }.count
        let lowercaseTokenCount = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                let sanitized = token.trimmingCharacters(in: .punctuationCharacters)
                guard sanitized.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
                    return false
                }
                return sanitized == sanitized.lowercased()
            }
            .count

        let startsLikeSentence = trimmed.first?.isUppercase == true
            && trimmed.dropFirst().contains(where: \.isLowercase)
        let isMostlySentenceCase = lowercaseTokenCount >= max(1, words.count - 1)

        return startsLikeSentence
            && isMostlySentenceCase
            && (stopwordCount >= 1 || words.count >= 4)
    }

    func mergedItemName(
        around bestCandidate: PriceParsingService.ItemNameCandidate,
        candidates: [PriceParsingService.ItemNameCandidate],
        observations: [OCRTextObservation]
    ) -> String? {
        let candidateMap = Dictionary(uniqueKeysWithValues: candidates.map { ($0.lineIndex, $0) })
        let nearbyIndexes = candidates
            .map(\.lineIndex)
            .filter { abs($0 - bestCandidate.lineIndex) <= 2 }
            .sorted()
            .filter { observations.indices.contains($0) }
        let fragments = nearbyIndexes.compactMap { index -> String? in
            guard let candidate = candidateMap[index] else {
                return nil
            }
            return cleanedNameFragment(candidate.line)
        }

        guard let firstFragment = fragments.first else {
            return nil
        }

        return fragments.dropFirst().reduce(firstFragment) { partialResult, fragment in
            mergeNameFragments(partialResult, fragment)
        }
    }

    func cleanedNameFragment(_ line: String) -> String? {
        let trimmed = line.sanitizeOCRLine()
        guard !trimmed.isEmpty else {
            return nil
        }

        let strippedSizeSuffix = trimmed.replacingOccurrences(
            of: #"\s+\d{1,4}(?:[.,]\d+)?\s*(g|kg|ml|l|oz|lb|pk|ct|count|pack)\b.*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let cleaned = cleanedProductPhrase(from: strippedSizeSuffix)
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

    func cleanedProductPhrase(from line: String) -> String {
        let ignoredTokens: Set<String> = [
            "save",
            "this",
            "week",
            "easter",
            "ad",
            "exp"
        ]
        let tokens = line
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                let normalized = token
                    .trimmingCharacters(in: CharacterSet.punctuationCharacters)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()
                return !normalized.isEmpty && !ignoredTokens.contains(normalized)
            }

        return tokens.joined(separator: " ").sanitizeOCRLine()
    }
}
