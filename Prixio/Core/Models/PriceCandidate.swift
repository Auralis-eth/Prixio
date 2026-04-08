//
//  PriceCandidate.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

enum PriceKind: String, Codable, Sendable {
    case shelf
    case sale
    case member
    case regular
    case save
    case deposit
    case unit
    case unknown
}

struct PriceCandidate: Identifiable, Equatable {
    var id: String {
        "\(value)" + "\(confidence)" + ( quantity.map{ "\($0)" } ?? "") + kind.rawValue
    }

    let label: String
    let value: Decimal
    let quantity: Decimal?
    let priority: Int
    let sourceText: String
    let kind: PriceKind
    let sourceLineIndexes: [Int]
    let confidence: Float
}
