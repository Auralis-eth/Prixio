import Foundation

enum ItemKeyNormalizer {
    private static let removableUnitWords: Set<String> = [
        "g", "gram", "grams", "kg", "kilogram", "kilograms",
        "ml", "l", "liter", "liters", "litre", "litres",
        "oz", "lb", "lbs", "pound", "pounds",
        "pk", "pack", "packs", "ct", "count", "counts", "each", "ea",
        "dozen", "doz"
    ]

    /// Spelled-out counts that act as quantities when followed by a unit (e.g. "One
    /// Dozen", "Six Pack"). Deliberately excludes "a"/"an" (articles) to avoid
    /// stripping them from real names.
    private static let numberWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "half"
    ]

    /// Matches a size/quantity measurement — a number (with an optional decimal) and
    /// an optional space, then a unit — as a whole token. Stripped *before* the
    /// non-alphanumeric fold so a decimal pack size ("1.89 L", "454.5 g") is removed
    /// intact rather than splitting into a dangling number ("1") that would become the
    /// item's head noun and break generic-query rollup. Longer unit spellings are
    /// listed before their prefixes (e.g. "ml" before "l") so the right one matches.
    private static let sizeMeasurementPattern =
        #"\b\d+(?:\.\d+)?\s?(?:kilograms?|kgs?|grams?|g|millilitres?|milliliters?|mls?|litres?|liters?|lbs?|pounds?|ounces?|oz|l|counts?|cts?|packs?|pk|dozen|doz)\b"#

    static func normalize(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: sizeMeasurementPattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)

        let tokens = folded.split(whereSeparator: \.isWhitespace).map(String.init)
        var normalizedTokens: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            let next = tokens.indices.contains(index + 1) ? tokens[index + 1] : nil

            // A count (digit or spelled-out number word) immediately before a unit is
            // a quantity, not part of the name: "6 pack", "One Dozen", "Twelve Pack".
            // Number words are only dropped when a unit follows, so a brand like
            // "One A Day" (no trailing unit) is preserved.
            if token.allSatisfy(\.isNumber) || Self.numberWords.contains(token),
               let next, removableUnitWords.contains(next) {
                index += 2
                continue
            }

            if isCompactSizeToken(token) || removableUnitWords.contains(token) {
                index += 1
                continue
            }

            normalizedTokens.append(singularized(token))
            index += 1
        }

        return normalizedTokens.joined(separator: " ")
    }

    /// The normalized tokens of a value — the same folding/unit-stripping/singularizing pipeline as
    /// `normalize`, then split on spaces. An empty or unit-only value yields no tokens.
    static func tokens(_ value: String) -> [String] {
        let normalized = normalize(value)
        guard !normalized.isEmpty else {
            return []
        }
        return normalized.split(separator: " ").map(String.init)
    }

    /// Whether a (possibly generic) shopping/query item matches a stored entry's item, allowing a
    /// generic query to roll up more-specific products. True when the keys are identical, or when
    /// every token of the query also appears in the entry **and** the query's head noun (its last
    /// token) is the entry's head noun — so "sour cream" matches "Daisy Sour Cream", "butter"
    /// matches "Salted Butter", and "milk" matches "Almond Milk", but the generic word being a mere
    /// modifier in the entry is rejected ("milk" ✗ "milk chocolate", "cream" ✗ "cream cheese"), a
    /// more-specific query never matches a broader entry ("daisy sour cream" ✗ "sour cream"), and
    /// unrelated items never match.
    ///
    /// The head-noun anchor mirrors `PriceInsightEngine.areSubstitutable`. Known limitation: compound
    /// products whose head noun *is* the generic word still match ("peanut butter" under "butter"),
    /// since separating them needs lexical knowledge this normalizer doesn't have.
    ///
    /// Inputs may be raw or already-normalized; both sides are normalized internally.
    static func matches(queryKey: String, entryKey: String) -> Bool {
        let queryTokens = tokens(queryKey)
        let entryTokens = tokens(entryKey)
        guard let queryHead = queryTokens.last else {
            // An empty query only matches an (equally empty) entry — never rolls up real products.
            return entryTokens.isEmpty
        }
        // The query's head noun must also be the entry's head noun, so a generic query only rolls up
        // products that refine it (brand/adjective in front), not ones that merely mention the word.
        guard entryTokens.last == queryHead else {
            return false
        }
        let entrySet = Set(entryTokens)
        return queryTokens.allSatisfy(entrySet.contains)
    }

    private static func isCompactSizeToken(_ token: String) -> Bool {
        token.range(
            of: #"^\d+(?:g|kg|ml|l|oz|lb|lbs|pk|ct)$"#,
            options: .regularExpression
        ) != nil
    }

    private static func singularized(_ token: String) -> String {
        guard token.count > 3, token.hasSuffix("s") else {
            return token
        }
        if token.hasSuffix("ss") || token.hasSuffix("us") {
            return token
        }
        if token.hasSuffix("ies"), token.count > 4 {
            return String(token.dropLast(3)) + "y"
        }
        // Plurals that add "-es" to a singular ending in -o (tomatoes → tomato, potatoes → potato).
        if token.hasSuffix("oes"), token.count > 4 {
            return String(token.dropLast(2))
        }
        // Plurals that add "-es" after a sibilant (peaches → peach, dishes → dish, boxes → box,
        // glasses → glass). Restricted to these endings so "houses"/"roses" aren't over-stemmed.
        if token.hasSuffix("ches") || token.hasSuffix("shes") ||
            token.hasSuffix("xes") || token.hasSuffix("zes") || token.hasSuffix("sses") {
            return String(token.dropLast(2))
        }
        return String(token.dropLast())
    }
}
