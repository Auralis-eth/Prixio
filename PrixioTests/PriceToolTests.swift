import CoreLocation
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

    @Test(.tags(.ocr, .product))
    func itemHistoryReturnsEmptyOutputForBrandNewItem() async throws {
        let container = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let tool = ItemHistoryTool(repository: PriceEntryRepository(context: context))

        let output = try await tool.call(arguments: .init(itemName: "Dragon Fruit", normalizedUnitType: .kg))

        #expect(output.count == 0)
        #expect(output.cheapestPrice == nil)
        #expect(output.typicalPrice == nil)
        #expect(output.cheapestStoreName == nil)
        #expect(output.newestCapturedAtISO8601 == nil)
    }

    @Test(.tags(.ocr, .product))
    func itemHistoryUsesOddMedianAndLocationNameFallback() async throws {
        let container = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let normalized = ItemKeyNormalizer.normalize("Bananas")

        context.insert(historyEntry(
            normalizedName: normalized,
            price: Decimal(4),
            capturedAt: Date(timeIntervalSince1970: 1_000),
            chainName: "Metro",
            locationName: nil
        ))
        context.insert(historyEntry(
            normalizedName: normalized,
            price: Decimal(2),
            capturedAt: Date(timeIntervalSince1970: 2_000),
            chainName: nil,
            locationName: "Market Stall 4"
        ))
        context.insert(historyEntry(
            normalizedName: normalized,
            price: Decimal(3),
            capturedAt: Date(timeIntervalSince1970: 3_000),
            chainName: "Loblaws",
            locationName: nil
        ))
        try context.save()

        let tool = ItemHistoryTool(repository: PriceEntryRepository(context: context))
        let output = try await tool.call(arguments: .init(itemName: "Bananas", normalizedUnitType: .kg))

        #expect(output.count == 3)
        #expect(output.cheapestPrice == Decimal(2))
        #expect(output.typicalPrice == Decimal(3))
        #expect(output.cheapestStoreName == "Market Stall 4")
    }

    @Test(.tags(.ocr, .product))
    func itemHistoryFiltersWrongUnitType() async throws {
        let container = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(historyEntry(
            normalizedName: ItemKeyNormalizer.normalize("Milk"),
            price: Decimal(5),
            unitType: .liter,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            chainName: "Co-op",
            locationName: nil
        ))
        try context.save()

        let tool = ItemHistoryTool(repository: PriceEntryRepository(context: context))
        let output = try await tool.call(arguments: .init(itemName: "Milk", normalizedUnitType: .kg))

        #expect(output.count == 0)
        #expect(output.cheapestPrice == nil)
        #expect(output.typicalPrice == nil)
    }

    @Test(.tags(.ocr, .product))
    func normalizeUnitPriceThrowsForNonPositivePrice() async throws {
        let tool = NormalizeUnitPriceTool()

        do {
            _ = try await tool.call(arguments: .init(price: Decimal.zero, unit: .each, quantity: nil))
            Issue.record("Expected NormalizeUnitPriceTool to throw for a zero price")
        } catch PriceToolError.notNormalizable {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(.tags(.ocr, .product))
    func normalizeUnitPriceDividesQuantityBeforeConvertingUnits() async throws {
        let tool = NormalizeUnitPriceTool()

        let output = try await tool.call(arguments: .init(price: Decimal(5), unit: .hundredGrams, quantity: Decimal(2)))

        #expect(output.normalizedUnit == .kg)
        #expect(output.normalizedUnitPrice == Decimal(25))
    }

    @Test(.tags(.ocr, .product))
    func resolveUnitAndQuantityGracefullyHandlesGarbageText() async throws {
        let tool = ResolveUnitAndQuantityTool()

        let output = try await tool.call(arguments: .init(unitText: "aisle marker only"))

        #expect(output.unit == nil)
        #expect(output.quantity == nil)
    }

    @Test(.tags(.ocr, .product))
    func resolveUnitAndQuantityPrefersOfferQuantityOverPackAndDetectedQuantity() async throws {
        let tool = ResolveUnitAndQuantityTool()

        let output = try await tool.call(arguments: .init(unitText: "2 for $7 6 pack $3.50/lb"))

        #expect(output.unit == .lb)
        #expect(output.quantity == Decimal(2))
    }

    @Test(.tags(.ocr, .product))
    func inferStoreContextPrioritizesChainReadFromScanText() async throws {
        let candidates = [
            storeCandidate(id: "safeway", chainName: "Safeway", locationName: "Safeway Kensington", distanceMeters: 120),
            storeCandidate(id: "walmart", chainName: "Walmart", locationName: "Walmart Deerfoot", distanceMeters: 240),
            storeCandidate(id: "coop", chainName: "Co-op", locationName: "Calgary Co-op Oakridge", distanceMeters: 90)
        ]
        let tool = InferStoreContextTool(
            service: StoreDetectionService(),
            location: nil,
            nearbyCandidates: candidates,
            lastStoreCandidate: nil
        )

        let output = try await tool.call(arguments: .init(
            storeNameHint: nil,
            relevantText: "Walmart\nGreat Value Milk\n$4.49"
        ))

        let firstSuggestion = try #require(output.first)
        #expect(firstSuggestion.chainName == "Walmart")
        #expect(firstSuggestion.locationName == "Walmart Deerfoot")
        #expect(output.map(\.locationName) == ["Walmart Deerfoot", "Safeway Kensington", "Calgary Co-op Oakridge"])
    }

    @Test(.tags(.ocr, .product))
    func inferStoreContextFallsBackToLastStoreWhenNoNearbyCandidatesExist() async throws {
        let lastStore = storeCandidate(
            id: "last",
            chainName: "Co-op",
            locationName: "Calgary Co-op Midtown",
            distanceMeters: 75
        )
        let tool = InferStoreContextTool(
            service: StoreDetectionService(),
            location: nil,
            nearbyCandidates: [],
            lastStoreCandidate: lastStore
        )

        let output = try await tool.call(arguments: .init(
            storeNameHint: nil,
            relevantText: "Organic Bananas\n$1.29 /lb"
        ))

        #expect(output.count == 1)
        let suggestion = try #require(output.first)
        #expect(suggestion.chainName == "Co-op")
        #expect(suggestion.locationName == "Calgary Co-op Midtown")
        #expect(suggestion.distanceMeters == 75)
    }

    private func historyEntry(
        normalizedName: String,
        price: Decimal,
        unitType: UnitType = .kg,
        capturedAt: Date,
        chainName: String?,
        locationName: String?
    ) -> PriceEntry {
        PriceEntry(
            capturedAt: capturedAt,
            itemNameRaw: "Bananas",
            itemNameNormalized: normalizedName,
            priceValue: price,
            unitType: unitType,
            normalizedUnitPriceValue: price,
            normalizedUnitType: unitType,
            storeChainNameSnapshot: chainName,
            storeLocationNameSnapshot: locationName,
            photoAssetId: UUID().uuidString
        )
    }

    private func storeCandidate(
        id: String,
        chainName: String?,
        locationName: String,
        distanceMeters: CLLocationDistance?
    ) -> StoreCandidate {
        StoreCandidate(
            id: id,
            chainName: chainName,
            locationName: locationName,
            address: nil,
            coordinate: nil,
            distanceMeters: distanceMeters,
            mapKitPlaceId: id
        )
    }
}
