//
//  String.swift
//  Prixio
//
//  Created by Daniel Bell on 3/10/26.
//

import Foundation
extension String {
    private static let canonicalPricePattern = #"^[sS\$]*\s*(\d+[.,]\d{2})"#

    func sanitizeOCRLine() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        return trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }

    func normalizedWords() -> [String] {
        let lowered = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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

    func digitsAsLettersCount() -> Int {
        let tokens = split(whereSeparator: \.isWhitespace)
            .map(String.init)
        var count = 0
        for token in tokens {
            let hasLetters = token.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            let hasDigits = token.contains(where: \.isNumber)
            guard hasLetters && hasDigits else {
                continue
            }
            count += token.filter { ["0", "1", "5", "8"].contains($0) }.count
        }
        return count
    }
    
    func unifiedOCRToken() -> String {
        let mapped = map { character in
            switch character {
            case "0", "o":
                return "o"
            case "1", "l", "i":
                return "l"
            case "5", "s":
                return "s"
            case "8", "b":
                return "b"
            default:
                return "\(character)"
            }
        }
        return mapped.filter { character in
            character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
        }
        .joined(separator: "")
    }
    
    func comparisonToken() -> String {
        if let canonicalPrice = canonicalPriceToken() {
            return canonicalPrice
        }
        return unifiedOCRToken()
    }

    func canonicalPriceToken() -> String? {
        guard let regex = try? NSRegularExpression(pattern: Self.canonicalPricePattern) else {
            return nil
        }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              let coreRange = Range(match.range(at: 1), in: self)
        else {
            return nil
        }
        return self[coreRange].replacingOccurrences(of: ",", with: ".")
    }

    func isMeaningfulObservationLine() -> Bool {
        guard count > 1 else {
            return false
        }

        return unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }

    func comparisonNormalizedWords() -> [String] {
        let lowered = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalized = lowered.replacingOccurrences(
            of: #"[^\p{L}\p{N}\.,\$]+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).comparisonToken() }
            .filter { !$0.isEmpty }
    }
}

extension String {
    func editDistanceAtMostOne(_ rhs: String) -> Bool {
        let lhsChars = Array(self)
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
    
    func isSingleWordNearMatch(_ rhsKey: String) -> Bool {
        guard !isEmpty else {
            return false
        }
        guard !rhsKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return editDistanceAtMostOne(rhsKey)
    }
    
    func isLikelyOCRTokenVariant(_ rhs: String) -> Bool {
        if editDistanceAtMostOne(rhs) {
            return true
        }

        if abs(count - rhs.count) <= 2, min(count, rhs.count) >= 5 {
            return hasPrefix(rhs) || rhs.hasPrefix(self)
        }

        return false
    }
}
