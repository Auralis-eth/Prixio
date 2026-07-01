import Foundation

/// Pure helpers for judging whether a flyer payload carries real price data. Split out
/// so they carry no WebKit dependency — they're used by the endpoint acquisition path
/// (which counts price signals in fetched item JSON) and by tests.
enum FlyerPriceSignal {
    /// Counts flyer price signals across both `$X.XX` text and JSON `"price": 3.99`
    /// (or `current_price`) forms, since structured payloads carry prices as numeric
    /// fields without a `$`.
    static func priceSignalCount(in text: String) -> Int {
        let lower = text.lowercased()
        let dollar = FlyerSourceShapeClassifier.priceTokenCount(in: lower)
        let json = regexMatchCount(
            "\"(current_|sale_|reg_)?price\"\\s*:\\s*\"?\\$?\\d{1,4}(\\.\\d{1,2})?",
            in: lower
        )
        return dollar + json
    }

    /// Whether a payload is JSON (object/array) rather than JavaScript/HTML. Flyer item
    /// data is always JSON; this rejects code (e.g. Flipp's webpack bundles, which start
    /// with `(self.webpack…`) that merely mentions price-like words in source text.
    static func isJSONPayload(_ body: String) -> Bool {
        let trimmed = body.drop { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" || $0 == "\u{FEFF}" }
        guard let first = trimmed.first else { return false }
        return first == "{" || first == "["
    }

    private static func regexMatchCount(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
