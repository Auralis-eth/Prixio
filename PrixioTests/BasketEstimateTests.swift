import Foundation
import Testing
@testable import Prixio

struct BasketEstimateTests {
    private let costco = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!
    private let walmart = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let loblaws = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    private func entry(
        name: String,
        price: String,
        chainID: UUID,
        chainName: String,
        capturedDaysAgo: Int = 1,
        now: Date
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: .each,
            storeChainId: chainID,
            storeChainNameSnapshot: chainName,
            photoAssetId: ""
        )
    }

    private func basketItems(_ names: String...) -> [BasketItemInput] {
        names.map { BasketItemInput(itemKey: ItemKeyNormalizer.normalize($0), displayName: $0) }
    }

    private func noChainEntry(
        name: String,
        price: String,
        locationID: UUID,
        storeName: String,
        now: Date
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: .each,
            storeLocationId: locationID,
            storeLocationNameSnapshot: storeName,
            photoAssetId: ""
        )
    }

    @Test
    func keepsDistinctNoChainStoresWithTheSameNameSeparate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let locA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let locB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        // Two physically different stores with no chain id that happen to share a name. They must
        // not be merged into a single store by the basket builder.
        let entries = [
            noChainEntry(name: "Milk", price: "4.00", locationID: locA, storeName: "Corner Market", now: now),
            noChainEntry(name: "Milk", price: "5.00", locationID: locB, storeName: "Corner Market", now: now)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.perStore.count == 2)
        // The cheaper of the two same-named stores wins, with its own (non-merged) total.
        #expect(estimate.cheapestSingleStore?.knownTotal == Decimal(string: "4.00"))
    }

    @Test
    func estimatesPerStoreTotalsAndPicksCheapestSingleStore() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Milk", price: "5.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Milk", price: "4.50", chainID: walmart, chainName: "Walmart", now: now),
            entry(name: "Eggs", price: "3.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Eggs", price: "3.20", chainID: walmart, chainName: "Walmart", now: now)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.pricedItemCount == 2)
        #expect(estimate.totalItemCount == 2)
        #expect(estimate.perStore.count == 2)
        // Walmart total 7.70 < Costco 8.00, both cover all -> Walmart is the cheapest single store.
        #expect(estimate.cheapestSingleStore?.storeName == "Walmart")
        #expect(estimate.cheapestSingleStore?.knownTotal == Decimal(string: "7.70"))
        #expect(estimate.perStore.first?.storeName == "Walmart")
        // Tiny per-item savings (0.20) -> no split suggested.
        #expect(estimate.split == nil)
    }

    @Test
    func reportsMissingAndUnpricedItemsWithoutTreatingThemAsZero() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Milk", price: "5.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Milk", price: "4.50", chainID: walmart, chainName: "Walmart", now: now),
            entry(name: "Eggs", price: "3.00", chainID: costco, chainName: "Costco", now: now)
            // Bread has no price anywhere.
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs", "Bread"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.totalItemCount == 3)
        #expect(estimate.pricedItemCount == 2)
        #expect(estimate.unpricedItemNames == ["Bread"])

        let walmart = estimate.perStore.first { $0.storeName == "Walmart" }
        #expect(walmart?.knownItemCount == 1)
        #expect(walmart?.missingItems == ["Eggs"])
        #expect(walmart?.coversAllPricedItems == false)

        // Only Costco covers every priced item.
        #expect(estimate.cheapestSingleStore?.storeName == "Costco")
        #expect(estimate.cheapestSingleStore?.coversAllPricedItems == true)
    }

    @Test
    func suggestsSplitOnlyWhenSavingsClearThresholds() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Milk", price: "10.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Milk", price: "4.00", chainID: walmart, chainName: "Walmart", now: now),
            entry(name: "Eggs", price: "4.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Eggs", price: "9.00", chainID: walmart, chainName: "Walmart", now: now)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        // One-stop cheapest is Walmart at 13.00; split buys Milk@Walmart(4) + Eggs@Costco(4) = 8.00.
        let split = try #require(estimate.split)
        #expect(split.combinedTotal == Decimal(string: "8.00"))
        #expect(split.savingsVsSingle == Decimal(string: "5.00"))
        #expect(split.stores.count == 2)
    }

    @Test
    func suggestsSplitWithoutSavingsWhenNoStoreCoversEverything() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Milk only at Walmart, Eggs only at Costco — no single store covers the whole basket.
        let entries = [
            entry(name: "Milk", price: "4.00", chainID: walmart, chainName: "Walmart", now: now),
            entry(name: "Eggs", price: "3.00", chainID: costco, chainName: "Costco", now: now)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        // No one-stop baseline exists, so the split is the only complete plan and carries no savings.
        let split = try #require(estimate.split)
        #expect(split.combinedTotal == Decimal(string: "7.00"))
        #expect(split.savingsVsSingle == nil)
        #expect(split.stores.count == 2)
        // No single store covers both priced items.
        #expect(estimate.perStore.allSatisfy { !$0.coversAllPricedItems })
    }

    @Test
    func picksCheapestStoreThatCoversEverything() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Milk", price: "5.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Milk", price: "4.00", chainID: walmart, chainName: "Walmart", now: now),
            entry(name: "Milk", price: "4.00", chainID: loblaws, chainName: "Loblaws", now: now),
            entry(name: "Eggs", price: "3.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Eggs", price: "3.00", chainID: walmart, chainName: "Walmart", now: now)
            // Loblaws is missing Eggs, so it cannot be the single-store winner.
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        // Walmart (7.00) beats Costco (8.00) among stores covering all items; Loblaws is excluded.
        #expect(estimate.cheapestSingleStore?.storeName == "Walmart")
        #expect(estimate.cheapestSingleStore?.knownTotal == Decimal(string: "7.00"))
    }

    @Test
    func suggestsCheaperSimilarItemAsSubstitution() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Almond Milk", price: "5.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Soy Milk", price: "3.00", chainID: walmart, chainName: "Walmart", now: now)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Almond Milk"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        let sub = try #require(estimate.substitutions.first)
        #expect(sub.substituteItemName == "Soy Milk")
        #expect(sub.substitutePrice == Decimal(string: "3.00"))
        #expect(sub.savings == Decimal(string: "2.00"))
        #expect(sub.substituteStoreName == "Walmart")
    }

    @Test
    func doesNotSuggestSubstitutionForUnrelatedOrInsufficientSavings() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            // Different head noun -> not a substitute even though cheaper.
            entry(name: "Almond Milk", price: "5.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "White Bread", price: "1.00", chainID: walmart, chainName: "Walmart", now: now),
            // Similar item, but only ~10% cheaper -> below the savings floor.
            entry(name: "Soy Milk", price: "4.60", chainID: walmart, chainName: "Walmart", now: now)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Almond Milk"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.substitutions.isEmpty)
    }

    @Test
    func returnsEmptyWhenNoPricesExist() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs"),
            useNormalizedPricing: false,
            allEntries: [],
            now: now
        )

        #expect(estimate.hasAnyPrices == false)
        #expect(estimate.cheapestSingleStore == nil)
        #expect(estimate.split == nil)
        #expect(estimate.unpricedItemNames.count == 2)
    }

    private func geoEntry(
        name: String,
        price: String,
        chainID: UUID,
        chainName: String,
        lat: Double,
        lon: Double,
        now: Date
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: .each,
            storeChainId: chainID,
            storeChainNameSnapshot: chainName,
            storeCoordinateLat: lat,
            storeCoordinateLon: lon,
            photoAssetId: ""
        )
    }

    @Test
    func doesNotSuggestThreeStoreSplitForLooseChange() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Costco covers everything at 14.00. The split (Milk@Walmart 3.50 + Eggs@Loblaws 4.00 +
        // Bread@Costco 4.00 = 11.50) saves 2.50 — which would clear the flat $2 floor, but spans
        // three stores. The per-extra-stop convenience penalty (2 extra stops × $1.50 = $3) makes a
        // 2.50 saving not worth the running around, so no split is suggested.
        let entries = [
            entry(name: "Milk", price: "5.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Eggs", price: "5.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Bread", price: "4.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Milk", price: "3.50", chainID: walmart, chainName: "Walmart", now: now),
            entry(name: "Eggs", price: "4.00", chainID: loblaws, chainName: "Loblaws", now: now)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs", "Bread"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.cheapestSingleStore?.storeName == "Costco")
        #expect(estimate.split == nil)
    }

    @Test
    func distantSplitMustClearAHigherSavingsBar() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Cheapest one-stop is Walmart at 8.00 (Milk 2.00 + Eggs 6.00). The split buys Milk@Walmart
        // (2.00) + Eggs@Costco (3.50) = 5.50, saving 2.50. With the two stores ~110 km apart, the
        // distance penalty pushes the required saving well past 2.50, so no split is suggested.
        let farEntries = [
            geoEntry(name: "Milk", price: "5.00", chainID: costco, chainName: "Costco", lat: 49.0, lon: -123.0, now: now),
            geoEntry(name: "Eggs", price: "3.50", chainID: costco, chainName: "Costco", lat: 49.0, lon: -123.0, now: now),
            geoEntry(name: "Milk", price: "2.00", chainID: walmart, chainName: "Walmart", lat: 49.0, lon: -124.5, now: now),
            geoEntry(name: "Eggs", price: "6.00", chainID: walmart, chainName: "Walmart", lat: 49.0, lon: -124.5, now: now)
        ]

        let farEstimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs"),
            useNormalizedPricing: false,
            allEntries: farEntries,
            now: now
        )
        #expect(farEstimate.split == nil)

        // The same prices with no coordinates carry no distance penalty, so the 2.50 saving (a
        // two-store, one-extra-stop trip) clears the floor and the split is suggested.
        let nearEntries = [
            entry(name: "Milk", price: "5.00", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Eggs", price: "3.50", chainID: costco, chainName: "Costco", now: now),
            entry(name: "Milk", price: "2.00", chainID: walmart, chainName: "Walmart", now: now),
            entry(name: "Eggs", price: "6.00", chainID: walmart, chainName: "Walmart", now: now)
        ]

        let nearEstimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Milk", "Eggs"),
            useNormalizedPricing: false,
            allEntries: nearEntries,
            now: now
        )
        let split = try #require(nearEstimate.split)
        #expect(split.savingsVsSingle == Decimal(string: "2.50"))
    }
}
