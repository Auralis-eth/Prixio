//
//  OCRTextObservation.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

struct OCRTextObservation {
    let string: String
    let confidence: Float
    
    var cleanlinessScore: Double {
        let currencyBonus = string.contains("$") ? 0.2 : 0
        let digitPenalty = Double(string.digitsAsLettersCount()) * 0.05
        return Double(confidence) + currencyBonus - digitPenalty
    }
}
