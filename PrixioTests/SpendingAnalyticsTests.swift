import Foundation
import Testing
@testable import Prixio

struct SpendingAnalyticsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(monthsAgo: Int, day: Int = 14) -> Date {
        let calendar = Calendar.current
        let monthStart = MonthBucket.start(of: calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now)
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
    }

    private func expense(
        amount: String,
        category: ExpenseCategory,
        merchant: String? = nil,
        date: Date
    ) -> ExpenseEntry {
        ExpenseEntry(date: date, amount: Decimal(string: amount)!, category: category, merchant: merchant)
    }

    private func receipt(
        total: String,
        chain: String,
        date: Date,
        reviewState: ReceiptReviewState = .reviewed
    ) -> ReceiptCapture {
        ReceiptCapture(
            capturedAt: date,
            purchaseDate: date,
            storeChainNameSnapshot: chain,
            total: Decimal(string: total)!,
            reviewState: reviewState
        )
    }

    // MARK: - Trend

    @Test
    func spendTrendReturnsRequestedMonthsOldestFirst() {
        let expenses = [
            expense(amount: "100", category: .utilities, date: date(monthsAgo: 0)),
            expense(amount: "200", category: .rent, date: date(monthsAgo: 1))
        ]

        let trend = SpendingInsightEngine.spendTrend(
            months: 3,
            through: now,
            expenses: expenses,
            income: [],
            receipts: []
        )

        #expect(trend.count == 3)
        #expect(trend[0].spending == 0)          // two months ago
        #expect(trend[1].spending == Decimal(string: "200")) // last month
        #expect(trend[2].spending == Decimal(string: "100")) // this month
        #expect(trend[0].month < trend[2].month) // oldest first
    }

    // MARK: - Store share

    @Test
    func storeSharesComputeRankedFractions() throws {
        let receipts = [
            receipt(total: "75", chain: "Test Mart", date: date(monthsAgo: 0, day: 5)),
            receipt(total: "25", chain: "Seed Foods", date: date(monthsAgo: 0, day: 10)),
            receipt(total: "500", chain: "Old Store", date: date(monthsAgo: 2)) // different month, excluded
        ]

        let shares = SpendingInsightEngine.storeShares(month: now, receipts: receipts)

        #expect(shares.count == 2)
        #expect(shares.first?.storeName == "Test Mart")
        #expect(abs((shares.first?.fraction ?? 0) - 0.75) < 0.0001)
        #expect(abs((shares.last?.fraction ?? 0) - 0.25) < 0.0001)
    }

    // MARK: - Budget pressure

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
    func budgetPressureClassifiesRatios() {
        #expect(SpendingInsightEngine.budgetPressure(for: summary(income: "1000", spending: "500")).level == .comfortable)
        #expect(SpendingInsightEngine.budgetPressure(for: summary(income: "1000", spending: "800")).level == .tight)
        #expect(SpendingInsightEngine.budgetPressure(for: summary(income: "1000", spending: "1200")).level == .over)

        let noIncome = SpendingInsightEngine.budgetPressure(for: summary(income: "0", spending: "500"))
        #expect(noIncome.level == .noIncomeData)
        #expect(noIncome.ratio == nil)
    }

    // MARK: - Anomalies

    @Test
    func flagsCategorySpikeAgainstBaseline() throws {
        var expenses: [ExpenseEntry] = []
        for monthsAgo in 1...3 {
            expenses.append(expense(amount: "100", category: .utilities, date: date(monthsAgo: monthsAgo)))
            expenses.append(expense(amount: "1500", category: .rent, date: date(monthsAgo: monthsAgo)))
        }
        // Current month: utilities spikes, rent steady, plus a tiny new category.
        expenses.append(expense(amount: "400", category: .utilities, date: date(monthsAgo: 0)))
        expenses.append(expense(amount: "1500", category: .rent, date: date(monthsAgo: 0)))
        expenses.append(expense(amount: "5", category: .other, date: date(monthsAgo: 0)))

        let anomalies = SpendingInsightEngine.spendingAnomalies(
            month: now,
            expenses: expenses,
            receipts: []
        )

        #expect(anomalies.count == 1)
        let anomaly = try #require(anomalies.first)
        #expect(anomaly.category == .utilities)
        #expect(anomaly.currentTotal == Decimal(string: "400"))
        #expect(anomaly.baselineAverage == Decimal(string: "100"))
        #expect(abs(anomaly.deltaFraction - 3.0) < 0.0001)
    }

    @Test
    func ranksMultipleAnomaliesByDeltaFractionDescending() throws {
        // Two categories spike at once with different magnitudes. The engine sorts anomalies by
        // `deltaFraction` descending, so the larger relative spike (groceries, 5x) must come before the
        // smaller one (utilities, 3x). Only the single-anomaly case was previously exercised.
        var expenses: [ExpenseEntry] = []
        for monthsAgo in 1...3 {
            expenses.append(expense(amount: "100", category: .utilities, date: date(monthsAgo: monthsAgo)))
            expenses.append(expense(amount: "100", category: .groceries, date: date(monthsAgo: monthsAgo)))
        }
        expenses.append(expense(amount: "400", category: .utilities, date: date(monthsAgo: 0))) // 3x
        expenses.append(expense(amount: "600", category: .groceries, date: date(monthsAgo: 0))) // 5x

        let anomalies = SpendingInsightEngine.spendingAnomalies(month: now, expenses: expenses, receipts: [])

        #expect(anomalies.map(\.category) == [.groceries, .utilities])
        #expect(abs((anomalies.first?.deltaFraction ?? 0) - 5.0) < 0.0001)
        #expect(abs((anomalies.last?.deltaFraction ?? 0) - 3.0) < 0.0001)
    }

    @Test
    func doesNotFlagWhenNoBaselineHistory() {
        let expenses = [
            expense(amount: "400", category: .utilities, date: date(monthsAgo: 0))
        ]

        let anomalies = SpendingInsightEngine.spendingAnomalies(
            month: now,
            expenses: expenses,
            receipts: []
        )

        #expect(anomalies.isEmpty)
    }

    @Test
    func doesNotFlagIntermittentCategoryWithThinBaseline() {
        // Utilities appears in only ONE of the three baseline months ($60). Averaging over the months
        // that actually had spend gives a $60 baseline, so a steady $60 this month is NOT an anomaly.
        // (Dividing by the full 3-month lookback would deflate the baseline to $20 and fire a false
        // spike — the bug this guards against.)
        let expenses = [
            expense(amount: "60", category: .utilities, date: date(monthsAgo: 2)),
            expense(amount: "60", category: .utilities, date: date(monthsAgo: 0))
        ]

        let anomalies = SpendingInsightEngine.spendingAnomalies(
            month: now,
            expenses: expenses,
            receipts: []
        )

        #expect(!anomalies.contains { $0.category == .utilities })
    }

    @Test
    func stillFlagsGenuineSpikeOnIntermittentCategory() throws {
        // Same thin baseline ($60 in one month), but this month is $200 — a real spike that still
        // clears the multiplier against the $60 (not deflated) baseline.
        let expenses = [
            expense(amount: "60", category: .utilities, date: date(monthsAgo: 2)),
            expense(amount: "200", category: .utilities, date: date(monthsAgo: 0))
        ]

        let anomalies = SpendingInsightEngine.spendingAnomalies(
            month: now,
            expenses: expenses,
            receipts: []
        )

        let anomaly = try #require(anomalies.first { $0.category == .utilities })
        #expect(anomaly.baselineAverage == Decimal(string: "60"))
    }
}
