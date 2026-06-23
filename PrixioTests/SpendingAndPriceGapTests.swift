//
//  SpendingAndPriceGapTests.swift
//  PrixioTests
//
//  Fills specific untested branches surfaced during the ship-readiness review: the spend-trend
//  zero-month guard, the store-share grand-total guard and "Unknown" fallback, the exact
//  budget-pressure boundary ratios (0.7 and 1.0, which the existing tests step over), and the
//  even-count price median where the two middle observations differ.
//

import Foundation
import Testing
@testable import Prixio

struct SpendingGapTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(monthsAgo: Int, day: Int = 14) -> Date {
        let calendar = Calendar.current
        let monthStart = MonthBucket.start(of: calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now)
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
    }

    private func summary(income: String, spending: String) -> MonthlySummary {
        MonthlySummary(
            month: MonthBucket.start(of: now),
            categoryTotals: [.other: Decimal(string: spending)!],
            manualExpensesTotal: Decimal(string: spending)!,
            receiptTotalsByCategory: [:],
            incomeTotal: Decimal(string: income)!
        )
    }

    @Test
    func spendTrendReturnsEmptyForZeroOrNegativeMonths() {
        #expect(SpendingInsightEngine.spendTrend(months: 0, through: now, expenses: [], income: [], receipts: []).isEmpty)
        #expect(SpendingInsightEngine.spendTrend(months: -3, through: now, expenses: [], income: [], receipts: []).isEmpty)
    }

    @Test
    func storeSharesReturnsEmptyWhenNoPositiveTotals() {
        // Reviewed, reporting-currency receipts but with no usable total — the grand-total guard must
        // return no shares rather than dividing by zero.
        let receipts = [
            ReceiptCapture(capturedAt: date(monthsAgo: 0), purchaseDate: date(monthsAgo: 0),
                           storeChainNameSnapshot: "Test Mart", total: nil, reviewState: .reviewed)
        ]
        #expect(SpendingInsightEngine.storeShares(month: now, receipts: receipts).isEmpty)
    }

    @Test
    func storeSharesFallsBackToUnknownWhenStoreNameMissing() throws {
        // No chain and no location snapshot -> grouped under "Unknown" rather than dropped.
        let receipts = [
            ReceiptCapture(capturedAt: date(monthsAgo: 0), purchaseDate: date(monthsAgo: 0),
                           total: Decimal(string: "40"), reviewState: .reviewed)
        ]
        let shares = SpendingInsightEngine.storeShares(month: now, receipts: receipts)
        #expect(shares.count == 1)
        #expect(shares.first?.storeName == "Unknown")
        #expect(abs((shares.first?.fraction ?? 0) - 1.0) < 0.0001)
    }

    @Test
    func budgetPressureBoundaryRatiosAreClassifiedInclusively() {
        // Exactly 0.7 is the comfortable/tight cut point: `..<0.7` is comfortable, so 0.7 itself is tight.
        #expect(SpendingInsightEngine.budgetPressure(for: summary(income: "1000", spending: "700")).level == .tight)
        // Exactly 1.0 is the tight/over cut point: `0.7..<1.0` is tight, so 1.0 itself is over.
        #expect(SpendingInsightEngine.budgetPressure(for: summary(income: "1000", spending: "1000")).level == .over)
    }
}

struct PriceMedianGapTests {
    private func entry(name: String, price: String, capturedDaysAgo: Int, now: Date) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: .each,
            photoAssetId: ""
        )
    }

    @Test
    func evenCountMedianAveragesTwoDistinctMiddleValues() throws {
        // Existing coverage uses [4,5,5,6] where both middles are 5, so the averaging of *distinct*
        // middles is never exercised. Here sorted prices are [3,4,6,7] -> median = (4 + 6) / 2 = 5.00.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Butter", price: "3.00", capturedDaysAgo: 30, now: now),
            entry(name: "Butter", price: "4.00", capturedDaysAgo: 20, now: now),
            entry(name: "Butter", price: "6.00", capturedDaysAgo: 10, now: now),
            entry(name: "Butter", price: "7.00", capturedDaysAgo: 1, now: now)
        ]

        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Butter",
            displayName: "Butter",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        #expect(history.median == Decimal(string: "5.00"))
    }
}
