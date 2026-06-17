//
//  PriceParsingService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//
//  Source-of-truth domain logic over already-clean price fields. After the
//  OCR → image-AI migration this no longer parses pixels: the spatial/heuristic
//  extraction pipeline was removed. What remains is unit-price math, receipt
//  detection, the shared regex/token vocabulary, and the small text predicates
//  the surviving scorers/resolvers (retyped onto `TextObservation`) still call.
//

import Foundation

enum PriceParsingService {
    // Pure data carriers used by the surviving unit/name resolvers.
    struct UnitDetectionSignal {
        let unit: UnitType
        let score: Int
        let location: String.Index
    }

    struct ItemNameCandidate {
        let line: String
        let score: Int
        let lineIndex: Int
    }

    struct ItemNameResolution: Sendable {
        let evidenceName: String?
        let canonicalName: String?
    }

    static let currencyPattern = #"\$?\s*(\d+[.,]\d{2})"#
    static let multiBuyPattern = #"(\d+)\s*(?:/|for)\s*\$?\s*(\d+(?:[.,]\d{2})?)"#
    static let splitCurrencyPattern = #"(^|[^\d])(\d{1,3})\s*(?:\n|\s)\s*(\d{2})(?=$|[^\d])"#
    static let impliedCurrencyPattern = #"(^|[^\d])(\d{3,4})(?=$|[^\d])"#
    static let simplePricePattern = #"\$?\s*\d+[.,]\d{2}"#
    static let promoMarkerPattern = #"\b(member|club|loyalty|sale|special|deal)\b"#
    static let regularPriceMarkerPattern = #"\b(regular|reg(?:ular)?|was|original|compare)\b"#
    static let depositMarkerPattern = #"\b(deposit|dep|crv|enviro|fee)\b"#
    static let unitLabelPattern = #"\b(ea|each)\b|/(lb|lbs|kg|l|liter|litre|100\s?g)\b"#
    static let quantityFractionPattern = #"\b(\d+)\s*/\s*(\d+)\s*(?:lb|lbs|kg|l|liter|litre)\b"#
    static let quantityDecimalPattern = #"\b(\d+(?:[.,]\d+)?)\s*(?:lb|lbs|kg|l|liter|litre)\b"#
    static let buyGetPattern = #"\bbuy\s+(\d+|one|two|three|four|five)\s+get\s+(\d+|one|two|three|four|five)(?:\s+free)?\b"#
    static let monthNamePattern = #"\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b"#
    static let shelfCodePattern = #"^[A-Z0-9]{2,}(?:[/\-][A-Z0-9]{2,})+$"#
    static let skuLikeTokenPattern = #"^[A-Z]*\d+[A-Z\d\-\/]*$"#
    static let poundsPerKilogram = Decimal(string: "2.2046226218")!
    static let receiptMarkers = [
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
    static let itemNameIgnoredTokens: Set<String> = [
        "sale",
        "member",
        "members",
        "club",
        "loyalty",
        "special",
        "deal",
        "regular",
        "reg",
        "was",
        "compare",
        "price",
        "ea",
        "each",
        "lb",
        "lbs",
        "kg",
        "l",
        "liter",
        "litre",
        "pk",
        "pack",
        "ct",
        "count",
        "per"
    ]

    // MARK: - Unit-price math

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

    // MARK: - Capture classification

    static func looksLikeReceipt(text: String) -> Bool {
        let lowered = text.lowercased()
        let markerCount = receiptMarkers.reduce(into: 0) { count, marker in
            if lowered.contains(marker) {
                count += 1
            }
        }
        return markerCount >= 2
    }

    // MARK: - Shared text predicates
    //
    // Relocated from the deleted PriceParsingSnapshotBuilder. The surviving
    // scorers/resolvers and the new PriceExtractionValidator depend on these.

    static func isDescriptiveObservation(_ observation: any TextObservation) -> Bool {
        let line = observation.string
        return line.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            && !containsPriceSignal(in: line)
    }

    static func containsPriceSignal(in text: String) -> Bool {
        if text.contains("$") {
            return true
        }

        guard let regex = try? NSRegularExpression(pattern: simplePricePattern) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    static func isLikelyShelfCode(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: shelfCodePattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    static func isLikelySKU(_ text: String) -> Bool {
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

    static func isSizeToken(_ word: String) -> Bool {
        word.range(of: #"^\d{1,4}(g|kg|ml|l|oz|lb|pk|ct)$"#, options: .regularExpression) != nil
    }

    static func containsExplicitSizeToken(in line: String) -> Bool {
        let words = line.normalizedWords()
        if words.contains(where: { isSizeToken($0) }) {
            return true
        }
        if line.range(
            of: #"\d{1,2}\s*[x×]\s*\d{1,4}(?:\.\d+)?\s*(ml|g|kg|l|oz)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        return line.range(
            of: #"\d{1,4}\s*(ml|g|kg|l|oz|lb|pk|ct|count|pack)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
