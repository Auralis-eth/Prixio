import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct WeeklyBriefEngineTests {
    /// Fixed "today" so week-window math is deterministic regardless of when tests run.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self, RestockRule.self,
                PriceEntry.self, FlyerPriceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func day(_ offset: Int) -> Date {
        let today = Calendar.current.startOfDay(for: now)
        return Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    /// A reviewed basket-only receipt `weeksAgo` full weeks back (0 = this week, now).
    private func spendReceipt(total: Decimal, weeksAgo: Int) -> ReceiptCapture {
        let date = weeksAgo == 0
            ? now
            : Calendar.current.date(byAdding: .weekOfYear, value: -weeksAgo, to: now)!
        return ReceiptCapture(
            capturedAt: date,
            purchaseDate: date,
            total: total,
            reviewState: .reviewed
        )
    }

    private func milkReceipt(daysAgo: Int) -> ReceiptCapture {
        ReceiptCapture(
            capturedAt: day(-daysAgo),
            purchaseDate: day(-daysAgo),
            reviewState: .reviewed,
            lineItems: [
                ReceiptLineItem(lineText: "Milk", itemNameRaw: "Milk", itemNameNormalized: "milk")
            ]
        )
    }

    private func entry(item: String, price: Decimal, daysAgo: Int) -> PriceEntry {
        PriceEntry(
            capturedAt: day(-daysAgo),
            itemNameRaw: item,
            itemNameNormalized: ItemKeyNormalizer.normalize(item),
            priceValue: price,
            unitType: .each,
            photoAssetId: "test"
        )
    }

    private func compose(
        entries: [PriceEntry] = [],
        receipts: [ReceiptCapture] = [],
        flyerRecords: [FlyerPriceRecord] = [],
        restockRules: [RestockRule] = [],
        listItemKeys: [String] = []
    ) throws -> HouseholdBrief {
        let context = try makeContext()
        entries.forEach(context.insert)
        receipts.forEach(context.insert)
        flyerRecords.forEach(context.insert)
        restockRules.forEach(context.insert)
        try context.save()
        return WeeklyBriefEngine.compose(
            entries: entries,
            receipts: receipts,
            flyerRecords: flyerRecords,
            restockRules: restockRules,
            listItemKeys: listItemKeys,
            now: now
        )
    }

    @Test
    func emptyInputsYieldAnEmptyBrief() throws {
        let brief = try compose()
        #expect(brief.isEmpty)
        #expect(brief.facts.isEmpty)
        #expect(brief.spendComparison == .insufficientData)
    }

    @Test
    func weeklySpendComparesAgainstTheTrailingMedian() throws {
        let receipts = [
            spendReceipt(total: 100, weeksAgo: 0),
            spendReceipt(total: 112, weeksAgo: 0),
            spendReceipt(total: 190, weeksAgo: 1),
            spendReceipt(total: 200, weeksAgo: 2),
            spendReceipt(total: 210, weeksAgo: 3),
            spendReceipt(total: 200, weeksAgo: 4)
        ]
        let brief = try compose(receipts: receipts)
        #expect(brief.receiptSpendThisWeek == 212)
        #expect(brief.receiptCountThisWeek == 2)
        #expect(brief.spendComparison == .nearUsual(usualWeekly: 200))
        // The spend fact plus the comparison fact.
        #expect(brief.facts.count == 2)
    }

    @Test
    func overspendingClassifiesAboveUsual() throws {
        let receipts = [
            spendReceipt(total: 300, weeksAgo: 0),
            spendReceipt(total: 200, weeksAgo: 1),
            spendReceipt(total: 200, weeksAgo: 2),
            spendReceipt(total: 200, weeksAgo: 3)
        ]
        let brief = try compose(receipts: receipts)
        #expect(brief.spendComparison == .aboveUsual(usualWeekly: 200))
    }

    @Test
    func tooFewPriorWeeksClaimsNoComparison() throws {
        let receipts = [
            spendReceipt(total: 300, weeksAgo: 0),
            spendReceipt(total: 200, weeksAgo: 1),
            spendReceipt(total: 200, weeksAgo: 2)
        ]
        let brief = try compose(receipts: receipts)
        #expect(brief.spendComparison == .insufficientData)
        // Spend fact only — no comparison sentence without a grounded baseline.
        #expect(brief.facts.count == 1)
    }

    @Test
    func priceAboveTheUsualBandThisWeekIsCalledOut() throws {
        let entries = [
            entry(item: "Eggs", price: Decimal(string: "4.40")!, daysAgo: 40),
            entry(item: "Eggs", price: Decimal(string: "4.50")!, daysAgo: 25),
            entry(item: "Eggs", price: Decimal(string: "4.60")!, daysAgo: 12),
            entry(item: "Eggs", price: Decimal(string: "6.99")!, daysAgo: 0)
        ]
        let brief = try compose(entries: entries)
        #expect(brief.unusualPrices.count == 1)
        #expect(brief.unusualPrices.first?.itemKey == "egg")
        #expect(brief.unusualPrices.first?.capturedPrice == Decimal(string: "6.99")!)
        #expect(brief.facts.count == 1)
    }

    @Test
    func usualPricesThisWeekStaySilent() throws {
        let entries = [
            entry(item: "Eggs", price: Decimal(string: "4.40")!, daysAgo: 40),
            entry(item: "Eggs", price: Decimal(string: "4.50")!, daysAgo: 25),
            entry(item: "Eggs", price: Decimal(string: "4.60")!, daysAgo: 12),
            entry(item: "Eggs", price: Decimal(string: "4.55")!, daysAgo: 0)
        ]
        let brief = try compose(entries: entries)
        #expect(brief.unusualPrices.isEmpty)
        #expect(brief.facts.isEmpty)
    }

    @Test
    func unusualPricePickIsIndependentOfInputOrder() throws {
        // Two above-band captures of the same item this week, hours apart: the
        // most recent one must be reported no matter how callers order the
        // array — the card's @Query and MainView's fetch are both unsorted, and
        // the two surfaces must compose the same brief.
        func weekEntry(price: Decimal, hoursIntoDay: Int) -> PriceEntry {
            PriceEntry(
                capturedAt: day(0).addingTimeInterval(TimeInterval(hoursIntoDay * 3600)),
                itemNameRaw: "Eggs",
                itemNameNormalized: ItemKeyNormalizer.normalize("Eggs"),
                priceValue: price,
                unitType: .each,
                photoAssetId: "test"
            )
        }
        let entries = [
            entry(item: "Eggs", price: Decimal(string: "4.40")!, daysAgo: 40),
            entry(item: "Eggs", price: Decimal(string: "4.50")!, daysAgo: 25),
            entry(item: "Eggs", price: Decimal(string: "4.60")!, daysAgo: 12),
            weekEntry(price: Decimal(string: "6.99")!, hoursIntoDay: 0),
            weekEntry(price: Decimal(string: "7.99")!, hoursIntoDay: 1)
        ]
        let forward = try compose(entries: entries)
        let backward = try compose(entries: Array(entries.reversed()))
        #expect(forward.unusualPrices.first?.capturedPrice == Decimal(string: "7.99")!)
        #expect(forward.fingerprint == backward.fingerprint)
    }

    @Test
    func dueRestockItemsAppearUnlessCoveredByTheList() throws {
        let receipts = [21, 14, 7].map(milkReceipt(daysAgo:))

        let brief = try compose(receipts: receipts)
        #expect(brief.restockSuggestions.map(\.cadence.itemKey) == ["milk"])
        #expect(brief.facts.contains { $0.contains("probably low") && $0.contains("Milk") })

        let withList = try compose(receipts: receipts, listItemKeys: ["milk"])
        #expect(withList.restockSuggestions.isEmpty)
        #expect(withList.facts.isEmpty)
    }

    @Test
    func fingerprintTracksTheFacts() throws {
        let receipts = [21, 14, 7].map(milkReceipt(daysAgo:))
        let first = try compose(receipts: receipts)
        let second = try compose(receipts: receipts)
        let different = try compose(receipts: receipts, listItemKeys: ["milk"])
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.fingerprint != different.fingerprint)
    }
}
