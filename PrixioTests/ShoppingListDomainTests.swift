import Foundation
import SwiftData
import Testing
@testable import Prixio

@MainActor
struct ShoppingListDomainTests {
    @Test
    func itemKeyNormalizerMatchesRepositoryPersistence() throws {
        let container = try ModelContainer(
            for: PriceEntry.self,
                StoreChain.self,
                StoreLocation.self,
                ShoppingList.self,
                ShoppingListItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let repository = PriceEntryRepository(context: context)

        var draft = PriceEntryDraft()
        draft.itemName = "  Yellow Onions  "
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Co-op"
        draft.storeChainExplicitlySelected = true

        try repository.saveEntry(from: draft)

        let entry = try #require(context.fetch(FetchDescriptor<PriceEntry>()).first)
        #expect(entry.itemNameNormalized == ItemKeyNormalizer.normalize(draft.itemName))
        #expect(entry.itemNameNormalized == "yellow onions")
    }

    @Test
    func stalenessThresholdsMapToExpectedBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(
            PriceInsightEngine.stalenessBucket(
                for: now.addingTimeInterval(-2 * 86_400),
                now: now
            ) == .fresh
        )
        #expect(
            PriceInsightEngine.stalenessBucket(
                for: now.addingTimeInterval(-12 * 86_400),
                now: now
            ) == .aging
        )
        #expect(
            PriceInsightEngine.stalenessBucket(
                for: now.addingTimeInterval(-45 * 86_400),
                now: now
            ) == .stale
        )
        #expect(
            PriceInsightEngine.stalenessBucket(
                for: now.addingTimeInterval(-120 * 86_400),
                now: now
            ) == .veryStale
        )
    }

    @Test
    func bestStoreSelectionPrefersNormalizedPricingWhenAvailable() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let entries = [
            makeEntry(
                itemName: "Milk",
                normalizedName: "milk",
                price: "5.49",
                normalizedPrice: "5.49",
                normalizedUnitType: .liter,
                chainName: "Store A",
                capturedAt: now.addingTimeInterval(-2 * 86_400)
            ),
            makeEntry(
                itemName: "Milk",
                normalizedName: "milk",
                price: "4.99",
                normalizedPrice: "4.99",
                normalizedUnitType: .liter,
                chainName: "Store B",
                capturedAt: now.addingTimeInterval(-4 * 86_400)
            )
        ]

        let suggestion = PriceInsightEngine.computeBestStoreForItem(
            itemKey: "milk",
            allEntries: entries,
            now: now
        )

        #expect(suggestion?.storeChainName == "Store B")
        #expect(suggestion?.usedNormalizedPricing == true)
        #expect(suggestion?.comparablePrice == Decimal(string: "4.99"))
        #expect(suggestion?.comparableUnitType == .liter)
    }

    @Test
    func packageModeFallbackWorksWhenNormalizedPricingIsAbsent() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let entries = [
            makeEntry(
                itemName: "Chips",
                normalizedName: "chips",
                price: "3.99",
                chainName: "Store A",
                capturedAt: now.addingTimeInterval(-2 * 86_400)
            ),
            makeEntry(
                itemName: "Chips",
                normalizedName: "chips",
                price: "2.99",
                chainName: "Store B",
                capturedAt: now.addingTimeInterval(-1 * 86_400)
            )
        ]

        let suggestion = PriceInsightEngine.computeBestStoreForItem(
            itemKey: "chips",
            allEntries: entries,
            now: now
        )

        #expect(suggestion?.storeChainName == "Store B")
        #expect(suggestion?.usedNormalizedPricing == false)
        #expect(suggestion?.comparablePrice == Decimal(string: "2.99"))
        #expect(suggestion?.comparableUnitType == .each)
    }

    @Test
    func recentEntriesBeatOlderEntriesWhenRecentComparableDataExists() {
        let now = Date(timeIntervalSince1970: 4_000_000)
        let entries = [
            makeEntry(
                itemName: "Butter",
                normalizedName: "butter",
                price: "1.99",
                normalizedPrice: "1.99",
                normalizedUnitType: .each,
                chainName: "Very Old Cheap Store",
                capturedAt: now.addingTimeInterval(-45 * 86_400)
            ),
            makeEntry(
                itemName: "Butter",
                normalizedName: "butter",
                price: "3.49",
                normalizedPrice: "3.49",
                normalizedUnitType: .each,
                chainName: "Recent Store",
                capturedAt: now.addingTimeInterval(-4 * 86_400)
            )
        ]

        let suggestion = PriceInsightEngine.computeBestStoreForItem(
            itemKey: "butter",
            allEntries: entries,
            now: now
        )

        #expect(suggestion?.storeChainName == "Recent Store")
        #expect(suggestion?.stalenessBucket == .fresh)
    }

    @Test
    func recencyBreaksPriceTies() {
        let now = Date(timeIntervalSince1970: 5_000_000)
        let entries = [
            makeEntry(
                itemName: "Eggs",
                normalizedName: "eggs",
                price: "4.29",
                normalizedPrice: "4.29",
                normalizedUnitType: .each,
                chainName: "Older Store",
                capturedAt: now.addingTimeInterval(-6 * 86_400)
            ),
            makeEntry(
                itemName: "Eggs",
                normalizedName: "eggs",
                price: "4.29",
                normalizedPrice: "4.29",
                normalizedUnitType: .each,
                chainName: "Newer Store",
                capturedAt: now.addingTimeInterval(-2 * 86_400)
            )
        ]

        let suggestion = PriceInsightEngine.computeBestStoreForItem(
            itemKey: "eggs",
            allEntries: entries,
            now: now
        )

        #expect(suggestion?.storeChainName == "Newer Store")
    }

    @Test
    func missingEntriesReturnNilSuggestion() {
        let suggestion = PriceInsightEngine.computeBestStoreForItem(
            itemKey: "bread",
            allEntries: []
        )

        #expect(suggestion == nil)
    }

    private func makeEntry(
        itemName: String,
        normalizedName: String,
        price: String,
        normalizedPrice: String? = nil,
        normalizedUnitType: UnitType? = nil,
        chainName: String,
        capturedAt: Date
    ) -> PriceEntry {
        PriceEntry(
            capturedAt: capturedAt,
            itemNameRaw: itemName,
            itemNameNormalized: normalizedName,
            priceValue: Decimal(string: price)!,
            unitType: .each,
            unitQuantityValue: nil,
            normalizedUnitPriceValue: normalizedPrice.flatMap { Decimal(string: $0) },
            normalizedUnitType: normalizedUnitType,
            storeChainId: UUID(),
            storeLocationId: nil,
            storeChainNameSnapshot: chainName,
            storeLocationNameSnapshot: nil,
            photoAssetId: ""
        )
    }
}
