//
//  PriceCandidateScorer.swift
//  Prixio
//

import Foundation

private struct PriceCandidateScorer {
    func extractPriceCandidates(from observations: [OCRTextObservation]) -> [PriceCandidate] {
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

        if let regex = try? NSRegularExpression(pattern: PriceParsingService.splitCurrencyPattern) {
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

        return candidates.sorted(by: comparePriceCandidates)
    }

    func scorePriceCandidates(
        _ candidates: [PriceCandidate],
        in observations: [OCRTextObservation]
    ) -> [PriceCandidate] {
        guard !candidates.isEmpty else {
            return []
        }

        let descriptiveLineIndexes = observations.enumerated().compactMap { index, observation in
            PriceParsingService.isDescriptiveObservation(observation) ? index : nil
        }

        let scoredCandidates = candidates.map { candidate in
            let sourceIndexes = PriceParsingService.sourceLineIndexes(for: candidate, in: observations)
            let adjustedPriority = candidate.priority
                + proximityPriorityBoost(
                    sourceLineIndexes: sourceIndexes,
                    descriptiveLineIndexes: descriptiveLineIndexes
                )
                + promotionalPriorityBoost(for: candidate.sourceText)
                + unitLabelPriorityBoost(for: candidate.sourceText)
                - regularPricePenalty(for: candidate.sourceText)
                - depositPenalty(for: candidate.sourceText)

            return PriceCandidate(
                label: candidate.label,
                value: candidate.value,
                quantity: candidate.quantity,
                priority: max(0, adjustedPriority),
                sourceText: candidate.sourceText,
                confidence: candidate.confidence
            )
        }

        return scoredCandidates.sorted(by: comparePriceCandidates)
    }

    func extractInlinePriceCandidates(from observation: OCRTextObservation) -> [PriceCandidate] {
        var candidates: [PriceCandidate] = []
        let text = observation.string

        if let regex = try? NSRegularExpression(pattern: PriceParsingService.multiBuyPattern, options: [.caseInsensitive]) {
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

        if let regex = try? NSRegularExpression(pattern: PriceParsingService.currencyPattern) {
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

        if let regex = try? NSRegularExpression(pattern: PriceParsingService.impliedCurrencyPattern) {
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

    func splitCurrencyCandidate(
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

    func impliedCurrencyCandidate(
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

    func contextualPricePriority(in text: String, basePriority: Int) -> Int {
        let lowered = text.lowercased()

        if lowered.contains("member") || lowered.contains("club") || lowered.contains("loyalty") {
            return min(4, basePriority + 1)
        }
        if lowered.contains("regular") || lowered.contains(" was ") || lowered.hasPrefix("was ") {
            return max(1, basePriority - 1)
        }

        return basePriority
    }

    func comparePriceCandidates(_ lhs: PriceCandidate, _ rhs: PriceCandidate) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }

        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }

        return lhs.value > rhs.value
    }

    func proximityPriorityBoost(
        sourceLineIndexes: [Int],
        descriptiveLineIndexes: [Int]
    ) -> Int {
        guard
            !sourceLineIndexes.isEmpty,
            !descriptiveLineIndexes.isEmpty
        else {
            return 0
        }

        let nearestDistance = sourceLineIndexes.flatMap { sourceIndex in
            descriptiveLineIndexes.map { abs(sourceIndex - $0) }
        }.min()

        switch nearestDistance {
        case 0:
            return 3
        case 1:
            return 2
        case 2:
            return 1
        default:
            return 0
        }
    }

    func promotionalPriorityBoost(for text: String) -> Int {
        matchesContextPattern(PriceParsingService.promoMarkerPattern, in: text) ? 1 : 0
    }

    func unitLabelPriorityBoost(for text: String) -> Int {
        matchesContextPattern(PriceParsingService.unitLabelPattern, in: text) ? 1 : 0
    }

    func regularPricePenalty(for text: String) -> Int {
        matchesContextPattern(PriceParsingService.regularPriceMarkerPattern, in: text) ? 2 : 0
    }

    func depositPenalty(for text: String) -> Int {
        matchesContextPattern(PriceParsingService.depositMarkerPattern, in: text) ? 3 : 0
    }

    func matchesContextPattern(_ pattern: String, in text: String) -> Bool {
        text.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    func shouldIgnoreDirectPriceLine(_ text: String) -> Bool {
        let lowered = text.lowercased()

        if lowered.contains("save") {
            return true
        }
        if PriceParsingService.containsPhoneNumber(in: lowered) {
            return true
        }
        if PriceParsingService.looksLikeDateLine(lowered) {
            return true
        }

        return false
    }

    func shouldIgnoreImpliedCurrencyLine(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return PriceParsingService.containsPhoneNumber(in: lowered) || PriceParsingService.looksLikeDateLine(lowered)
    }

    func hasCompetingTopCandidates(_ candidates: [PriceCandidate]) -> Bool {
        guard candidates.count >= 2 else {
            return false
        }

        let top = candidates[0]
        let runnerUp = candidates[1]
        if matchesContextPattern(PriceParsingService.depositMarkerPattern, in: runnerUp.sourceText) {
            return false
        }

        let priorityGap = abs(top.priority - runnerUp.priority)
        if priorityGap > 1 {
            return false
        }

        let confidenceGap = abs(top.confidence - runnerUp.confidence)
        if confidenceGap > 0.08 {
            return false
        }

        return top.sourceText != runnerUp.sourceText || top.value != runnerUp.value
    }
}

extension PriceParsingService {
    static func extractPriceCandidates(from observations: [OCRTextObservation]) -> [PriceCandidate] {
        PriceCandidateScorer().extractPriceCandidates(from: observations)
    }

    static func scorePriceCandidates(
        _ candidates: [PriceCandidate],
        in observations: [OCRTextObservation]
    ) -> [PriceCandidate] {
        PriceCandidateScorer().scorePriceCandidates(candidates, in: observations)
    }

    static func extractInlinePriceCandidates(from observation: OCRTextObservation) -> [PriceCandidate] {
        PriceCandidateScorer().extractInlinePriceCandidates(from: observation)
    }

    static func splitCurrencyCandidate(
        dollarsText: String,
        centsText: String,
        sourceText: String,
        confidence: Float
    ) -> PriceCandidate? {
        PriceCandidateScorer().splitCurrencyCandidate(
            dollarsText: dollarsText,
            centsText: centsText,
            sourceText: sourceText,
            confidence: confidence
        )
    }

    static func impliedCurrencyCandidate(
        from text: String,
        sourceText: String,
        confidence: Float
    ) -> PriceCandidate? {
        PriceCandidateScorer().impliedCurrencyCandidate(
            from: text,
            sourceText: sourceText,
            confidence: confidence
        )
    }

    static func contextualPricePriority(in text: String, basePriority: Int) -> Int {
        PriceCandidateScorer().contextualPricePriority(in: text, basePriority: basePriority)
    }

    static func comparePriceCandidates(_ lhs: PriceCandidate, _ rhs: PriceCandidate) -> Bool {
        PriceCandidateScorer().comparePriceCandidates(lhs, rhs)
    }

    static func proximityPriorityBoost(
        sourceLineIndexes: [Int],
        descriptiveLineIndexes: [Int]
    ) -> Int {
        PriceCandidateScorer().proximityPriorityBoost(
            sourceLineIndexes: sourceLineIndexes,
            descriptiveLineIndexes: descriptiveLineIndexes
        )
    }

    static func promotionalPriorityBoost(for text: String) -> Int {
        PriceCandidateScorer().promotionalPriorityBoost(for: text)
    }

    static func unitLabelPriorityBoost(for text: String) -> Int {
        PriceCandidateScorer().unitLabelPriorityBoost(for: text)
    }

    static func regularPricePenalty(for text: String) -> Int {
        PriceCandidateScorer().regularPricePenalty(for: text)
    }

    static func depositPenalty(for text: String) -> Int {
        PriceCandidateScorer().depositPenalty(for: text)
    }

    static func matchesContextPattern(_ pattern: String, in text: String) -> Bool {
        PriceCandidateScorer().matchesContextPattern(pattern, in: text)
    }

    static func shouldIgnoreDirectPriceLine(_ text: String) -> Bool {
        PriceCandidateScorer().shouldIgnoreDirectPriceLine(text)
    }

    static func shouldIgnoreImpliedCurrencyLine(_ text: String) -> Bool {
        PriceCandidateScorer().shouldIgnoreImpliedCurrencyLine(text)
    }

    static func hasCompetingTopCandidates(_ candidates: [PriceCandidate]) -> Bool {
        PriceCandidateScorer().hasCompetingTopCandidates(candidates)
    }
}
