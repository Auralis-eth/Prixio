//
//  PriceParsingService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation
import FoundationModels

enum PriceParsingService {
    private static let currencyPattern = #"\$?\s*(\d+[.,]\d{2})"#
    private static let multiBuyPattern = #"(\d+)\s*(?:/|for)\s*\$?\s*(\d+(?:[.,]\d{2})?)"#
    private static let splitCurrencyPattern = #"(^|[^\d])(\d{1,3})\s*(?:\n|\s)\s*(\d{2})(?=$|[^\d])"#
    private static let impliedCurrencyPattern = #"(^|[^\d])(\d{3,4})(?=$|[^\d])"#
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
        let cleanedObservations = observations.filter {
            isSupportedOCRLine($0.string)
        }
        let text = cleanedObservations.map(\.string)

        
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
        let priceCandidates = extractPriceCandidates(from: cleanedObservations)
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
            confidence: priceCandidates.first?.confidence ?? averageConfidence(in: cleanedObservations) ?? 0.1,
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
