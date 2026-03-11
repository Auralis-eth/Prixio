//
//  String.swift
//  Prixio
//
//  Created by Daniel Bell on 3/10/26.
//

import Foundation
extension String {
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
}
