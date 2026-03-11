//
//  ConsolidateObservations.swift
//  Prixio
//
//  Created by Daniel Bell on 3/10/26.
//

import Foundation

struct ConsolidateObservations {
    private static let canonicalPricePattern = #"^[sS\$]*\s*(\d+[.,]\d{2})"#
    private struct ConsolidatedObservation {
        let observation: OCRTextObservation
        let words: [String]
        let hasDigits: Bool
    }
    static func consolidateObservations(_ observations: [OCRTextObservation]) -> [OCRTextObservation] {
        var clusterOrder: [String] = []
        var clusterBest: [String: ConsolidatedObservation] = [:]
        var singleWordFrequency: [String: Int] = [:]
        let nearbyVocabulary = nearbyMultiWordVocabulary(from: observations)

        for (index, observation) in observations.enumerated() {
            let sanitized = observation.string.sanitizeOCRLine()
            guard !sanitized.isEmpty else {
                continue
            }
            guard isMeaningfulObservationLine(sanitized) else {
                continue
            }

            let words = comparisonNormalizedWords(in: sanitized)
            guard !words.isEmpty else {
                continue
            }

            let hasDigits = words.contains { word in
                word.contains(where: \.isNumber)
            }

            if !hasDigits && words.count == 1 {
                singleWordFrequency[words[0], default: 0] += 1
            }

            let key = words.joined(separator: " ")
            guard !key.isEmpty else {
                continue
            }

            var clusterKey = key
            if !hasDigits && !words.isEmpty {
                if words.count >= 2,
                   let nearMultiWordKey = clusterBest.keys.first(where: { existingKey in
                       let existingWords = existingKey
                           .split(separator: " ")
                           .map(String.init)
                       return isNearMultiWordMatch(words, existingWords)
                   }) {
                    clusterKey = nearMultiWordKey
                }

                for word in words {
                    let neighborhood = nearbyVocabulary[index]
                    if let nearMatch = clusterBest.keys.first(where: { existingKey in
                        let hasConsensus = singleWordFrequency[existingKey, default: 0] >= 2
                        let hasContextualAnchor = neighborhood.contains(word) || neighborhood.contains(existingKey)
                        return isSingleWordNearMatch(word, existingKey) && (hasConsensus || hasContextualAnchor)
                    }) {
                        if clusterKey == key {
                            clusterKey = nearMatch
                        } else {
                            clusterKey += nearMatch
                        }
                    }
                }
            }

            let candidate = ConsolidatedObservation(
                observation: OCRTextObservation(string: sanitized, confidence: observation.confidence),
                words: words,
                hasDigits: hasDigits
            )

            if let current = clusterBest[clusterKey] {
                if shouldReplaceClusterRepresentative(current: current, candidate: candidate) {
                    clusterBest[clusterKey] = candidate
                }
            } else {
                clusterOrder.append(clusterKey)
                clusterBest[clusterKey] = candidate
            }
        }

        let kept = clusterOrder.compactMap { clusterBest[$0] }

        return kept.compactMap { entry in
            if shouldAbsorbDescription(entry, within: kept) {
                return nil
            }
            return entry.observation
        }
    }
    
    private static func shouldReplaceClusterRepresentative(
        current: ConsolidatedObservation,
        candidate: ConsolidatedObservation
    ) -> Bool {
        let candidateScore = cleanlinessScore(for: candidate.observation)
        let currentScore = cleanlinessScore(for: current.observation)
        if candidateScore != currentScore {
            return candidateScore > currentScore
        }
        if candidate.observation.confidence != current.observation.confidence {
            return candidate.observation.confidence > current.observation.confidence
        }
        return candidate.observation.string.count > current.observation.string.count
    }
    
    private static func isSingleWordNearMatch(_ lhs: String, _ rhsKey: String) -> Bool {
        guard !lhs.isEmpty else {
            return false
        }
        guard !rhsKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return lhs.editDistanceAtMostOne(rhsKey)
    }
    
    private static func isNearMultiWordMatch(_ lhsWords: [String], _ rhsWords: [String]) -> Bool {
        guard lhsWords.count >= 2, lhsWords.count == rhsWords.count else {
            return false
        }

        var nonExactCount = 0
        for (lhs, rhs) in zip(lhsWords, rhsWords) {
            if lhs == rhs {
                continue
            }

            guard isLikelyOCRTokenVariant(lhs, rhs) else {
                return false
            }

            nonExactCount += 1
            if nonExactCount > 1 {
                return false
            }
        }

        return true
    }
    
    private static func nearbyMultiWordVocabulary(from observations: [OCRTextObservation], radius: Int = 1) -> [Set<String>] {
        let tokenized = observations.map { observation in
            comparisonNormalizedWords(in: observation.string.sanitizeOCRLine())
        }

        return tokenized.enumerated().map { index, _ in
            let lowerBound = max(0, index - radius)
            let upperBound = min(tokenized.count - 1, index + radius)
            var vocabulary = Set<String>()

            for neighbor in lowerBound...upperBound where neighbor != index {
                let words = tokenized[neighbor]
                guard words.count >= 2 else {
                    continue
                }
                words.forEach { vocabulary.insert($0) }
            }

            return vocabulary
        }
    }
    
    private static func cleanlinessScore(for observation: OCRTextObservation) -> Double {
        let confidenceScore = Double(observation.confidence)
        let currencyBonus = observation.string.contains("$") ? 0.2 : 0
        let digitPenalty = Double(observation.string.digitsAsLettersCount()) * 0.05
        return confidenceScore + currencyBonus - digitPenalty
    }

    private static func shouldAbsorbDescription(
        _ candidate: ConsolidatedObservation,
        within observations: [ConsolidatedObservation]
    ) -> Bool {
        guard !candidate.hasDigits else {
            return false
        }

        for observation in observations {
            guard observation.observation.string != candidate.observation.string ||
                    observation.words != candidate.words else {
                continue
            }
            guard !observation.hasDigits else {
                continue
            }
            guard observation.words.count > candidate.words.count else {
                continue
            }
            if observation.words.containsSubphrase(candidate.words) {
                return true
            }
        }

        return false
    }

    private static func isMeaningfulObservationLine(_ line: String) -> Bool {
        guard line.count > 1 else {
            return false
        }

        return line.unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }
    
    private static func comparisonNormalizedWords(in line: String) -> [String] {
        let lowered = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalized = lowered.replacingOccurrences(
            of: #"[^\p{L}\p{N}\.,\$]+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map { comparisonToken(from: String($0)) }
            .filter { !$0.isEmpty }
    }
    
    private static func isLikelyOCRTokenVariant(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.editDistanceAtMostOne(rhs) {
            return true
        }

        if abs(lhs.count - rhs.count) <= 2, min(lhs.count, rhs.count) >= 5 {
            return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
        }

        return false
    }
    
    private static func comparisonToken(from token: String) -> String {
        if let canonicalPrice = canonicalPriceToken(token) {
            return canonicalPrice
        }
        return token.unifiedOCRToken()
    }
    
    private static func canonicalPriceToken(_ token: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: canonicalPricePattern) else {
            return nil
        }
        let range = NSRange(token.startIndex..., in: token)
        guard let match = regex.firstMatch(in: token, range: range),
              let coreRange = Range(match.range(at: 1), in: token)
        else {
            return nil
        }
        return token[coreRange].replacingOccurrences(of: ",", with: ".")
    }
}

private extension Array where Element == String {
    func containsSubphrase(_ candidate: [String]) -> Bool {
        guard !candidate.isEmpty, count >= candidate.count else {
            return false
        }
        guard count > candidate.count else {
            return false
        }

        for startIndex in 0...(count - candidate.count) {
            let slice = Array(self[startIndex..<(startIndex + candidate.count)])
            if slice == candidate {
                return true
            }
        }

        return false
    }
}
