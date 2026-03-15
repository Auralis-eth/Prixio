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
    
    var cleanlinessScore: Double {
        let currencyBonus = string.contains("$") ? 0.2 : 0
        let digitPenalty = Double(string.digitsAsLettersCount()) * 0.05
        return Double(confidence) + currencyBonus - digitPenalty
    }

    init(string: String, confidence: Float, boundingBox: CGRect? = nil) {
        self.string = string
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}
