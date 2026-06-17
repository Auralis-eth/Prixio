import Foundation

enum ItemKeyNormalizer {
    private static let removableUnitWords: Set<String> = [
        "g", "gram", "grams", "kg", "kilogram", "kilograms",
        "ml", "l", "liter", "liters", "litre", "litres",
        "oz", "lb", "lbs", "pound", "pounds",
        "pk", "pack", "packs", "ct", "count", "counts", "each", "ea"
    ]

    static func normalize(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)

        let tokens = folded.split(whereSeparator: \.isWhitespace).map(String.init)
        var normalizedTokens: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            let next = tokens.indices.contains(index + 1) ? tokens[index + 1] : nil

            if token.allSatisfy(\.isNumber), let next, removableUnitWords.contains(next) {
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
        return String(token.dropLast())
    }
}
