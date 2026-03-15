//
//  Array+OCRTextObservation.swift
//  Prixio
//
//  Created by Daniel Bell on 3/11/26.
//

import Foundation

extension Array where Element == OCRTextObservation {
    func nearbyMultiWordVocabulary(radius: Int = 1) -> [Set<String>] {
        let tokenized = map { observation in
            observation.string.sanitizeOCRLine().comparisonNormalizedWords()
        }

        return tokenized.enumerated().map { index, _ in
            let lowerBound = Swift.max(0, index - radius)
            let upperBound = Swift.min(tokenized.count - 1, index + radius)
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
    
    func consolidateObservations() -> [OCRTextObservation] {
        var clusterOrder: [String] = []
        var clusterBest: [String: ConsolidatedObservation] = [:]
        var singleWordFrequency: [String: Int] = [:]
        let nearbyVocabulary = nearbyMultiWordVocabulary()

        for (index, observation) in enumerated() {
            let sanitized = observation.string.sanitizeOCRLine()
            guard !sanitized.isEmpty else {
                continue
            }
            guard sanitized.isMeaningfulObservationLine() else {
                continue
            }

            let words = sanitized.comparisonNormalizedWords()
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
                       return words.isNearMultiWordMatch(existingWords)
                   }) {
                    clusterKey = nearMultiWordKey
                }

                for word in words {
                    let neighborhood = nearbyVocabulary[index]
                    if let nearMatch = clusterBest.keys.first(where: { existingKey in
                        let hasConsensus = singleWordFrequency[existingKey, default: 0] >= 2
                        let hasContextualAnchor = neighborhood.contains(word) || neighborhood.contains(existingKey)
                        return word.isSingleWordNearMatch(existingKey) && (hasConsensus || hasContextualAnchor)
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
                observation: OCRTextObservation(
                    string: sanitized,
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox
                ),
                words: words,
                hasDigits: hasDigits
            )

            if let current = clusterBest[clusterKey] {
                if current.shouldReplaceClusterRepresentative(candidate: candidate) {
                    clusterBest[clusterKey] = candidate
                }
            } else {
                clusterOrder.append(clusterKey)
                clusterBest[clusterKey] = candidate
            }
        }

        let kept = clusterOrder.compactMap { clusterBest[$0] }

        return kept.compactMap { entry in
            if entry.shouldAbsorbDescription(within: kept) {
                return nil
            }
            return entry.observation
        }
    }
}
