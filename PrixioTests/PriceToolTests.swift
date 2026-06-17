import Foundation
import SwiftData
import Testing
@testable import Prixio

@MainActor
struct PriceToolTests {
    @Test(.tags(.ocr, .product))
    func normalizeUnitPriceMatchesDomainMath() async throws {
        let tool = NormalizeUnitPriceTool()

        let each = try await tool.call(arguments: .init(price: Decimal(3), unit: .each, quantity: nil))
        #expect(each.normalizedUnit == .each)
        #expect(each.normalizedUnitPrice == Decimal(3))

        let perPound = try await tool.call(arguments: .init(price: Decimal(1), unit: .lb, quantity: nil))
        #expect(perPound.normalizedUnit == .kg)
        #expect(perPound.normalizedUnitPrice == PriceParsingService.poundsPerKilogram)
    }

    @Test(.tags(.ocr, .product))
    func resolveUnitAndQuantityHandlesCommonTagPhrases() async throws {
        let tool = ResolveUnitAndQuantityTool()

        let perPound = try await tool.call(arguments: .init(unitText: "$3.99/lb"))
        #expect(perPound.unit == .lb)
        #expect(perPound.quantity == Decimal(1))

        let pack = try await tool.call(arguments: .init(unitText: "6 pack"))
        #expect(pack.unit == .each)
        #expect(pack.quantity == Decimal(6))

        let hundredGrams = try await tool.call(arguments: .init(unitText: "100g"))
        #expect(hundredGrams.unit == .hundredGrams)
        #expect(hundredGrams.quantity == Decimal(1))

        let multiBuy = try await tool.call(arguments: .init(unitText: "3 for $5"))
        #expect(multiBuy.quantity == Decimal(3))
    }

    @Test(.tags(.ocr, .product))
    func itemHistoryReportsCountCheapestAndMedian() async throws {
        let container = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let normalized = ItemKeyNormalizer.normalize("Bananas")

        context.insert(PriceEntry(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            itemNameRaw: "Bananas",
            itemNameNormalized: normalized,
            priceValue: Decimal(3),
            unitType: .kg,
            normalizedUnitPriceValue: Decimal(3),
            normalizedUnitType: .kg,
            storeChainNameSnapshot: "Metro",
            photoAssetId: "a"
        ))
        context.insert(PriceEntry(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            itemNameRaw: "Bananas",
            itemNameNormalized: normalized,
            priceValue: Decimal(2),
            unitType: .kg,
            normalizedUnitPriceValue: Decimal(2),
            normalizedUnitType: .kg,
            storeChainNameSnapshot: "Loblaws",
            photoAssetId: "b"
        ))
        try context.save()

        let tool = ItemHistoryTool(repository: PriceEntryRepository(context: context))
        let output = try await tool.call(arguments: .init(itemName: "Bananas", normalizedUnitType: .kg))

        #expect(output.count == 2)
        #expect(output.cheapestPrice == Decimal(2))
        #expect(output.typicalPrice == Decimal(string: "2.5"))
        #expect(output.cheapestStoreName == "Loblaws")
        #expect(output.newestCapturedAtISO8601 != nil)
    }
}
