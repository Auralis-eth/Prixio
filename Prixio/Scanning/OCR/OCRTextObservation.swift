//
//  OCRTextObservation.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreGraphics
import Foundation

struct OCRTextObservation {
    let string: String
    let confidence: Float
    let boundingBox: CGRect?
    let alternateStrings: [String]
    
    var cleanlinessScore: Double {
        let currencyBonus = string.contains("$") ? 0.2 : 0
        let digitPenalty = Double(string.digitsAsLettersCount()) * 0.05
        return Double(confidence) + currencyBonus - digitPenalty
    }

    var allCandidateStrings: [String] {
        [string] + alternateStrings
    }

    var likelyCompactPriceAlternates: [String] {
        allCandidateStrings.filter { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.range(of: #"^\$?\d{3,4}$"#, options: .regularExpression) != nil
        }
    }

    init(
        string: String,
        confidence: Float,
        boundingBox: CGRect? = nil,
        alternateStrings: [String] = []
    ) {
        self.string = string
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.alternateStrings = Array(
            NSOrderedSet(
                array: alternateStrings
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0 != string }
            )
        ) as? [String] ?? alternateStrings
    }
}
