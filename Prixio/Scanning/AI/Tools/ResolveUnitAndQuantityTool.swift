//
//  ResolveUnitAndQuantityTool.swift
//  Prixio
//
//  A model-callable adapter over PriceParsingUnitResolver's text methods. Sanity-
//  checks multi-buy, pack count, and per-lb/kg/100g/each from printed unit text.
//  Shared adapter for future agents; not registered on the Capture flow.
//  See AIPriceExtractionTools.md §6.2.
//

import Foundation
import FoundationModels

struct ResolveUnitAndQuantityTool: Tool {
    let name = "resolveUnitAndQuantity"
    let description = "Resolve a unit and quantity from the printed unit text."

    @Generable
    struct Arguments {
        let unitText: String
    }

    @Generable
    struct Output {
        let unit: UnitType?
        let quantity: Decimal?
    }

    func call(arguments: Arguments) async throws -> Output {
        // PriceParsingUnitResolver is main-actor-isolated; hop to it from this nonisolated
        // Tool.call (tools-doc §6.3 bridging). The work is pure text parsing.
        await MainActor.run {
            let resolver = PriceParsingUnitResolver()
            let unit = resolver.detectUnit(in: arguments.unitText)
            let quantity = resolver.inferOfferQuantity(in: arguments.unitText)
                ?? resolver.inferPackQuantity(in: arguments.unitText)
                ?? resolver.detectQuantity(in: arguments.unitText, unit: unit)
            return Output(unit: unit, quantity: quantity)
        }
    }
}
