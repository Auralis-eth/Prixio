//
//  PriceParsingService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation
import FoundationModels

enum PriceParsingService {
    private struct ConsolidatedObservation {
        let observation: OCRTextObservation
        let words: [String]
        let hasDigits: Bool
    }

    private static let currencyPattern = #"\$?\s*(\d+[.,]\d{2})"#
    private static let multiBuyPattern = #"(\d+)\s*(?:/|for)\s*\$?\s*(\d+(?:[.,]\d{2})?)"#
    private static let splitCurrencyPattern = #"(^|[^\d])(\d{1,3})\s*(?:\n|\s)\s*(\d{2})(?=$|[^\d])"#
    private static let impliedCurrencyPattern = #"(^|[^\d])(\d{3,4})(?=$|[^\d])"#
    private static let simplePricePattern = #"\$?\s*\d+[.,]\d{2}"#
    private static let shelfCodePattern = #"^[A-Z0-9]{2,}(?:[/\-][A-Z0-9]{2,})+$"#
    private static let skuLikeTokenPattern = #"^[A-Z]*\d+[A-Z\d\-\/]*$"#
    private static let poundsPerKilogram = Decimal(string: "2.2046226218")!
    private static let supportedOCRLinePattern = #"^[\p{Latin}\p{N}\p{P}\p{Zs}]+$"#
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

    static func extract(from text: [String]) -> OCRResult {
        extract(
            from: text.map { OCRTextObservation(string: $0, confidence: 0) }
        )
    }

    static func extract(from observations: [OCRTextObservation]) -> OCRResult {
        let supportedObservations = observations.filter {
            isSupportedOCRLine($0.string)
        }
        let cleanedObservations = removeObviousNoise(from: supportedObservations)
        let consolidatedObservations = consolidateObservations(cleanedObservations)
        let text = consolidatedObservations.map(\.string)

        
        // TODO: Foundation Model the text
        // https://developer.apple.com/documentation/FoundationModels
        let session = LanguageModelSession(instructions: Instructions {
            """
            You are a Retail Shelf Assistant. Translate raw OCR text from store shelf images into clean, structured product entries.

            PERSONA: High-precision retail data extractor. Convert OCR noise into a single, accurate shopping list entry.

            EXTRACTION RULES

            Product Identification:
            - Combine brand + variety/flavor + size into one descriptor (e.g., "Oreo Double Stuf 15.35oz")
            - If a brand name appears multiple times, treat it as the target product
            - Ignore category signage, neighboring items, shelf location codes, and stock numbers

            Price Identification (priority order):
            1. Promotional price — "Buy X for $Y" or "2 for $X" always takes precedence
            2. Standard format — $X.XX or X.XX near keywords: "Sale", "Each", "lb", "Price"
            3. Raw digit clusters — interpret 3–4 digit strings near the product as currency (e.g., "499" → "$4.99")

            De-Noising:
            - Remove duplicates, OCR artifacts (e.g., "|||", "___", "---"), barcodes, and unrelated metadata
            - Discard partial text from neighboring products

            ERROR HANDLING
            - No price found → Price: Price not detected
            - Text too garbled to identify product → Unable to identify item from OCR data
            """
        })
        let prompt = Prompt {
            "Summarize this OCR text from my purchase for my record keeping:"
            text.map { Prompt($0) }
        }
        Task {
            do {
                let summary = try await session.respond(to: prompt).content
                print(summary)
            } catch let error as LanguageModelSession.GenerationError {
//                switch error {
//                case .historyTokenExpired:
//                    print("History Token expired.")
//                case .exceededContextWindowSize(let string):
//                    print("Exceeded context window size. Generated: \(string)")
//                case .assetsUnavailable(_):
//                    <#code#>
//                case .guardrailViolation(_):
//                    <#code#>
//                case .unsupportedGuide(_):
//                    <#code#>
//                case .unsupportedLanguageOrLocale(_):
//                    <#code#>
//                case .decodingFailure(_):
//                    <#code#>
//                case .rateLimited(_):
//                    <#code#>
//                case .concurrentRequests(_):
//                    <#code#>
//                case .refusal(_, _):
//                    <#code#>
//                default:
//                    print(error)
//                }
                
                if let failureReason = error.failureReason {
                    print(failureReason)
                }
                if let recoverySuggestion = error.recoverySuggestion {
                    print(recoverySuggestion)
                }
                if let helpAnchor = error.helpAnchor {
                    print(helpAnchor)
                }
            } catch {
                print(error.localizedDescription)
            }
        }
        
        
        
        let normalizedText = text.joined(separator: "\n").replacingOccurrences(of: ",", with: ".")
        let priceCandidates = extractPriceCandidates(from: consolidatedObservations)
        let unit = detectUnit(in: normalizedText)
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let itemNameHint = lines.first { line in
            !line.contains("$") && detectUnit(in: line) == nil && !line.contains(where: { $0.isNumber })
        }

        return OCRResult(
            rawText: text.joined(separator: "\n"),
            itemNameHint: itemNameHint,
            price: priceCandidates.first?.value,
            unit: unit,
            quantity: priceCandidates.first?.quantity,
            confidence: priceCandidates.first?.confidence ?? averageConfidence(in: consolidatedObservations) ?? 0.1,
            priceCandidates: priceCandidates
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

    private static func removeObviousNoise(from observations: [OCRTextObservation]) -> [OCRTextObservation] {
        var seenKeys = Set<String>()

        return observations.compactMap { observation in
            let sanitized = sanitizeOCRLine(observation.string)
            guard !sanitized.isEmpty else {
                return nil
            }

            guard !isObviousNoiseLine(sanitized) else {
                return nil
            }

            let key = normalizedWords(in: sanitized).joined(separator: " ")
            guard !key.isEmpty else {
                return nil
            }

            guard seenKeys.insert(key).inserted else {
                return nil
            }

            return OCRTextObservation(string: sanitized, confidence: observation.confidence)
        }
    }

    private static func isObviousNoiseLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let words = normalizedWords(in: trimmed)
        guard !words.isEmpty else {
            return true
        }

        let hasDigits = trimmed.contains(where: \.isNumber)
        let hasLetters = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        let hasPriceSignal = containsPriceSignal(in: trimmed)
        let hasUnitSignal = detectUnit(in: trimmed) != nil

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

    private static func consolidateObservations(_ observations: [OCRTextObservation]) -> [OCRTextObservation] {
        var clusterOrder: [String] = []
        var clusterBest: [String: ConsolidatedObservation] = [:]
        var singleWordFrequency: [String: Int] = [:]

        for observation in observations {
            let sanitized = sanitizeOCRLine(observation.string)
            guard !sanitized.isEmpty else {
                continue
            }

            let words = normalizedWords(in: sanitized)
            guard !words.isEmpty else {
                continue
            }

            let hasDigits = words.contains { word in
                word.contains(where: \.isNumber)
            }

            if !hasDigits && words.count == 1 {
                singleWordFrequency[words[0], default: 0] += 1
            }

            let key = words.joined(separator: " ")
            guard !key.isEmpty else {
                continue
            }

            var clusterKey = key
            if !hasDigits && words.count == 1 {
                let word = words[0]
                if let nearMatch = clusterBest.keys.first(where: { existingKey in
                    isSingleWordNearMatch(word, existingKey)
                }) {
                    clusterKey = nearMatch
                }
            }

            let candidate = ConsolidatedObservation(
                observation: OCRTextObservation(string: sanitized, confidence: observation.confidence),
                words: words,
                hasDigits: hasDigits
            )

            if let current = clusterBest[clusterKey] {
                if shouldReplaceClusterRepresentative(current: current, candidate: candidate) {
                    clusterBest[clusterKey] = candidate
                }
            } else {
                clusterOrder.append(clusterKey)
                clusterBest[clusterKey] = candidate
            }
        }

        let kept = clusterOrder.compactMap { clusterBest[$0] }
        let multiWordVocabulary = Set(
            kept
                .filter { !$0.hasDigits && $0.words.count >= 2 }
                .flatMap(\.words)
        )

        return kept.compactMap { entry in
            if !entry.hasDigits,
               entry.words.count == 1,
               let word = entry.words.first,
               singleWordFrequency[word, default: 0] > 1,
               multiWordVocabulary.contains(word) {
                return nil
            }
            return entry.observation
        }
    }

    private static func shouldReplaceClusterRepresentative(
        current: ConsolidatedObservation,
        candidate: ConsolidatedObservation
    ) -> Bool {
        if candidate.observation.confidence != current.observation.confidence {
            return candidate.observation.confidence > current.observation.confidence
        }
        return candidate.observation.string.count > current.observation.string.count
    }

    private static func sanitizeOCRLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        return trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func normalizedWords(in line: String) -> [String] {
        let lowered = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalized = lowered.replacingOccurrences(
            of: #"[^\p{L}\p{N}]+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func isSingleWordNearMatch(_ lhs: String, _ rhsKey: String) -> Bool {
        guard !lhs.isEmpty else {
            return false
        }
        guard !rhsKey.contains(" ") else {
            return false
        }
        return editDistanceAtMostOne(lhs, rhsKey)
    }

    private static func editDistanceAtMostOne(_ lhs: String, _ rhs: String) -> Bool {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let lengthDelta = abs(lhsChars.count - rhsChars.count)
        if lengthDelta > 1 {
            return false
        }

        var i = 0
        var j = 0
        var mismatches = 0

        while i < lhsChars.count && j < rhsChars.count {
            if lhsChars[i] == rhsChars[j] {
                i += 1
                j += 1
                continue
            }

            mismatches += 1
            if mismatches > 1 {
                return false
            }

            if lhsChars.count > rhsChars.count {
                i += 1
            } else if lhsChars.count < rhsChars.count {
                j += 1
            } else {
                i += 1
                j += 1
            }
        }

        if i < lhsChars.count || j < rhsChars.count {
            mismatches += 1
        }

        return mismatches <= 1
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
                confidence: observation.confidence
            )
        }

        for observation in normalizedObservations {
            candidates.append(contentsOf: extractInlinePriceCandidates(from: observation))
        }

        if let regex = try? NSRegularExpression(pattern: splitCurrencyPattern) {
            let combinedObservations = zip(normalizedObservations, normalizedObservations.dropFirst()).map { lhs, rhs in
                OCRTextObservation(
                    string: "\(lhs.string)\n\(rhs.string)",
                    confidence: min(lhs.confidence, rhs.confidence)
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
                        priority: 3,
                        sourceText: observation.string,
                        confidence: observation.confidence
                    )
                )
            }
        }

        if let regex = try? NSRegularExpression(pattern: impliedCurrencyPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
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
}
