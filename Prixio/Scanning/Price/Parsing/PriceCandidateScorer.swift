//
//  PriceCandidateScorer.swift
//  Prixio
//

import Foundation

struct PriceCandidateScorer {
    func extractPriceCandidates(from observations: [OCRTextObservation]) -> [PriceCandidate] {
        var candidates: [PriceCandidate] = []
        let normalizedObservations = observations.map { observation in
            OCRTextObservation(
                string: observation.string.replacingOccurrences(of: ",", with: "."),
                confidence: observation.confidence,
                boundingBox: observation.boundingBox,
                alternateStrings: observation.alternateStrings
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
                    boundingBox: nil,
                    alternateStrings: lhs.alternateStrings + rhs.alternateStrings
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
            let sourceIndexes = PriceParsingConfidenceResolver().sourceLineIndexes(for: candidate, in: observations)
            let kind = inferPriceKind(
                candidate: candidate,
                sourceLineIndexes: sourceIndexes,
                observations: observations
            )
            let adjustedPriority = candidate.priority
                + proximityPriorityBoost(
                    sourceLineIndexes: sourceIndexes,
                    descriptiveLineIndexes: descriptiveLineIndexes
                )
                + kindPriorityBoost(for: kind)
                + promotionalPriorityBoost(for: candidate.sourceText)
                + unitLabelPriorityBoost(for: candidate.sourceText)
                + standaloneShelfPriceBoost(
                    candidate: candidate,
                    sourceLineIndexes: sourceIndexes,
                    observations: observations
                )
                - nearbySavePenalty(
                    candidate: candidate,
                    sourceLineIndexes: sourceIndexes,
                    observations: observations
                )
                - compactNumericRiskPenalty(
                    candidate: candidate,
                    sourceLineIndexes: sourceIndexes,
                    observations: observations
                )
                - regularPricePenalty(for: candidate.sourceText)
                - depositPenalty(for: candidate.sourceText)

            return PriceCandidate(
                label: candidate.label,
                value: candidate.value,
                quantity: candidate.quantity,
                priority: max(0, adjustedPriority),
                sourceText: candidate.sourceText,
                kind: kind,
                sourceLineIndexes: sourceIndexes,
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
                        kind: .unknown,
                        sourceLineIndexes: [],
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
                        kind: .unknown,
                        sourceLineIndexes: [],
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
            kind: .unknown,
            sourceLineIndexes: [],
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
            let integerValue = Int(text),
            !looksLikeExplicitSizeContext(sourceText, token: text),
            sourceText.localizedCaseInsensitiveContains("plu") == false
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
            kind: .unknown,
            sourceLineIndexes: [],
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

        if lhs.kind != rhs.kind {
            return kindSortWeight(lhs.kind) > kindSortWeight(rhs.kind)
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

    func kindPriorityBoost(for kind: PriceKind) -> Int {
        switch kind {
        case .shelf:
            return 3
        case .sale:
            return 2
        case .member, .unit:
            return 1
        case .regular:
            return -2
        case .save:
            return -4
        case .deposit:
            return -5
        case .unknown:
            return 0
        }
    }

    func unitLabelPriorityBoost(for text: String) -> Int {
        matchesContextPattern(PriceParsingService.unitLabelPattern, in: text)
            || PriceParsingService.containsExplicitSizeToken(in: text) ? 2 : 0
    }

    func regularPricePenalty(for text: String) -> Int {
        matchesContextPattern(PriceParsingService.regularPriceMarkerPattern, in: text) ? 2 : 0
    }

    func depositPenalty(for text: String) -> Int {
        matchesContextPattern(PriceParsingService.depositMarkerPattern, in: text) ? 3 : 0
    }

    func nearbySavePenalty(
        candidate: PriceCandidate,
        sourceLineIndexes: [Int],
        observations: [OCRTextObservation]
    ) -> Int {
        let neighboringLines = sourceLineIndexes.flatMap { index in
            [index - 1, index + 1]
                .filter { observations.indices.contains($0) }
                .map { observations[$0].string }
        }

        let hasStandaloneSaveMarker = neighboringLines.contains { line in
            line.range(of: #"(?i)^\W*save\b"#, options: .regularExpression) != nil
                || line.range(of: #"(?i)^\W*-\s*save\b"#, options: .regularExpression) != nil
        }

        guard hasStandaloneSaveMarker else {
            return 0
        }

        // Preserve big standalone shelf prices that often sit next to a SAVE banner,
        // while still demoting small savings amounts like "$5.00 ea".
        let isLikelyPrimaryShelfPrice = candidate.value >= 10
            && !matchesContextPattern(PriceParsingService.unitLabelPattern, in: candidate.sourceText)
            && candidate.quantity == nil
        return isLikelyPrimaryShelfPrice ? 0 : 4
    }

    func standaloneShelfPriceBoost(
        candidate: PriceCandidate,
        sourceLineIndexes: [Int],
        observations: [OCRTextObservation]
    ) -> Int {
        let neighboringLines = sourceLineIndexes.flatMap { index in
            [index - 2, index - 1, index + 1, index + 2]
                .filter { observations.indices.contains($0) }
                .map { observations[$0].string }
        }

        let hasStandaloneSaveMarker = neighboringLines.contains { line in
            line.range(of: #"(?i)^\W*save\b"#, options: .regularExpression) != nil
                || line.range(of: #"(?i)^\W*-\s*save\b"#, options: .regularExpression) != nil
        }
        guard hasStandaloneSaveMarker else {
            return 0
        }

        let trimmed = candidate.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCompactNumericCandidate = trimmed.range(of: #"^\$?\d{3,4}$"#, options: .regularExpression) != nil
        return isCompactNumericCandidate && candidate.value >= 10 ? 6 : 0
    }

    func compactNumericRiskPenalty(
        candidate: PriceCandidate,
        sourceLineIndexes: [Int],
        observations: [OCRTextObservation]
    ) -> Int {
        let trimmed = candidate.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCompactNumericCandidate = trimmed.range(of: #"^\$?\d{3,4}$"#, options: .regularExpression) != nil
            || (trimmed.range(of: #"\b\d{3,4}\b"#, options: .regularExpression) != nil
                && !PriceParsingService.containsPriceSignal(in: trimmed))
        guard isCompactNumericCandidate else {
            return 0
        }

        let lowered = trimmed.lowercased()
        if lowered.contains("plu") {
            return 6
        }

        if trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            && !matchesContextPattern(PriceParsingService.unitLabelPattern, in: trimmed)
            && !PriceParsingService.containsExplicitSizeToken(in: trimmed) {
            return 4
        }

        let neighboringLines = sourceLineIndexes.flatMap { index in
            [index - 1, index + 1]
                .filter { observations.indices.contains($0) }
                .map { observations[$0].string }
        }
        let hasNearbyDescriptor = neighboringLines.contains { line in
            PriceParsingConfidenceResolver().isProductDescriptor(line)
        }

        if hasNearbyDescriptor {
            return 0
        }

        let hasNearbyUnitSignal = neighboringLines.contains { line in
            matchesContextPattern(PriceParsingService.unitLabelPattern, in: line)
                || PriceParsingService.containsExplicitSizeToken(in: line)
        }
        return hasNearbyUnitSignal ? 4 : 3
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
        if PriceParsingConfidenceResolver().containsPhoneNumber(in: lowered) {
            return true
        }
        if PriceParsingConfidenceResolver().looksLikeDateLine(lowered) {
            return true
        }

        return false
    }

    func shouldIgnoreImpliedCurrencyLine(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return PriceParsingConfidenceResolver().containsPhoneNumber(in: lowered)
            || PriceParsingConfidenceResolver().looksLikeDateLine(lowered)
            || PriceParsingService.containsExplicitSizeToken(in: text)
    }

    func looksLikeExplicitSizeContext(_ sourceText: String, token: String) -> Bool {
        let escapedToken = NSRegularExpression.escapedPattern(for: token)
        return sourceText.range(
            of: #"(?i)\b\#(escapedToken)\s*(g|kg|ml|l|oz|lb|pk|ct|count|pack)\b"#,
            options: .regularExpression
        ) != nil
    }

    func hasCompetingTopCandidates(_ candidates: [PriceCandidate]) -> Bool {
        guard candidates.count >= 2 else {
            return false
        }

        let top = candidates[0]
        let runnerUp = candidates[1]
        if runnerUp.kind == .deposit {
            return false
        }
        if runnerUp.kind == .regular || runnerUp.kind == .save {
            return false
        }
        if top.kind != runnerUp.kind {
            let kindGap = abs(kindSortWeight(top.kind) - kindSortWeight(runnerUp.kind))
            if kindGap >= 2 {
                return false
            }
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

    func inferPriceKind(
        candidate: PriceCandidate,
        sourceLineIndexes: [Int],
        observations: [OCRTextObservation]
    ) -> PriceKind {
        let sourceText = candidate.sourceText.lowercased()
        let neighboringText = sourceLineIndexes.flatMap { index in
            [index - 1, index, index + 1]
                .filter { observations.indices.contains($0) }
                .map { observations[$0].string.lowercased() }
        }.joined(separator: "\n")

        if sourceText.range(of: #"(?i)^\W*-?\s*save\b"#, options: .regularExpression) != nil
            || neighboringText.range(of: #"(?i)^\W*-?\s*save\b"#, options: .regularExpression) != nil {
            return .save
        }
        if matchesContextPattern(PriceParsingService.depositMarkerPattern, in: sourceText)
            || matchesContextPattern(PriceParsingService.depositMarkerPattern, in: neighboringText) {
            return .deposit
        }
        if matchesContextPattern(PriceParsingService.regularPriceMarkerPattern, in: sourceText)
            || matchesContextPattern(PriceParsingService.regularPriceMarkerPattern, in: neighboringText) {
            return .regular
        }
        if sourceText.contains("member")
            || sourceText.contains("club")
            || sourceText.contains("loyalty")
            || neighboringText.contains("member")
            || neighboringText.contains("club")
            || neighboringText.contains("loyalty") {
            return .member
        }
        let looksLikeUnitPrice = matchesContextPattern(PriceParsingService.unitLabelPattern, in: sourceText)
            || sourceText.range(of: #"(?i)/\s*(lb|lbs|kg|l|liter|litre|100\s?g)\b"#, options: .regularExpression) != nil
        if looksLikeUnitPrice {
            return sourceText.contains("sale") ? .sale : .unit
        }
        if sourceText.contains("sale") || sourceText.contains("special") || sourceText.contains("deal") {
            return .sale
        }
        if candidate.value >= 1 {
            return .shelf
        }
        return .unknown
    }

    func kindSortWeight(_ kind: PriceKind) -> Int {
        switch kind {
        case .shelf:
            return 7
        case .sale:
            return 6
        case .member:
            return 5
        case .unit:
            return 4
        case .unknown:
            return 3
        case .regular:
            return 2
        case .save:
            return 1
        case .deposit:
            return 0
        }
    }
}
