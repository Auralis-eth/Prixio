//
//  OCRResult.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

struct OCRResult {
    var rawText: String
    var itemNameHint: String?
    var price: Decimal?
    var unit: UnitType?
    var quantity: Decimal?
    var confidence: Float?
    var priceCandidates: [PriceCandidate]
}
