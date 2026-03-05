//
//  PriceCandidate.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

struct PriceCandidate: Identifiable, Equatable {
    var id: String {
        "\(value)" + "\(confidence)" + ( quantity.map{ "\($0)" } ?? "")
    }

    let label: String
    let value: Decimal
    let quantity: Decimal?
    let priority: Int
    let sourceText: String
    let confidence: Float
}
