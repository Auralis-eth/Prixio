//
//  NormalizeUnitPriceTool.swift
//  Prixio
//
//  A model-callable adapter over the comparable unit-price math — the one piece
//  the model must NOT eyeball. Registered on the Capture flow's session
//  (ScanViewModel.captureTools) and shared with the Compare/Planner agents.
//

import Foundation
import FoundationModels

enum PriceToolError: Error {
    case notNormalizable
}

struct NormalizeUnitPriceTool: Tool {
    let name = "normalizeUnitPrice"
    let description = "Compute the comparable per-unit price from price, unit, and quantity."

    @Generable
    struct Arguments {
        let price: Decimal
        let unit: UnitType
        let quantity: Decimal?
    }

    @Generable
    struct Output {
        let normalizedUnitPrice: Decimal
        let normalizedUnit: UnitType
    }

    func call(arguments: Arguments) async throws -> Output {
        // PriceParsingService is main-actor-isolated; hop to it from this nonisolated Tool.call
        // (tools-doc §6.3 bridging). The work is pure value math.
        try await MainActor.run {
            guard let (value, unit) = PriceParsingService.normalize(
                price: arguments.price, unit: arguments.unit, quantity: arguments.quantity
            ) else { throw PriceToolError.notNormalizable }
            return Output(normalizedUnitPrice: value, normalizedUnit: unit)
        }
    }
}
