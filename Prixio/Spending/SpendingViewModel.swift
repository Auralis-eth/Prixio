import Combine
import Foundation

@MainActor
final class SpendingViewModel: ObservableObject {
    @Published private(set) var summary: MonthlySummary
    @Published private(set) var monthExpenses: [ExpenseEntry] = []
    @Published private(set) var monthIncome: [IncomeEntry] = []
    @Published private(set) var monthReceipts: [ReceiptCapture] = []
    @Published private(set) var suggestions: [RecurringSuggestion] = []
    @Published private(set) var trend: [SpendingTrendPoint] = []
    @Published private(set) var storeShares: [StoreShare] = []
    @Published private(set) var budgetPressure: BudgetPressure
    @Published private(set) var anomalies: [SpendingAnomaly] = []

    init() {
        summary = MonthlySummary(
            month: MonthBucket.start(of: .now),
            categoryTotals: [:],
            manualExpensesTotal: 0,
            receiptTotalsByCategory: [:],
            incomeTotal: 0
        )
        budgetPressure = BudgetPressure(level: .noIncomeData, spending: 0, income: 0, ratio: nil)
    }

    func recompute(
        month: Date,
        expenses: [ExpenseEntry],
        income: [IncomeEntry],
        receipts: [ReceiptCapture],
        rules: [RecurringExpenseRule],
        now: Date = .now
    ) {
        summary = SpendingInsightEngine.monthlySummary(
            month: month,
            expenses: expenses,
            income: income,
            receipts: receipts
        )

        // Only show rows in the reporting currency — these lists must reconcile with `summary`/Net,
        // which sum reporting-currency records only. A foreign-currency row would otherwise render here
        // (formatted as the reporting currency by the shared formatter) yet contribute nothing to the
        // totals, so the displayed numbers wouldn't add up. Cross-currency support is a separate effort.
        monthExpenses = expenses
            .filter { $0.currencyCode == SpendingInsightEngine.reportingCurrency }
            .filter { MonthBucket.contains($0.date, month: month) }
            .sorted { $0.date > $1.date }

        monthIncome = income
            .filter { $0.currencyCode == SpendingInsightEngine.reportingCurrency }
            .filter { MonthBucket.contains($0.date, month: month) }
            .sorted { $0.date > $1.date }

        // Scope the receipts list to the displayed month so it reconciles with the summary, which only
        // sums receipts bucketed into `month` (`SpendingInsightEngine.spendingReceipts` + month filter).
        // Reviewed receipts are additionally restricted to the reporting currency to match the totals —
        // but unreviewed drafts stay visible in any currency so a misread-currency receipt can still be
        // reached and corrected here (its "Needs review" badge already explains it isn't in totals yet).
        monthReceipts = receipts
            .filter { MonthBucket.contains($0.purchaseDate ?? $0.capturedAt, month: month) }
            .filter { $0.currencyCode == SpendingInsightEngine.reportingCurrency || $0.reviewState != .reviewed }
            .sorted { ($0.purchaseDate ?? $0.capturedAt) > ($1.purchaseDate ?? $1.capturedAt) }

        suggestions = SpendingInsightEngine.detectRecurring(
            expenses: expenses,
            existingRules: rules,
            now: now
        )

        trend = SpendingInsightEngine.spendTrend(
            months: 6,
            through: month,
            expenses: expenses,
            income: income,
            receipts: receipts
        )

        storeShares = SpendingInsightEngine.storeShares(month: month, receipts: receipts)

        budgetPressure = SpendingInsightEngine.budgetPressure(for: summary)

        anomalies = SpendingInsightEngine.spendingAnomalies(
            month: month,
            expenses: expenses,
            receipts: receipts
        )
    }
}
