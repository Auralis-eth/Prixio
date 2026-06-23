import Foundation
import Testing
@testable import Prixio

struct PriceMemoryInsightTests {
    private func entry(
        name: String,
        price: String,
        unit: UnitType = .each,
        capturedDaysAgo: Int = 1,
        now: Date
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: unit,
            photoAssetId: ""
        )
    }

    @Test
    func returnsNilBelowMinimumObservations() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Organic Milk", price: "4.99", now: now),
            entry(name: "Organic Milk", price: "5.09", now: now)
        ]

        let insight = PriceInsightEngine.computePriceMemory(
            itemName: "Organic Milk",
            currentPrice: Decimal(string: "4.99")!,
            unitType: .each,
            allEntries: entries,
            now: now
        )

        #expect(insight == nil)
    }

    @Test
    func flagsPriceNearUsualWithinBand() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Organic Milk", price: "4.90", now: now),
            entry(name: "Organic Milk", price: "5.00", now: now),
            entry(name: "Organic Milk", price: "5.10", now: now)
        ]

        let insight = PriceInsightEngine.computePriceMemory(
            itemName: "organic milk",
            currentPrice: Decimal(string: "5.00")!,
            unitType: .each,
            allEntries: entries,
            now: now
        )

        #expect(insight?.level == .nearUsual)
        #expect(insight?.observationCount == 3)
    }

    @Test
    func flagsPriceBelowUsual() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Organic Milk", price: "5.00", now: now),
            entry(name: "Organic Milk", price: "5.00", now: now),
            entry(name: "Organic Milk", price: "5.00", now: now)
        ]

        let insight = PriceInsightEngine.computePriceMemory(
            itemName: "Organic Milk",
            currentPrice: Decimal(string: "3.99")!,
            unitType: .each,
            allEntries: entries,
            now: now
        )

        #expect(insight?.level == .belowUsual)
    }

    @Test
    func flagsPriceAboveUsual() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Organic Milk", price: "5.00", now: now),
            entry(name: "Organic Milk", price: "5.00", now: now),
            entry(name: "Organic Milk", price: "5.00", now: now)
        ]

        let insight = PriceInsightEngine.computePriceMemory(
            itemName: "Organic Milk",
            currentPrice: Decimal(string: "6.49")!,
            unitType: .each,
            allEntries: entries,
            now: now
        )

        #expect(insight?.level == .aboveUsual)
    }

    @Test
    func excludesEntriesWithDifferentUnit() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Bananas", price: "0.69", unit: .lb, now: now),
            entry(name: "Bananas", price: "0.71", unit: .lb, now: now),
            entry(name: "Bananas", price: "0.70", unit: .lb, now: now),
            entry(name: "Bananas", price: "1.99", unit: .each, now: now)
        ]

        // Only one `.each` observation exists, so an each-unit candidate has too little history.
        let insight = PriceInsightEngine.computePriceMemory(
            itemName: "Bananas",
            currentPrice: Decimal(string: "1.99")!,
            unitType: .each,
            allEntries: entries,
            now: now
        )

        #expect(insight == nil)
    }
}

struct StoreMemoryInsightTests {
    private func entry(
        name: String,
        price: String,
        chain: String,
        unit: UnitType = .each,
        capturedDaysAgo: Int = 1,
        now: Date
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: unit,
            storeChainNameSnapshot: chain,
            photoAssetId: ""
        )
    }

    private func milkAtTwoChains(now: Date) -> [PriceEntry] {
        [
            entry(name: "Milk", price: "5.00", chain: "Costco", now: now),
            entry(name: "Milk", price: "5.00", chain: "Costco", now: now),
            entry(name: "Milk", price: "4.00", chain: "Walmart", now: now),
            entry(name: "Milk", price: "4.00", chain: "Walmart", now: now)
        ]
    }

    @Test
    func flagsCheaperHereWhenStoreBeatsOthers() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let insight = PriceInsightEngine.computeStoreMemory(
            itemName: "Milk",
            currentStoreName: "Walmart",
            unitType: .each,
            allEntries: milkAtTwoChains(now: now),
            now: now
        )
        #expect(insight?.level == .cheaperHere)
        #expect(insight?.observationCount == 2)
        #expect(insight?.storeCount == 2)
    }

    @Test
    func flagsExpensiveHereWhenStoreIsPricier() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let insight = PriceInsightEngine.computeStoreMemory(
            itemName: "Milk",
            currentStoreName: "Costco",
            unitType: .each,
            allEntries: milkAtTwoChains(now: now),
            now: now
        )
        #expect(insight?.level == .expensiveHere)
    }

    @Test
    func returnsNilWithOnlyOneStore() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Milk", price: "5.00", chain: "Costco", now: now),
            entry(name: "Milk", price: "5.00", chain: "Costco", now: now),
            entry(name: "Milk", price: "5.00", chain: "Costco", now: now)
        ]
        let insight = PriceInsightEngine.computeStoreMemory(
            itemName: "Milk",
            currentStoreName: "Costco",
            unitType: .each,
            allEntries: entries,
            now: now
        )
        #expect(insight == nil)
    }

    @Test
    func returnsNilWhenCurrentStoreHasNoHistoryForItem() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let insight = PriceInsightEngine.computeStoreMemory(
            itemName: "Milk",
            currentStoreName: "Loblaws", // never seen for milk
            unitType: .each,
            allEntries: milkAtTwoChains(now: now),
            now: now
        )
        #expect(insight == nil)
    }
}
