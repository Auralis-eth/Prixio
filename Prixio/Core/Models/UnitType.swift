//
//  UnitType.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

enum UnitType: String, Codable, CaseIterable, Identifiable {
    case each
    case lb
    case kg
    case liter
    case hundredGrams

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .each:
            return "Each"
        case .lb:
            return "lb"
        case .kg:
            return "kg"
        case .liter:
            return "L"
        case .hundredGrams:
            return "100 g"
        }
    }
}
