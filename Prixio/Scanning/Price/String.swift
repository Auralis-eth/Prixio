//
//  String.swift
//  Prixio
//
//  Created by Daniel Bell on 3/10/26.
//
//  Generic text utilities still used by the surviving scorers/resolvers after the
//  OCR → image-AI migration. The Vision OCR-repair helpers (token unification,
//  edit-distance near-match, multi-word matching) were removed with the
//  consolidation/vocabulary pipeline that was their only caller.
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
}
