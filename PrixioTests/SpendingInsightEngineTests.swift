import Foundation
import Testing
@testable import Prixio

struct SpendingInsightEngineTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    }

    private func date(monthsAgo: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
    }

    private func expense(
        amount: String,
        category: ExpenseCategory = .other,
        merchant: String? = nil,
        date: Date
    ) -> ExpenseEntry {
        ExpenseEntry(date: date, amount: Decimal(string: amount)!, category: category, merchant: merchant)
    }

    private func receipt(
        total: String,
        purchaseDate: Date,
        reviewState: ReceiptReviewState = .reviewed,
        category: ExpenseCategory = .groceries
    ) -> ReceiptCapture {
        ReceiptCapture(
            capturedAt: purchaseDate,
            purchaseDate: purchaseDate,
            total: Decimal(string: total)!,
            reviewState: reviewState,
            category: category
        )
    }

    // MARK: - Monthly summary

    @Test
    func monthlySummaryCombinesCategoriesIncomeAndReceiptGroceries() {
        let expenses = [
            expense(amount: "50", category: .groceries, date: date(daysAgo: 0)),
            expense(amount: "100", category: .utilities, date: date(daysAgo: 1)),
            expense(amount: "15", category: .subscriptions, date: date(daysAgo: 2)),
            expense(amount: "999", category: .groceries, date: date(monthsAgo: 2)) // different month, excluded
        ]
        let income = [
            IncomeEntry(date: date(daysAgo: 0), amount: Decimal(string: "2000")!, label: "Pay"),
            IncomeEntry(date: date(monthsAgo: 2), amount: Decimal(string: "500")!, label: "Old") // excluded
        ]
        let receipts = [
            receipt(total: "80", purchaseDate: date(daysAgo: 3)),
            receipt(total: "40", purchaseDate: date(monthsAgo: 2)) // excluded
        ]

        let summary = SpendingInsightEngine.monthlySummary(
            month: now,
            expenses: expenses,
            income: income,
            receipts: receipts
        )

        #expect(summary.groceriesTotal == Decimal(string: "130")) // 50 manual + 80 receipt
        #expect(summary.receiptGroceriesTotal == Decimal(string: "80"))
        #expect(summary.billsTotal == Decimal(string: "100"))
        #expect(summary.subscriptionsTotal == Decimal(string: "15"))
        #expect(summary.incomeTotal == Decimal(string: "2000"))
        #expect(summary.spendingTotal == Decimal(string: "245")) // 165 manual + 80 receipt
        #expect(summary.net == Decimal(string: "1755"))
    }

    @Test
    func monthlySummaryExcludesUnreviewedReceipts() {
        let receipts = [
            receipt(total: "80", purchaseDate: date(daysAgo: 1), reviewState: .reviewed),
            receipt(total: "55", purchaseDate: date(daysAgo: 2), reviewState: .pendingReview) // excluded
        ]

        let summary = SpendingInsightEngine.monthlySummary(
            month: now,
            expenses: [],
            income: [],
            receipts: receipts
        )

        // Only the reviewed receipt counts; the pending one never reaches spending math.
        #expect(summary.receiptGroceriesTotal == Decimal(string: "80"))
        #expect(summary.spendingTotal == Decimal(string: "80"))
    }

    @Test
    func receiptAttributedToItsOwnCategoryNotAlwaysGroceries() {
        // A grocery receipt counts toward groceries; a utilities-categorized receipt counts toward
        // bills — it must not inflate the grocery figure.
        let groceryReceipt = receipt(total: "60", purchaseDate: date(daysAgo: 1))
        let utilitiesReceipt = receipt(total: "200", purchaseDate: date(daysAgo: 2), category: .utilities)

        let summary = SpendingInsightEngine.monthlySummary(
            month: now,
            expenses: [],
            income: [],
            receipts: [groceryReceipt, utilitiesReceipt]
        )

        #expect(summary.groceriesTotal == Decimal(string: "60"))
        #expect(summary.total(for: .utilities) == Decimal(string: "200"))
        #expect(summary.billsTotal == Decimal(string: "200")) // utilities is bill-like
        #expect(summary.receiptTotal == Decimal(string: "260"))
        #expect(summary.spendingTotal == Decimal(string: "260"))
    }

    @Test
    func nonGroceryReceiptCanTriggerCategoryAnomaly() {
        // Receipts now feed their own category's baseline, so a spike in a non-grocery receipt category
        // is detectable as an anomaly (previously every receipt landed in groceries).
        let baseline = (1...3).map { receipt(total: "30", purchaseDate: date(monthsAgo: $0), category: .utilities) }
        let spike = receipt(total: "300", purchaseDate: date(daysAgo: 1), category: .utilities)

        let anomalies = SpendingInsightEngine.spendingAnomalies(
            month: now,
            expenses: [],
            receipts: baseline + [spike]
        )

        #expect(anomalies.contains { $0.category == .utilities })
        #expect(!anomalies.contains { $0.category == .groceries })
    }

    @Test
    func excludesForeignCurrencyReceiptsAndExpensesFromSpending() {
        // Spending math is single-currency. A USD receipt/expense must be excluded rather than summed
        // as if it were CAD — otherwise a foreign-currency scan silently corrupts the totals.
        let cadReceipt = receipt(total: "80", purchaseDate: date(daysAgo: 1))
        let usdReceipt = ReceiptCapture(
            capturedAt: date(daysAgo: 2),
            purchaseDate: date(daysAgo: 2),
            total: Decimal(string: "200")!,
            currencyCode: "USD",
            reviewState: .reviewed
        )
        let cadExpense = expense(amount: "50", category: .groceries, date: date(daysAgo: 0))
        let usdExpense = ExpenseEntry(
            date: date(daysAgo: 0),
            amount: Decimal(string: "999")!,
            currencyCode: "USD",
            category: .utilities
        )

        let summary = SpendingInsightEngine.monthlySummary(
            month: now,
            expenses: [cadExpense, usdExpense],
            income: [],
            receipts: [cadReceipt, usdReceipt]
        )

        #expect(summary.receiptGroceriesTotal == Decimal(string: "80"))
        #expect(summary.manualExpensesTotal == Decimal(string: "50"))
        #expect(summary.categoryTotals[.utilities] == nil)
    }

    // MARK: - Recurring detection

    @Test
    func detectsMonthlyRecurringMerchant() throws {
        let expenses = [
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 0)),
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 30)),
            expense(amount: "14.99", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 60))
        ]

        let suggestions = SpendingInsightEngine.detectRecurring(
            expenses: expenses,
            existingRules: [],
            now: now
        )

        #expect(suggestions.count == 1)
        let suggestion = try #require(suggestions.first)
        #expect(suggestion.matchKey == "merchant:netflix")
        #expect(suggestion.cadence == .monthly)
        #expect(suggestion.occurrenceCount == 3)
    }

    @Test
    func detectsWeeklyRecurringMerchant() throws {
        // ~7-day intervals classify as weekly (nearest cadence to the 7-day average, within the ±50%
        // band). Only monthly was previously exercised, leaving the weekly/biweekly branches untested.
        let expenses = [
            expense(amount: "12.00", category: .other, merchant: "Coffee Co", date: date(daysAgo: 0)),
            expense(amount: "12.00", category: .other, merchant: "Coffee Co", date: date(daysAgo: 7)),
            expense(amount: "12.00", category: .other, merchant: "Coffee Co", date: date(daysAgo: 14))
        ]

        let suggestions = SpendingInsightEngine.detectRecurring(expenses: expenses, existingRules: [], now: now)

        let suggestion = try #require(suggestions.first)
        #expect(suggestion.cadence == .weekly)
        #expect(suggestion.occurrenceCount == 3)
    }

    @Test
    func detectsBiweeklyRecurringMerchant() throws {
        // ~14-day intervals classify as biweekly (nearest cadence to the 14-day average).
        let expenses = [
            expense(amount: "40.00", category: .other, merchant: "Gym", date: date(daysAgo: 0)),
            expense(amount: "40.00", category: .other, merchant: "Gym", date: date(daysAgo: 14)),
            expense(amount: "40.00", category: .other, merchant: "Gym", date: date(daysAgo: 28))
        ]

        let suggestions = SpendingInsightEngine.detectRecurring(expenses: expenses, existingRules: [], now: now)

        let suggestion = try #require(suggestions.first)
        #expect(suggestion.cadence == .biweekly)
        #expect(suggestion.occurrenceCount == 3)
    }

    @Test
    func doesNotSuggestBelowMinimumOccurrences() {
        let expenses = [
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 0)),
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 30))
        ]

        let suggestions = SpendingInsightEngine.detectRecurring(
            expenses: expenses,
            existingRules: [],
            now: now
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func doesNotSuggestIrregularIntervals() {
        let expenses = [
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 0)),
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 3)),
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 90))
        ]

        let suggestions = SpendingInsightEngine.detectRecurring(
            expenses: expenses,
            existingRules: [],
            now: now
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func doesNotSuggestInconsistentAmounts() {
        let expenses = [
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 0)),
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 30)),
            expense(amount: "200.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 60))
        ]

        let suggestions = SpendingInsightEngine.detectRecurring(
            expenses: expenses,
            existingRules: [],
            now: now
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func skipsStalePatternsThatHaveGoneSilent() {
        // A clean monthly pattern, but the most recent occurrence is ~3 months old — the pattern is
        // no longer live, so it should not be surfaced as "recurring" now.
        let expenses = [
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 90)),
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 120)),
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 150))
        ]

        let suggestions = SpendingInsightEngine.detectRecurring(
            expenses: expenses,
            existingRules: [],
            now: now
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func skipsPatternsAlreadyDismissed() {
        let expenses = [
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 0)),
            expense(amount: "15.00", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 30)),
            expense(amount: "14.99", category: .subscriptions, merchant: "Netflix", date: date(daysAgo: 60))
        ]
        let rules = [
            RecurringExpenseRule(matchKey: "merchant:netflix", displayLabel: "Netflix", status: .dismissed)
        ]

        let suggestions = SpendingInsightEngine.detectRecurring(
            expenses: expenses,
            existingRules: rules,
            now: now
        )

        #expect(suggestions.isEmpty)
    }
}
