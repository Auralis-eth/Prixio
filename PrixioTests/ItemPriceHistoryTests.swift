import Foundation
import Testing
@testable import Prixio

struct ItemPriceHistoryTests {
    private func entry(
        name: String,
        price: String,
        unit: UnitType = .each,
        normalizedPrice: String? = nil,
        normalizedUnit: UnitType? = nil,
        capturedDaysAgo: Int,
        now: Date
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: unit,
            normalizedUnitPriceValue: normalizedPrice.map { Decimal(string: $0)! },
            normalizedUnitType: normalizedUnit,
            photoAssetId: ""
        )
    }

    @Test
    func returnsNilWhenNoEntries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let history = PriceInsightEngine.computeItemHistory(
            itemKey: "Organic Milk",
            displayName: "Organic Milk",
            useNormalizedPricing: false,
            allEntries: [],
            now: now
        )
        #expect(history == nil)
    }

    @Test
    func computesLatestLowestHighestAndUsualBand() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Organic Milk", price: "5.00", capturedDaysAgo: 30, now: now),
            entry(name: "Organic Milk", price: "4.00", capturedDaysAgo: 20, now: now),
            entry(name: "Organic Milk", price: "6.00", capturedDaysAgo: 10, now: now),
            entry(name: "Organic Milk", price: "5.00", capturedDaysAgo: 1, now: now)
        ]

        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Organic Milk",
            displayName: "Organic Milk",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        #expect(history.observationCount == 4)
        #expect(history.latest.price == Decimal(string: "5.00"))
        #expect(history.lowest.price == Decimal(string: "4.00"))
        #expect(history.highest.price == Decimal(string: "6.00"))
        #expect(history.hasUsualBand)
        // Median of [4,5,5,6] = 5.00; band ±10% -> 4.50...5.50
        #expect(history.median == Decimal(string: "5.00"))
        #expect(history.usualLow == Decimal(string: "4.50"))
        #expect(history.usualHigh == Decimal(string: "5.50"))
        // Timeline is oldest-first.
        #expect(history.timeline.first?.date ?? now < (history.timeline.last?.date ?? now))
    }

    @Test
    func suppressesUsualBandBelowMinimumObservations() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Eggs", price: "3.00", capturedDaysAgo: 5, now: now),
            entry(name: "Eggs", price: "3.50", capturedDaysAgo: 1, now: now)
        ]

        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Eggs",
            displayName: "Eggs",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        #expect(history.hasUsualBand == false)
        #expect(history.anomaly == .insufficientData)
    }

    @Test
    func flagsLikelySaleWhenLatestFarBelowMedian() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Cheese", price: "10.00", capturedDaysAgo: 30, now: now),
            entry(name: "Cheese", price: "10.00", capturedDaysAgo: 20, now: now),
            entry(name: "Cheese", price: "10.00", capturedDaysAgo: 10, now: now),
            entry(name: "Cheese", price: "7.50", capturedDaysAgo: 1, now: now)
        ]

        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Cheese",
            displayName: "Cheese",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        // 7.50 is 25% below median 10.00 (beyond the 2× band) -> likely sale.
        #expect(history.anomaly == .likelySale)
    }

    @Test
    func flagsUnusuallyHighWhenLatestFarAboveMedian() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Coffee", price: "10.00", capturedDaysAgo: 30, now: now),
            entry(name: "Coffee", price: "10.00", capturedDaysAgo: 20, now: now),
            entry(name: "Coffee", price: "10.00", capturedDaysAgo: 10, now: now),
            entry(name: "Coffee", price: "13.00", capturedDaysAgo: 1, now: now)
        ]

        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Coffee",
            displayName: "Coffee",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        // 13.00 is 30% above median 10.00 (beyond the 2× band) -> unusually high.
        #expect(history.anomaly == .unusuallyHigh)
    }

    @Test
    func nearUsualWhenLatestWithinBand() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Bread", price: "3.00", capturedDaysAgo: 30, now: now),
            entry(name: "Bread", price: "3.00", capturedDaysAgo: 20, now: now),
            entry(name: "Bread", price: "3.00", capturedDaysAgo: 10, now: now),
            entry(name: "Bread", price: "3.05", capturedDaysAgo: 1, now: now)
        ]

        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Bread",
            displayName: "Bread",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        #expect(history.anomaly == .nearUsual)
    }

    @Test
    func normalizedModeUsesOnlyEntriesWithNormalizedPrice() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Apples", price: "2.20", unit: .lb, normalizedPrice: "4.85", normalizedUnit: .kg, capturedDaysAgo: 10, now: now),
            entry(name: "Apples", price: "2.30", unit: .lb, normalizedPrice: "5.07", normalizedUnit: .kg, capturedDaysAgo: 5, now: now),
            entry(name: "Apples", price: "1.99", unit: .each, capturedDaysAgo: 1, now: now) // no normalized price
        ]

        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Apples",
            displayName: "Apples",
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        ))

        // Only the two entries with a normalized unit price are considered.
        #expect(history.observationCount == 2)
        #expect(history.latest.price == Decimal(string: "5.07"))
        #expect(history.latest.unitType == .kg)
    }

    @Test
    func normalizedModeKeepsOnlyTheDominantUnitFamily() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Three $/kg observations plus a single stray $/each normalized price. The per-unit history
        // must not blend incompatible families — otherwise the $/each value would corrupt the
        // lowest/median and could fire a false anomaly. The dominant family ($/kg) wins.
        let entries = [
            entry(name: "Apples", price: "2.20", unit: .lb, normalizedPrice: "4.85", normalizedUnit: .kg, capturedDaysAgo: 30, now: now),
            entry(name: "Apples", price: "2.30", unit: .lb, normalizedPrice: "5.00", normalizedUnit: .kg, capturedDaysAgo: 20, now: now),
            entry(name: "Apples", price: "2.25", unit: .lb, normalizedPrice: "4.95", normalizedUnit: .kg, capturedDaysAgo: 10, now: now),
            entry(name: "Apples", price: "0.50", unit: .each, normalizedPrice: "0.50", normalizedUnit: .each, capturedDaysAgo: 1, now: now)
        ]

        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Apples",
            displayName: "Apples",
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        ))

        // The stray $/each (0.50) is excluded: only the three $/kg entries are summarized.
        #expect(history.observationCount == 3)
        #expect(history.lowest.price == Decimal(string: "4.85"))
        #expect(history.highest.price == Decimal(string: "5.00"))
        #expect(history.latest.unitType == .kg)
    }

    private func storeEntry(
        name: String,
        price: String,
        chain: String,
        capturedDaysAgo: Int,
        now: Date
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: .each,
            storeChainNameSnapshot: chain,
            photoAssetId: ""
        )
    }

    @Test
    func chainScopeSummarizesOnlyThatChainsObservations() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            storeEntry(name: "Milk", price: "5.00", chain: "Costco", capturedDaysAgo: 30, now: now),
            storeEntry(name: "Milk", price: "5.00", chain: "Costco", capturedDaysAgo: 20, now: now),
            storeEntry(name: "Milk", price: "5.00", chain: "Costco", capturedDaysAgo: 10, now: now),
            storeEntry(name: "Milk", price: "3.00", chain: "Walmart", capturedDaysAgo: 5, now: now),
            storeEntry(name: "Milk", price: "3.00", chain: "Walmart", capturedDaysAgo: 1, now: now)
        ]

        // Scoped to Costco: only its three $5 observations are summarized, not the cheaper Walmart ones.
        let costco = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Milk",
            displayName: "Milk",
            useNormalizedPricing: false,
            allEntries: entries,
            scope: .chain(name: "Costco"),
            now: now
        ))
        #expect(costco.scope == .chain(name: "Costco"))
        #expect(costco.observationCount == 3)
        #expect(costco.median == Decimal(string: "5.00"))

        // The all-stores view blends both chains, so its median sits between them.
        let all = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Milk",
            displayName: "Milk",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))
        #expect(all.observationCount == 5)
        #expect(all.median == Decimal(string: "5.00")) // median of [3,3,5,5,5]
    }

    @Test
    func availableScopesLeadsWithAllStoresThenChains() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            storeEntry(name: "Milk", price: "5.00", chain: "Costco", capturedDaysAgo: 10, now: now),
            storeEntry(name: "Milk", price: "5.00", chain: "Costco", capturedDaysAgo: 5, now: now),
            storeEntry(name: "Milk", price: "3.00", chain: "Walmart", capturedDaysAgo: 1, now: now)
        ]

        let scopes = PriceInsightEngine.availableStoreScopes(itemKey: "Milk", allEntries: entries)
        // All-stores first, then chains ranked by observation count (Costco has 2, Walmart 1).
        #expect(scopes == [.allStores, .chain(name: "Costco"), .chain(name: "Walmart")])
    }

    @Test
    func genericQueryRollsUpSpecificProductsInHistory() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Daisy Sour Cream", price: "3.00", capturedDaysAgo: 30, now: now),
            entry(name: "Daisy Sour Cream", price: "3.50", capturedDaysAgo: 20, now: now),
            entry(name: "Compliments Sour Cream", price: "2.50", capturedDaysAgo: 10, now: now)
        ]

        // A shopper's generic "Sour Cream" rolls up the specific scanned products that satisfy it.
        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Sour Cream",
            displayName: "Sour Cream",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))
        #expect(history.observationCount == 3)
        #expect(history.lowest.price == Decimal(string: "2.50"))
        #expect(history.highest.price == Decimal(string: "3.50"))
    }

    @Test
    func bestStoreForGenericQueryUsesCheapestSpecificProduct() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            storeEntry(name: "Daisy Sour Cream", price: "3.50", chain: "Walmart", capturedDaysAgo: 5, now: now),
            storeEntry(name: "Compliments Sour Cream", price: "2.50", chain: "Sobeys", capturedDaysAgo: 3, now: now)
        ]

        let suggestion = try #require(PriceInsightEngine.computeBestStoreForItem(
            itemKey: "sour cream",
            allEntries: entries,
            now: now
        ))
        #expect(suggestion.storeChainName == "Sobeys")
        #expect(suggestion.packagePrice == Decimal(string: "2.50"))
    }

    @Test
    func availableScopesIsAllStoresOnlyForASingleStore() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            storeEntry(name: "Milk", price: "5.00", chain: "Costco", capturedDaysAgo: 10, now: now),
            storeEntry(name: "Milk", price: "4.00", chain: "Costco", capturedDaysAgo: 1, now: now)
        ]

        // One store offers no useful breakdown beyond the all-stores view.
        #expect(PriceInsightEngine.availableStoreScopes(itemKey: "Milk", allEntries: entries) == [.allStores])
    }
}
