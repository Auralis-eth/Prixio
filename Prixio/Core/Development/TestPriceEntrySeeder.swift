import Foundation
import SwiftData

#if DEBUG
@MainActor
enum TestPriceEntrySeeder {
    static let recordCount = 100

    private static let marker = "Prixio.TestPriceEntrySeeder.v1"

    static func seededCount(in entries: [PriceEntry]) -> Int {
        entries.filter(isSeededEntry).count
    }

    @MainActor
    static func insertRecords(into modelContext: ModelContext, now: Date = .now) throws {
        for entry in makeEntries(now: now) {
            modelContext.insert(entry)
        }
        try modelContext.save()
    }

    @MainActor
    static func deleteRecords(from entries: [PriceEntry], in modelContext: ModelContext) throws {
        for entry in entries where isSeededEntry(entry) {
            modelContext.delete(entry)
        }
        try modelContext.save()
    }

    private static func isSeededEntry(_ entry: PriceEntry) -> Bool {
        entry.ocrText == marker
    }

    private static func makeEntries(now: Date) -> [PriceEntry] {
        var entries: [PriceEntry] = []

        for (itemIndex, item) in itemSeeds.enumerated() {
            for (storeIndex, store) in storeSeeds.enumerated() {
                for captureIndex in 0..<2 {
                    entries.append(
                        makeEntry(
                            item: item,
                            itemIndex: itemIndex,
                            store: store,
                            storeIndex: storeIndex,
                            captureIndex: captureIndex,
                            now: now
                        )
                    )
                }
            }
        }

        return entries
    }

    private static func makeEntry(
        item: ItemSeed,
        itemIndex: Int,
        store: StoreSeed,
        storeIndex: Int,
        captureIndex: Int,
        now: Date
    ) -> PriceEntry {
        let capturedAt = Calendar.current.date(
            byAdding: .day,
            value: -(itemIndex + storeIndex + (captureIndex * 12)),
            to: now
        ) ?? now
        let packagePrice = item.packageBasePrice + decimalCents((storeIndex * 19) + (itemIndex * 7) + (captureIndex * 11))
        let normalizedPrice = item.normalizedBasePrice + decimalCents((storeIndex * 13) + (itemIndex * 5) + trendCents(for: captureIndex, storeIndex: storeIndex))

        return PriceEntry(
            capturedAt: capturedAt,
            itemNameRaw: item.name,
            itemNameNormalized: ItemKeyNormalizer.normalize(item.name),
            priceValue: packagePrice,
            unitType: item.unitType,
            unitQuantityValue: item.unitQuantity,
            normalizedUnitPriceValue: normalizedPrice,
            normalizedUnitType: item.normalizedUnitType,
            storeChainId: store.chainID,
            storeLocationId: store.locationID,
            storeChainNameSnapshot: store.chainName,
            storeLocationNameSnapshot: store.locationName,
            storeCoordinateLat: store.latitude,
            storeCoordinateLon: store.longitude,
            photoAssetId: "",
            ocrText: marker,
            confidence: 0.99,
            parserReviewStateRaw: "testSeed",
            parserReviewIssuesRaw: "Generated test record",
            parserUsedFoundationModel: false,
            parserAmbiguityNotesRaw: marker
        )
    }

    private static func decimalCents(_ cents: Int) -> Decimal {
        Decimal(cents) / Decimal(100)
    }

    private static func trendCents(for captureIndex: Int, storeIndex: Int) -> Int {
        guard captureIndex == 1 else {
            return 0
        }

        return storeIndex.isMultiple(of: 2) ? 18 : -12
    }

    private struct ItemSeed {
        let name: String
        let unitType: UnitType
        let unitQuantity: Decimal?
        let packageBasePrice: Decimal
        let normalizedBasePrice: Decimal
        let normalizedUnitType: UnitType
    }

    private struct StoreSeed {
        let chainID: UUID
        let locationID: UUID
        let chainName: String
        let locationName: String
        let latitude: Double
        let longitude: Double
    }

    private static let itemSeeds: [ItemSeed] = [
        ItemSeed(name: "Test Milk 2L", unitType: .each, unitQuantity: 1, packageBasePrice: 5.29, normalizedBasePrice: 2.65, normalizedUnitType: .liter),
        ItemSeed(name: "Test Bananas", unitType: .lb, unitQuantity: 1, packageBasePrice: 1.89, normalizedBasePrice: 1.89, normalizedUnitType: .lb),
        ItemSeed(name: "Test Eggs 12 Pack", unitType: .each, unitQuantity: 12, packageBasePrice: 4.79, normalizedBasePrice: 0.40, normalizedUnitType: .each),
        ItemSeed(name: "Test Cheddar 400g", unitType: .each, unitQuantity: 1, packageBasePrice: 6.99, normalizedBasePrice: 1.75, normalizedUnitType: .hundredGrams),
        ItemSeed(name: "Test Apples", unitType: .lb, unitQuantity: 1, packageBasePrice: 2.49, normalizedBasePrice: 2.49, normalizedUnitType: .lb),
        ItemSeed(name: "Test Yogurt 650g", unitType: .each, unitQuantity: 1, packageBasePrice: 4.49, normalizedBasePrice: 0.69, normalizedUnitType: .hundredGrams),
        ItemSeed(name: "Test Pasta 900g", unitType: .each, unitQuantity: 1, packageBasePrice: 3.29, normalizedBasePrice: 0.37, normalizedUnitType: .hundredGrams),
        ItemSeed(name: "Test Orange Juice 1.54L", unitType: .each, unitQuantity: 1, packageBasePrice: 5.99, normalizedBasePrice: 3.89, normalizedUnitType: .liter),
        ItemSeed(name: "Test Ground Beef", unitType: .lb, unitQuantity: 1, packageBasePrice: 6.49, normalizedBasePrice: 6.49, normalizedUnitType: .lb),
        ItemSeed(name: "Test Coffee 907g", unitType: .each, unitQuantity: 1, packageBasePrice: 14.99, normalizedBasePrice: 1.65, normalizedUnitType: .hundredGrams)
    ]

    private static let storeSeeds: [StoreSeed] = [
        StoreSeed(chainID: fixedUUID("10000000-0000-0000-0000-000000000001"), locationID: fixedUUID("20000000-0000-0000-0000-000000000001"), chainName: "Test Mart", locationName: "Test Mart Downtown", latitude: 51.0447, longitude: -114.0719),
        StoreSeed(chainID: fixedUUID("10000000-0000-0000-0000-000000000002"), locationID: fixedUUID("20000000-0000-0000-0000-000000000002"), chainName: "Seed Foods", locationName: "Seed Foods Beltline", latitude: 51.0374, longitude: -114.0780),
        StoreSeed(chainID: fixedUUID("10000000-0000-0000-0000-000000000003"), locationID: fixedUUID("20000000-0000-0000-0000-000000000003"), chainName: "Mock Grocery", locationName: "Mock Grocery West", latitude: 51.0475, longitude: -114.1400),
        StoreSeed(chainID: fixedUUID("10000000-0000-0000-0000-000000000004"), locationID: fixedUUID("20000000-0000-0000-0000-000000000004"), chainName: "Fixture Market", locationName: "Fixture Market North", latitude: 51.0890, longitude: -114.0620),
        StoreSeed(chainID: fixedUUID("10000000-0000-0000-0000-000000000005"), locationID: fixedUUID("20000000-0000-0000-0000-000000000005"), chainName: "Sample Save", locationName: "Sample Save South", latitude: 50.9850, longitude: -114.0740)
    ]

    private static func fixedUUID(_ value: String) -> UUID {
        UUID(uuidString: value) ?? UUID()
    }
}
#endif
