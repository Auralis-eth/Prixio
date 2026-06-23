import Foundation
import Testing
@testable import Prixio

/// Coverage for `SpendingViewModel`, which fans a month's raw records out into the published state
/// the spending screen renders. The view model delegates the heavy math to `SpendingInsightEngine`
/// (tested separately), so these tests focus on the view model's own responsibilities: month
/// filtering, sort order, and wiring each derived value onto its published property.
@MainActor
struct SpendingViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(monthsAgo: Int, day: Int = 14) -> Date {
        let calendar = Calendar.current
        let monthStart = MonthBucket.start(of: calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now)
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
    }

    private func expense(_ amount: String, category: ExpenseCategory, date: Date, merchant: String? = nil) -> ExpenseEntry {
        ExpenseEntry(date: date, amount: Decimal(string: amount)!, category: category, merchant: merchant)
    }

    // MARK: - Initial state

    @Test
    func init_startsWithEmptySummaryAndNoIncomeData() {
        let model = SpendingViewModel()

        #expect(model.summary.spendingTotal == 0)
        #expect(model.summary.incomeTotal == 0)
        #expect(model.monthExpenses.isEmpty)
        #expect(model.monthIncome.isEmpty)
        #expect(model.budgetPressure.level == .noIncomeData)
    }

    // MARK: - recompute wiring

    @Test
    func recompute_filtersToMonthAndSortsNewestFirst() {
        let model = SpendingViewModel()
        let early = expense("50", category: .groceries, date: date(monthsAgo: 0, day: 5))
        let late = expense("100", category: .utilities, date: date(monthsAgo: 0, day: 20))
        let lastMonth = expense("999", category: .rent, date: date(monthsAgo: 1))

        let incomeThisMonth = IncomeEntry(date: date(monthsAgo: 0, day: 1), amount: Decimal(string: "2000")!, label: "Pay")
        let incomeLastMonth = IncomeEntry(date: date(monthsAgo: 1), amount: Decimal(string: "500")!, label: "Old")

        model.recompute(
            month: now,
            expenses: [early, late, lastMonth],
            income: [incomeThisMonth, incomeLastMonth],
            receipts: [],
            rules: [],
            now: now
        )

        // Out-of-month records dropped; remaining sorted newest first.
        #expect(model.monthExpenses.map(\.id) == [late.id, early.id])
        #expect(model.monthIncome.map(\.id) == [incomeThisMonth.id])
    }

    @Test
    func recompute_populatesSummaryTrendAndBudgetPressure() {
        let model = SpendingViewModel()
        let groceries = expense("50", category: .groceries, date: date(monthsAgo: 0, day: 5))
        let utilities = expense("100", category: .utilities, date: date(monthsAgo: 0, day: 10))
        let income = IncomeEntry(date: date(monthsAgo: 0, day: 1), amount: Decimal(string: "2000")!, label: "Pay")
        let receipt = ReceiptCapture(
            capturedAt: date(monthsAgo: 0, day: 7),
            purchaseDate: date(monthsAgo: 0, day: 7),
            storeChainNameSnapshot: "Test Mart",
            total: Decimal(string: "80")!,
            reviewState: .reviewed
        )

        model.recompute(
            month: now,
            expenses: [groceries, utilities],
            income: [income],
            receipts: [receipt],
            rules: [],
            now: now
        )

        // Summary folds manual expenses + reviewed receipt grocery spend.
        #expect(model.summary.spendingTotal == Decimal(string: "230")) // 150 manual + 80 receipt
        #expect(model.summary.incomeTotal == Decimal(string: "2000"))

        // Trend always returns six months, oldest first, ending at the requested month.
        #expect(model.trend.count == 6)
        #expect(model.trend.first!.month < model.trend.last!.month)
        #expect(model.trend.last!.spending == Decimal(string: "230"))

        // One reviewed receipt → a single store taking the full share.
        #expect(model.storeShares.count == 1)
        #expect(model.storeShares.first?.storeName == "Test Mart")
        #expect(abs((model.storeShares.first?.fraction ?? 0) - 1.0) < 0.0001)

        // 230 spent against 2000 income is comfortably under budget.
        #expect(model.budgetPressure.level == .comfortable)
    }

    @Test
    func recompute_surfacesConfirmedRecurringSuggestion() throws {
        let model = SpendingViewModel()
        let expenses = [
            expense("15.00", category: .subscriptions, date: date(monthsAgo: 0, day: 1), merchant: "Netflix"),
            expense("15.00", category: .subscriptions, date: date(monthsAgo: 1, day: 1), merchant: "Netflix"),
            expense("14.99", category: .subscriptions, date: date(monthsAgo: 2, day: 1), merchant: "Netflix")
        ]

        model.recompute(month: now, expenses: expenses, income: [], receipts: [], rules: [], now: now)

        let suggestion = try #require(model.suggestions.first)
        #expect(suggestion.matchKey == "merchant:netflix")
    }

    @Test
    func recompute_excludesForeignCurrencyRowsFromTheLists() {
        // The displayed rows must reconcile with `summary`/Net, which only sum reporting-currency
        // records. A foreign-currency row would otherwise show in the list (formatted as the reporting
        // currency) yet contribute nothing to the totals, so the numbers wouldn't add up.
        let model = SpendingViewModel()
        let local = ExpenseEntry(
            date: date(monthsAgo: 0, day: 5),
            amount: Decimal(string: "50")!,
            currencyCode: SpendingInsightEngine.reportingCurrency,
            category: .groceries
        )
        let foreign = ExpenseEntry(
            date: date(monthsAgo: 0, day: 6),
            amount: Decimal(string: "999")!,
            currencyCode: "USD",
            category: .groceries
        )
        let localIncome = IncomeEntry(
            date: date(monthsAgo: 0, day: 1),
            amount: Decimal(string: "2000")!,
            currencyCode: SpendingInsightEngine.reportingCurrency,
            label: "Pay"
        )
        let foreignIncome = IncomeEntry(
            date: date(monthsAgo: 0, day: 2),
            amount: Decimal(string: "3000")!,
            currencyCode: "USD",
            label: "Foreign Pay"
        )

        model.recompute(
            month: now,
            expenses: [local, foreign],
            income: [localIncome, foreignIncome],
            receipts: [],
            rules: [],
            now: now
        )

        #expect(model.monthExpenses.map(\.id) == [local.id])
        #expect(model.monthIncome.map(\.id) == [localIncome.id])
        // And the lists agree with the (currency-filtered) summary.
        #expect(model.summary.spendingTotal == Decimal(string: "50"))
        #expect(model.summary.incomeTotal == Decimal(string: "2000"))
    }
}
