//
//  ConsolidatedObservation.swift
//  Prixio
//
//  Created by Daniel Bell on 3/10/26.
//

import Foundation

struct ConsolidatedObservation {
    let observation: OCRTextObservation
    let words: [String]
    let hasDigits: Bool
    
    func shouldAbsorbDescription(
        within observations: [ConsolidatedObservation]
    ) -> Bool {
        guard !hasDigits else {
            return false
        }

        for observation in observations {
            guard observation.observation.string != self.observation.string ||
                    observation.words != words else {
                continue
            }
            guard !observation.hasDigits else {
                continue
            }
            guard observation.words.count > words.count else {
                continue
            }
            if observation.words.containsSubphrase(words) {
                return true
            }
        }

        return false
    }
    
    func shouldReplaceClusterRepresentative(
        candidate: ConsolidatedObservation
    ) -> Bool {
        let candidateScore = candidate.observation.cleanlinessScore
        let currentScore = observation.cleanlinessScore
        if candidateScore != currentScore {
            return candidateScore > currentScore
        }
        if candidate.observation.confidence != observation.confidence {
            return candidate.observation.confidence > observation.confidence
        }
        return candidate.observation.string.count > observation.string.count
    }
}

