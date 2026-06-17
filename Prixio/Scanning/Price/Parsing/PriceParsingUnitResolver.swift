//
//  PriceParsingUnitResolver.swift
//  Prixio
//

import Foundation

struct PriceParsingUnitResolver {
    func detectUnit(in text: String) -> UnitType? {
        let normalized = normalizedUnitDetectionText(text)
        let directSignals = directUnitSignals(in: normalized)
        if let strongestDirectSignal = strongestUnitSignal(in: directSignals) {
            return strongestDirectSignal.unit
        }

        let packageSignals = packageUnitSignals(in: normalized)
        return strongestUnitSignal(in: packageSignals)?.unit
    }

    func detectQuantity(in text: String, unit: UnitType?) -> Decimal? {
        guard let unit else {
            return nil
        }

        let lowered = normalizedUnitDetectionText(text)

        switch unit {
        case .lb:
            if matchesTokenBoundary(#"\b(?:lb|lbs)\b"#, in: lowered) {
                return Decimal(1)
            }
        case .kg:
            if matchesTokenBoundary(#"\bkg\b"#, in: lowered) {
                return Decimal(1)
            }
        case .liter:
            if matchesTokenBoundary(#"\b(?:l|liter|litre)\b"#, in: lowered) {
                return Decimal(1)
            }
        case .hundredGrams:
            if matchesTokenBoundary(#"\b100\s*g\b"#, in: lowered) {
                return Decimal(1)
            }
        case .each:
            break
        }

        if let regex = try? NSRegularExpression(pattern: PriceParsingService.quantityFractionPattern, options: [.caseInsensitive]) {
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

        if let regex = try? NSRegularExpression(pattern: PriceParsingService.quantityDecimalPattern, options: [.caseInsensitive]) {
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

    func inferResolvedQuantity(
        from observations: [any TextObservation],
        priceCandidates: [PriceCandidate],
        detectedUnit: UnitType?,
        fallbackText: String
    ) -> Decimal? {
        if let candidateQuantity = priceCandidates.first?.quantity {
            return candidateQuantity
        }

        let contextText = quantityContextText(
            for: priceCandidates.first,
            observations: observations,
            fallbackText: fallbackText
        )

        if let offerQuantity = inferOfferQuantity(in: contextText) {
            return offerQuantity
        }

        let packContextText = packQuantityContextText(
            for: priceCandidates.first,
            observations: observations,
            fallbackText: fallbackText
        )
        if detectedUnit == .each || detectedUnit == nil,
           let packQuantity = inferPackQuantity(in: packContextText) {
            return packQuantity
        }

        return detectQuantity(in: contextText, unit: detectedUnit)
    }

    func quantityContextText(
        for candidate: PriceCandidate?,
        observations: [any TextObservation],
        fallbackText: String
    ) -> String {
        guard let candidate else {
            return fallbackText
        }

        let sourceIndexes = PriceParsingConfidenceResolver().sourceLineIndexes(for: candidate, in: observations)
        guard !sourceIndexes.isEmpty else {
            return fallbackText
        }

        let nearbyIndexes = Set(sourceIndexes.flatMap { index in
            [(index - 1), index, (index + 1)].filter { observations.indices.contains($0) }
        })
        let nearbyLines = observations.enumerated().compactMap { index, observation in
            nearbyIndexes.contains(index) ? observation.string : nil
        }

        return nearbyLines.isEmpty ? fallbackText : nearbyLines.joined(separator: "\n")
    }

    func packQuantityContextText(
        for candidate: PriceCandidate?,
        observations: [any TextObservation],
        fallbackText: String
    ) -> String {
        guard let candidate else {
            return fallbackText
        }

        let sourceIndexes = PriceParsingConfidenceResolver().sourceLineIndexes(for: candidate, in: observations)
        guard !sourceIndexes.isEmpty else {
            return fallbackText
        }

        let nearbyIndexes = Set(sourceIndexes.flatMap { index in
            [(index - 1), index].filter { observations.indices.contains($0) }
        })
        let nearbyLines = observations.enumerated().compactMap { index, observation in
            nearbyIndexes.contains(index) ? observation.string : nil
        }

        return nearbyLines.isEmpty ? fallbackText : nearbyLines.joined(separator: "\n")
    }

    func inferOfferQuantity(in text: String) -> Decimal? {
        let lowered = normalizedUnitDetectionText(text)

        if let regex = try? NSRegularExpression(pattern: PriceParsingService.multiBuyPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let quantityRange = Range(match.range(at: 1), in: lowered),
           let quantity = Decimal(string: String(lowered[quantityRange])),
           quantity > 0 {
            return quantity
        }

        if lowered.contains("bogo") || lowered.contains("buy one get one") || lowered.contains("buy 1 get 1") {
            return Decimal(2)
        }

        if let regex = try? NSRegularExpression(pattern: PriceParsingService.buyGetPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let buyRange = Range(match.range(at: 1), in: lowered),
           let getRange = Range(match.range(at: 2), in: lowered),
           let buyQuantity = quantityWordValue(String(lowered[buyRange])),
           let getQuantity = quantityWordValue(String(lowered[getRange])) {
            return buyQuantity + getQuantity
        }

        return nil
    }

    func inferPackQuantity(in text: String) -> Decimal? {
        let lowered = normalizedUnitDetectionText(text)

        let patterns = [
            #"\b(\d{1,2})\s*[x×]\s*\d{1,4}(?:\.\d+)?\s*(?:ml|g|kg|l|oz)\b"#,
            #"\b(\d{1,3})\s*(?:pk|pack|ct|count)\b"#,
            #"\bpack\s+of\s+(\d{1,3})\b"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
                let quantityRange = Range(match.range(at: 1), in: lowered),
                let quantity = Decimal(string: String(lowered[quantityRange])),
                quantity > 0
            else {
                continue
            }

            return quantity
        }

        return nil
    }

    func quantityWordValue(_ token: String) -> Decimal? {
        if let numeric = Decimal(string: token), numeric > 0 {
            return numeric
        }

        let wordValues: [String: Decimal] = [
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5
        ]
        return wordValues[token]
    }

    func normalizedUnitDetectionText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func directUnitSignals(in text: String) -> [PriceParsingService.UnitDetectionSignal] {
        let unitPatterns: [(UnitType, Int, [String])] = [
            (
                .hundredGrams,
                7,
                [
                    #"(?:price\s+)?per\s+100\s*g\b"#,
                    #"/\s*100\s*g\b"#,
                    #"\b100\s*g\s+price\b"#,
                    #"\b100\s*g\b"#
                ]
            ),
            (
                .lb,
                6,
                [
                    #"(?:price\s+)?per\s+lbs?\b"#,
                    #"/\s*lbs?\b"#,
                    #"\blbs?\s+price\b"#,
                    #"\blbs?\b"#
                ]
            ),
            (
                .kg,
                6,
                [
                    #"(?:price\s+)?per\s+kg\b"#,
                    #"/\s*kg\b"#,
                    #"\bkg\s+price\b"#,
                    #"\bkg\b"#
                ]
            ),
            (
                .liter,
                6,
                [
                    #"(?:price\s+)?per\s+l(?:iter|itre)?s?\b"#,
                    #"/\s*l(?:iter|itre)?s?\b"#,
                    #"\bl(?:iter|itre)?s?\s+price\b"#
                ]
            ),
            (
                .each,
                5,
                [
                    #"(?:price\s+)?per\s+(?:ea|each)\b"#,
                    #"/\s*(?:ea|each)\b"#,
                    #"\b(?:ea|each)\b"#
                ]
            )
        ]

        return unitPatterns.flatMap { unit, baseScore, patterns in
            patterns.enumerated().compactMap { index, pattern in
                firstUnitSignal(unit: unit, pattern: pattern, in: text, score: baseScore - index)
            }
        }
    }

    func packageUnitSignals(in text: String) -> [PriceParsingService.UnitDetectionSignal] {
        var signals = [
            firstUnitSignal(
                unit: .each,
                pattern: #"\b\d{1,2}\s*[x×]\s*\d{1,4}(?:\.\d+)?\s*(?:ml|l|g|kg|oz)\b"#,
                in: text,
                score: 4
            ),
            firstUnitSignal(
                unit: .each,
                pattern: #"\b\d{1,3}\s*(?:pk|pack|ct|count)\b"#,
                in: text,
                score: 4
            ),
            firstUnitSignal(
                unit: .each,
                pattern: #"\b\d+(?:\.\d+)?\s*(?:ml|l|g|kg|oz)\b"#,
                in: text,
                score: 2
            )
        ].compactMap { $0 }

        if PriceParsingService.containsPriceSignal(in: text),
           let hundredGramSignal = firstUnitSignal(
                unit: .hundredGrams,
                pattern: #"\b(?:100\s*g|100g)\b"#,
                in: text,
                score: 3
           ) {
            signals.append(hundredGramSignal)
        }

        return signals
    }

    func strongestUnitSignal(in signals: [PriceParsingService.UnitDetectionSignal]) -> PriceParsingService.UnitDetectionSignal? {
        signals.max { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            return lhs.location > rhs.location
        }
    }

    func firstUnitSignal(
        unit: UnitType,
        pattern: String,
        in text: String,
        score: Int
    ) -> PriceParsingService.UnitDetectionSignal? {
        guard
            let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        else {
            return nil
        }

        return PriceParsingService.UnitDetectionSignal(unit: unit, score: score, location: range.lowerBound)
    }

    func matchesTokenBoundary(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
