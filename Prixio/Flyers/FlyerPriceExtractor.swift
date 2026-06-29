import Foundation

/// Turns acquired flyer content into structured `FlyerPriceCandidate`s — step 5 of
/// `FlyerProcessingPlan.md`. Deterministic and pure (no network, no rendering, no
/// model), so it's fully unit-testable against captured-payload fixtures.
///
/// Two strategies, dispatched on how the content was acquired:
///
/// - **Captured JSON** (`.endpointJSON`): the SPA's own flyer fetch — the strongest
///   source. A generic recursive walker finds every object carrying both a name-ish
///   and a price-ish field, so it handles Flipp, Salesforce, and Walmart schemas
///   without hardcoding each. High confidence.
/// - **Harvested text** (`.renderedHTML` / `.imageOCR` / `.staticHTML`): pairs each
///   `$X.XX` token with the surrounding product text on its line. Best-effort and
///   lower confidence — the structured path is preferred whenever available.
struct FlyerPriceExtractor {
    /// Upper bound on candidates per banner so a pathological payload can't blow up.
    var maxCandidates = 600
    /// Cap on a stored source-text fragment, for review.
    var maxSourceTextLength = 200
    /// Upper bound on balanced JSON objects scanned from a payload.
    var maxObjects = 8000
    /// A single flyer item object is small; anything larger is a container or the
    /// truncated outer document, so it's skipped during the balanced-object scan.
    var maxObjectBytes = 20_000

    func extract(from content: FlyerAcquiredContent) -> FlyerExtractionResult {
        let candidates: [FlyerPriceCandidate]
        switch content.acquisitionMethod {
        case .endpointJSON:
            candidates = extractFromJSON(content.extractionPayload ?? "")
        case .staticHTML, .renderedHTML, .imageOCR, .endpointImage, .endpointPDF:
            candidates = extractFromText(content.extractionPayload ?? "")
        case .none:
            candidates = []
        }

        let deduped = dedupe(candidates)
        let message: String
        if deduped.isEmpty {
            message = content.extractionPayload?.isEmpty ?? true
                ? "No acquired payload to extract from."
                : "No price candidates found in \(content.payloadByteCount)-byte payload."
        } else {
            message = "Extracted \(deduped.count) price candidate\(deduped.count == 1 ? "" : "s") via \(content.acquisitionMethod?.label ?? "unknown")."
        }

        return FlyerExtractionResult(
            banner: content.banner,
            sourceURL: content.sourceURL,
            fetchedAt: content.fetchedAt,
            method: content.acquisitionMethod,
            candidates: deduped,
            message: message
        )
    }

    // MARK: - JSON strategy

    private func extractFromJSON(_ payload: String) -> [FlyerPriceCandidate] {
        guard !payload.isEmpty else { return [] }
        var out: [FlyerPriceCandidate] = []

        // Captured payloads are several JSON docs joined by newlines, and each is
        // individually truncated at the capture byte cap — so a strict whole- or
        // per-line `JSONSerialization` parse fails on exactly the priced documents.
        // Instead, scan the blob for every balanced `{ }` object: intact item objects
        // are recovered even when the enclosing document is truncated or concatenated.
        // Objects above `maxObjectBytes` are skipped — those are containers (or the
        // truncated outer document), never a single item — which also keeps us from
        // re-parsing the whole subtree at every nesting level.
        for objectText in balancedJSONObjects(in: payload) {
            guard out.count < maxCandidates else { break }
            guard let data = objectText.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                continue
            }
            if let candidate = candidate(from: dict) {
                out.append(candidate)
            }
        }
        return out
    }

    /// Returns the text of every balanced `{ }` object in `text` (at any nesting
    /// level) whose length is at most `maxObjectBytes`. Scans raw UTF-8 bytes,
    /// tracking string/escape state so braces inside string values are ignored.
    /// Tolerant of truncated and newline-concatenated documents — an unclosed outer
    /// object simply yields no range while its already-closed children still do.
    private func balancedJSONObjects(in text: String) -> [String] {
        let bytes = Array(text.utf8)
        var results: [String] = []
        var stack: [Int] = []
        var inString = false
        var escaped = false

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {        // backslash
                    escaped = true
                } else if byte == 0x22 {        // closing quote
                    inString = false
                }
            } else {
                switch byte {
                case 0x22:                       // opening quote
                    inString = true
                case 0x7B:                       // {
                    stack.append(index)
                case 0x7D:                       // }
                    if let start = stack.popLast() {
                        let length = index - start + 1
                        if length <= maxObjectBytes {
                            results.append(String(decoding: bytes[start...index], as: UTF8.self))
                            if results.count >= maxObjects { return results }
                        }
                    }
                default:
                    break
                }
            }
            index += 1
        }
        return results
    }

    /// Builds a candidate from a dict if it carries both a usable name and price.
    private func candidate(from dict: [String: Any]) -> FlyerPriceCandidate? {
        let lookup = CaseInsensitiveLookup(dict)
        guard let name = lookup.firstString(Self.nameKeys, maxLength: 160),
              let price = lookup.firstPrice(Self.priceKeys),
              isPlausiblePrice(price) else {
            return nil
        }

        // A name must read like a product: at least two letters. This drops
        // non-product objects the generic scan also reaches (SKU-only entries,
        // numeric ids, single-glyph labels) that could never match a list item.
        guard hasProductName(name) else { return nil }

        let regular = lookup.firstPrice(Self.regularKeys).flatMap { isPlausiblePrice($0) && $0 != price ? $0 : nil }
        let brand = lookup.firstString(Self.brandKeys, maxLength: 80)
        let size = lookup.firstString(Self.sizeKeys, maxLength: 80)
        let unit = lookup.firstPrice(Self.unitPriceKeys).flatMap { isPlausiblePrice($0) ? $0 : nil }
        let from = lookup.firstDate(Self.fromKeys)
        let to = lookup.firstDate(Self.toKeys)
        let memberOnly = lookup.hasMemberSignal(Self.memberSignalKeys)

        let kind: PriceKind
        if memberOnly {
            kind = .member
        } else if regular != nil {
            kind = .sale
        } else {
            kind = .regular
        }

        let combined = brand.map { "\($0) \(name)" } ?? name
        let normalizedKey = ItemKeyNormalizer.normalize(combined)
        // An empty normalized key (unit-only / punctuation-only name) can never
        // match a list item, so it's noise — drop it.
        guard !normalizedKey.isEmpty else { return nil }

        return FlyerPriceCandidate(
            productName: name,
            normalizedItemKey: normalizedKey,
            brand: brand,
            price: price,
            regularPrice: regular,
            priceKind: kind,
            packageSize: size,
            unitPrice: unit,
            saleStartDate: from,
            saleEndDate: to,
            memberOnly: memberOnly,
            sourceText: String(combined.prefix(maxSourceTextLength)),
            confidence: 0.9
        )
    }

    // MARK: - Text strategy

    private func extractFromText(_ payload: String) -> [FlyerPriceCandidate] {
        guard !payload.isEmpty else { return [] }
        var out: [FlyerPriceCandidate] = []
        for rawLine in payload.split(whereSeparator: { $0 == "\n" || $0 == "\t" }) {
            guard out.count < maxCandidates else { break }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let price = Self.firstDollarPrice(in: line), isPlausiblePrice(price) else {
                continue
            }
            // The product name is the line with price tokens stripped out.
            let name = line
                .replacingOccurrences(of: #"\$\s?\d{1,4}(\.\d{2})?"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—•|/.,"))
            guard name.count <= 120, hasProductName(name) else {
                continue
            }
            let normalizedKey = ItemKeyNormalizer.normalize(name)
            guard !normalizedKey.isEmpty else { continue }
            let lowered = line.lowercased()
            let memberOnly = ["member", "with card", "loyalty", "points card"].contains { lowered.contains($0) }
            out.append(FlyerPriceCandidate(
                productName: name,
                normalizedItemKey: normalizedKey,
                brand: nil,
                price: price,
                regularPrice: nil,
                priceKind: memberOnly ? .member : .unknown,
                packageSize: nil,
                unitPrice: nil,
                saleStartDate: nil,
                saleEndDate: nil,
                memberOnly: memberOnly,
                sourceText: String(line.prefix(maxSourceTextLength)),
                confidence: 0.5
            ))
        }
        return out
    }

    // MARK: - Helpers

    private func isPlausiblePrice(_ value: Decimal) -> Bool {
        value >= Decimal(string: "0.01")! && value <= 9999
    }

    /// Whether a string reads like a product name: at least two letters. Rejects
    /// SKU/numeric/punctuation-only "names" the generic JSON scan can reach.
    private func hasProductName(_ name: String) -> Bool {
        name.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count >= 2
    }

    /// Collapses duplicates on normalized item key + price, keeping the first
    /// occurrence and preserving order. Keying on (key, price) — rather than also
    /// kind/dates — folds the same product appearing in several captured sections
    /// (main grid, "recommended", related items) into one candidate, which is the
    /// dominant inflation source for the 100+-item banners.
    private func dedupe(_ candidates: [FlyerPriceCandidate]) -> [FlyerPriceCandidate] {
        var seen = Set<String>()
        var out: [FlyerPriceCandidate] = []
        for candidate in candidates {
            let key = "\(candidate.normalizedItemKey)|\(candidate.price)"
            if seen.insert(key).inserted {
                out.append(candidate)
            }
        }
        return out
    }

    /// First `$X.XX` (or `$ X`) price in a string, as Decimal.
    static func firstDollarPrice(in text: String) -> Decimal? {
        guard let regex = try? NSRegularExpression(pattern: #"\$\s?(\d{1,4}(?:\.\d{1,2})?)"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Decimal(string: String(text[captured]))
    }

    // MARK: - Field key vocabularies (matched case-insensitively)

    static let nameKeys = ["name", "title", "product_name", "productname", "item_name", "itemname", "display_name", "displayname", "sku_name", "description"]
    static let priceKeys = ["current_price", "currentprice", "sale_price", "saleprice", "price", "current", "price_text", "pricetext", "display_price", "displayprice", "final_price", "finalprice"]
    static let regularKeys = ["regular_price", "regularprice", "reg_price", "regprice", "was_price", "wasprice", "original_price", "originalprice", "list_price", "listprice"]
    static let brandKeys = ["brand", "brand_name", "brandname", "manufacturer", "vendor"]
    static let sizeKeys = ["size", "package_size", "packagesize", "sale_story", "salestory", "unit_of_measure", "uom"]
    static let unitPriceKeys = ["unit_price", "unitprice", "price_per_unit", "priceperunit", "ppu"]
    static let fromKeys = ["valid_from", "validfrom", "start_date", "startdate", "from_date", "fromdate", "effective_date", "effectivedate"]
    static let toKeys = ["valid_to", "validto", "end_date", "enddate", "to_date", "todate", "expiry_date", "expirydate", "expiration_date"]
    static let memberSignalKeys = ["loyalty", "member", "members_only", "membersonly", "loyalty_only", "is_member_price", "requires_loyalty"]
}

/// Case-insensitive view over a JSON dictionary, with typed coercions for the
/// messy reality of flyer payloads (numbers as numbers, prices as `"$3.99"`
/// strings, dates as ISO strings or epoch numbers).
private struct CaseInsensitiveLookup {
    private let lowered: [String: Any]

    init(_ dict: [String: Any]) {
        var map: [String: Any] = [:]
        for (key, value) in dict {
            map[key.lowercased()] = value
        }
        lowered = map
    }

    /// First non-empty string value among `keys`, bounded so a long marketing blob
    /// (e.g. a `description` paragraph) isn't mistaken for a product name.
    func firstString(_ keys: [String], maxLength: Int) -> String? {
        for key in keys {
            guard let value = lowered[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.count <= maxLength {
                    return trimmed
                }
            }
        }
        return nil
    }

    /// First parseable price among `keys`. Accepts numeric values and strings like
    /// `"$3.99"`, `"3.99"`, or `"2/$5.00"` (takes the dollar amount).
    func firstPrice(_ keys: [String]) -> Decimal? {
        for key in keys {
            guard let value = lowered[key] else { continue }
            if let number = value as? NSNumber {
                // Bools bridge to NSNumber; reject them.
                if CFGetTypeID(number) == CFBooleanGetTypeID() { continue }
                return Decimal(string: number.stringValue)
            }
            if let string = value as? String {
                if let dollar = FlyerPriceExtractor.firstDollarPrice(in: string) {
                    return dollar
                }
                if let plain = firstPlainNumber(in: string) {
                    return plain
                }
            }
        }
        return nil
    }

    private func firstPlainNumber(in text: String) -> Decimal? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,4}(?:\.\d{1,2})?)"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return Decimal(string: String(text[captured]))
    }

    /// First parseable date among `keys`. Accepts ISO-8601, `yyyy-MM-dd`, and epoch
    /// seconds/milliseconds.
    func firstDate(_ keys: [String]) -> Date? {
        for key in keys {
            guard let value = lowered[key] else { continue }
            if let string = value as? String, let date = Self.parseDate(string) {
                return date
            }
            if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                let seconds = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
                if seconds > 0 { return Date(timeIntervalSince1970: seconds) }
            }
        }
        return nil
    }

    func hasMemberSignal(_ keys: [String]) -> Bool {
        for key in keys {
            guard let value = lowered[key] else { continue }
            if let bool = value as? Bool, bool { return true }
            if let number = value as? NSNumber, number.boolValue { return true }
            if let string = value as? String {
                let lowered = string.lowercased()
                if lowered == "true" || lowered.contains("member") || lowered.contains("loyalty") { return true }
            }
        }
        return false
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let iso = isoFormatter.date(from: trimmed) { return iso }
        if let day = dayFormatter.date(from: String(trimmed.prefix(10))) { return day }
        return nil
    }
}
