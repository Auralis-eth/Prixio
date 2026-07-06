import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct BuyAheadAdvisorTests {
    /// Fixed "today" so window math is deterministic regardless of when tests run.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func day(_ offset: Int) -> Date {
        let today = Calendar.current.startOfDay(for: now)
        return Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    private func cadence(
        itemKey: String = "laundry detergent",
        runOutInDays: Int
    ) -> ConsumptionCadenceEngine.ItemCadence {
        ConsumptionCadenceEngine.ItemCadence(
            itemKey: itemKey,
            displayName: itemKey,
            purchaseEventCount: 5,
            medianIntervalDays: 30,
            intervalSpreadDays: 0,
            lastPurchasedAt: day(runOutInDays - 30),
            predictedRunOutDate: day(runOutInDays),
            confidence: .high
        )
    }

    private func record(
        itemKey: String = "laundry detergent",
        price: Decimal,
        saleEndInDays: Int
    ) -> FlyerPriceRecord {
        FlyerPriceRecord(
            dealKey: "rcss|\(itemKey)|\(price)",
            bannerID: "rcss",
            bannerName: "Real Canadian Superstore",
            productName: itemKey,
            normalizedItemKey: itemKey,
            priceValue: price,
            priceKindRaw: "sale",
            saleStartDate: day(-2),
            saleEndDate: day(saleEndInDays),
            confidence: 0.9,
            sourceText: "\(itemKey) \(price)"
        )
    }

    /// Enough captured history for a usual band: median package price 12.99.
    private func baselineEntries(itemKey: String = "laundry detergent") -> [PriceEntry] {
        [Decimal(string: "12.49")!, Decimal(string: "12.99")!, Decimal(string: "13.49")!]
            .enumerated()
            .map { index, price in
                PriceEntry(
                    capturedAt: day(-(10 + index * 20)),
                    itemNameRaw: itemKey,
                    itemNameNormalized: itemKey,
                    priceValue: price,
                    unitType: .each,
                    photoAssetId: "test"
                )
            }
    }

    @Test
    func advisorySurfacesWhenSaleEndsBeforeRunOut() {
        let advisories = BuyAheadAdvisor.compute(
            cadences: [cadence(runOutInDays: 10)],
            records: [record(price: Decimal(string: "9.99")!, saleEndInDays: 5)],
            entries: baselineEntries(),
            now: now
        )
        #expect(advisories.count == 1)
        #expect(advisories.first?.bannerName == "Real Canadian Superstore")
        #expect(advisories.first?.anomaly == .likelySale)
        #expect(advisories.first?.saleEndDate == day(5))
    }

    @Test
    func noAdvisoryWhenSaleOutlastsTheRunOut() {
        // The deal is still on when the household would naturally shop — no need
        // to buy early.
        let advisories = BuyAheadAdvisor.compute(
            cadences: [cadence(runOutInDays: 10)],
            records: [record(price: Decimal(string: "9.99")!, saleEndInDays: 12)],
            entries: baselineEntries(),
            now: now
        )
        #expect(advisories.isEmpty)
    }

    @Test
    func noAdvisoryWithoutACapturedBaseline() {
        // No price history means no honest "below usual" claim.
        let advisories = BuyAheadAdvisor.compute(
            cadences: [cadence(runOutInDays: 10)],
            records: [record(price: Decimal(string: "9.99")!, saleEndInDays: 5)],
            entries: [],
            now: now
        )
        #expect(advisories.isEmpty)
    }

    @Test
    func noAdvisoryWhenTheDealPriceIsMerelyUsual() {
        let advisories = BuyAheadAdvisor.compute(
            cadences: [cadence(runOutInDays: 10)],
            records: [record(price: Decimal(string: "12.99")!, saleEndInDays: 5)],
            entries: baselineEntries(),
            now: now
        )
        #expect(advisories.isEmpty)
    }

    @Test
    func needsOutsideThePlanningWindowAreIgnored() {
        // Due within the due-soon window: the restock section's job.
        let imminent = BuyAheadAdvisor.compute(
            cadences: [cadence(runOutInDays: 2)],
            records: [record(price: Decimal(string: "9.99")!, saleEndInDays: 1)],
            entries: baselineEntries(),
            now: now
        )
        #expect(imminent.isEmpty)

        // Too far out to plan for.
        let distant = BuyAheadAdvisor.compute(
            cadences: [cadence(runOutInDays: 20)],
            records: [record(price: Decimal(string: "9.99")!, saleEndInDays: 5)],
            entries: baselineEntries(),
            now: now
        )
        #expect(distant.isEmpty)
    }

    @Test
    func dismissedRuleSuppressesTheAdvisory() {
        let rule = RestockRule(
            itemKey: "laundry detergent",
            displayName: "Laundry Detergent",
            status: .dismissed
        )
        let advisories = BuyAheadAdvisor.compute(
            cadences: [cadence(runOutInDays: 10)],
            records: [record(price: Decimal(string: "9.99")!, saleEndInDays: 5)],
            entries: baselineEntries(),
            rules: [rule],
            now: now
        )
        #expect(advisories.isEmpty)
    }

    @Test
    func viewModelSuppressesAdvisoriesForItemsAlreadyOnTheList() throws {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self, ShoppingListItem.self,
                PriceEntry.self, FlyerPriceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // Purchases every 10 days, last bought 3 days ago → run-out in ~7 days.
        let receipts = [23, 13, 3].map { daysAgo in
            ReceiptCapture(
                capturedAt: day(-daysAgo),
                purchaseDate: day(-daysAgo),
                reviewState: .reviewed,
                lineItems: [
                    ReceiptLineItem(
                        lineText: "Laundry Detergent",
                        itemNameRaw: "Laundry Detergent",
                        itemNameNormalized: "laundry detergent"
                    )
                ]
            )
        }
        receipts.forEach(context.insert)
        let entries = baselineEntries()
        entries.forEach(context.insert)
        let deal = record(price: Decimal(string: "9.99")!, saleEndInDays: 4)
        context.insert(deal)
        try context.save()

        let viewModel = ShoppingListViewModel()
        viewModel.recompute(
            items: [],
            entries: entries,
            flyerRecords: [deal],
            receipts: receipts,
            userLocation: nil,
            now: now
        )
        #expect(viewModel.buyAheadAdvisories.map(\.itemKey) == ["laundry detergent"])

        // The same item on the list moves it to the flyer advisory's jurisdiction.
        let listItem = ShoppingListItem(itemKey: "laundry detergent", displayName: "Laundry Detergent")
        context.insert(listItem)
        try context.save()
        viewModel.recompute(
            items: [listItem],
            entries: entries,
            flyerRecords: [deal],
            receipts: receipts,
            userLocation: nil,
            now: now
        )
        #expect(viewModel.buyAheadAdvisories.isEmpty)
    }
}
