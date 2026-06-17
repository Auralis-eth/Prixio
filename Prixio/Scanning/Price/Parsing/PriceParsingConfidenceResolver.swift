//
//  PriceParsingConfidenceResolver.swift
//  Prixio
//
//  After the OCR → image-AI migration the snapshot-coupled ambiguity/confidence
//  analysis was removed (the model now emits structured fields directly). What
//  survives are the pure text helpers the retyped scorers and the new
//  PriceExtractionValidator still call, retyped onto `TextObservation`.
//

import Foundation

struct PriceParsingConfidenceResolver {
    func sourceLineIndexes(
        for candidate: PriceCandidate,
        in observations: [any TextObservation]
    ) -> [Int] {
        if !candidate.sourceLineIndexes.isEmpty {
            return candidate.sourceLineIndexes
        }

        return observations.enumerated().compactMap { index, observation in
            let line = observation.string.lowercased()
            let source = candidate.sourceText.lowercased()
            return line.contains(source) || source.contains(line) ? index : nil
        }
    }

    func containsPhoneNumber(in text: String) -> Bool {
        text.range(of: #"\d{10,}"#, options: .regularExpression) != nil
    }

    func looksLikeDateLine(_ text: String) -> Bool {
        guard text.range(of: PriceParsingService.monthNamePattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return false
        }

        let hasDay = text.range(of: #"\b([12]?\d|3[01])\b"#, options: .regularExpression) != nil
        let hasYear = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        return hasDay || hasYear
    }

    func isProductDescriptor(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        guard !PriceParsingService.containsPriceSignal(in: trimmed) else {
            return false
        }
        guard !PriceParsingItemNameResolver().looksLikeReceiptFragment(trimmed) else {
            return false
        }
        guard !PriceParsingItemNameResolver().looksLikePromoBanner(trimmed) else {
            return false
        }
        guard trimmed.range(of: PriceParsingService.depositMarkerPattern, options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }
        guard trimmed.range(of: PriceParsingService.regularPriceMarkerPattern, options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }

        let words = trimmed.normalizedWords()
        let descriptiveTokens = words.filter { token in
            token.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
                && !PriceParsingService.itemNameIgnoredTokens.contains(token)
                && !PriceParsingItemNameResolver().isPureUnitToken(token)
        }

        return descriptiveTokens.count >= 1
    }
}
