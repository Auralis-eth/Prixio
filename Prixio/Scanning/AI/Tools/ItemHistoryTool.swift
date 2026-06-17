//
//  ItemHistoryTool.swift
//  Prixio
//
//  A read-only model-callable adapter that grounds "is this a good price?" in
//  saved history. Shared adapter for future Compare/Planner agents; never wired
//  into the Capture flow and never writes SwiftData. See AIPriceExtractionTools.md §6.4.
//

import Foundation
import FoundationModels

struct ItemHistoryTool: Tool {
    let name = "itemPriceHistory"
    let description = "Look up saved price history for an item to judge a new price."

    let repository: PriceEntryRepository

    @Generable
    struct Arguments {
        @Guide(description: "The product name to look up.")
        let itemName: String
        let normalizedUnitType: UnitType
    }

    @Generable
    struct Output {
        let count: Int
        let cheapestPrice: Decimal?
        let typicalPrice: Decimal?
        let newestCapturedAtISO8601: String?
        let cheapestStoreName: String?
    }

    func call(arguments: Arguments) async throws -> Output {
        try await MainActor.run {
            let entries = try repository.cheapestEntries(
                for: arguments.itemName,
                normalizedUnitType: arguments.normalizedUnitType
            )
            let prices = entries.compactMap(\.normalizedUnitPriceValue)
            let cheapest = entries.first   // sorted ascending by normalizedUnitPriceValue
            let newest = entries.max(by: { $0.capturedAt < $1.capturedAt })
            return Output(
                count: entries.count,
                cheapestPrice: cheapest?.normalizedUnitPriceValue,
                typicalPrice: Self.median(of: prices),
                newestCapturedAtISO8601: newest.map { ISO8601DateFormatter().string(from: $0.capturedAt) },
                cheapestStoreName: cheapest?.storeChainNameSnapshot ?? cheapest?.storeLocationNameSnapshot
            )
        }
    }

    static func median(of values: [Decimal]) -> Decimal? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}
