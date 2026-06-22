import Foundation

/// Monthly spending picture: per-category expense totals, grocery spend (manual groceries plus
/// reviewed receipt totals), income, and the resulting net.
struct MonthlySummary: Equatable, Sendable {
    let month: Date
    /// Per-category totals from manual expenses only.
    let categoryTotals: [ExpenseCategory: Decimal]
    let manualExpensesTotal: Decimal
    /// Receipt basket totals attributed to each receipt's own category (defaults to groceries), kept
    /// separate from manual expenses so a receipt can be re-categorized without touching expense data.
    let receiptTotalsByCategory: [ExpenseCategory: Decimal]
    let incomeTotal: Decimal

    /// Combined manual + receipt spend for a single category.
    func total(for category: ExpenseCategory) -> Decimal {
        (categoryTotals[category] ?? 0) + (receiptTotalsByCategory[category] ?? 0)
    }

    /// All receipt spend for the month, across every category.
    var receiptTotal: Decimal {
        receiptTotalsByCategory.values.reduce(Decimal(0), +)
    }

    /// Receipt spend attributed to groceries. Retained for callers/tests that track grocery receipts.
    var receiptGroceriesTotal: Decimal {
        receiptTotalsByCategory[.groceries] ?? 0
    }

    /// All grocery spending for the month: manual grocery expenses plus grocery-categorized receipts.
    var groceriesTotal: Decimal {
        total(for: .groceries)
    }

    /// Recurring obligations grouped together for display (manual + receipts in those categories).
    var billsTotal: Decimal {
        ExpenseCategory.billLikeCategories.reduce(Decimal(0)) { $0 + total(for: $1) }
    }

    var subscriptionsTotal: Decimal {
        total(for: .subscriptions)
    }

    /// Total money out for the month (manual expenses + all receipt spend).
    var spendingTotal: Decimal {
        manualExpensesTotal + receiptTotal
    }

    var net: Decimal {
        incomeTotal - spendingTotal
    }
}

/// A conservative recurring-pattern suggestion derived from expense history. Surfaced for user
/// confirm/dismiss — never applied automatically.
struct RecurringSuggestion: Equatable, Sendable, Identifiable {
    let matchKey: String
    let displayLabel: String
    let cadence: RecurrenceCadence
    let occurrenceCount: Int
    let averageAmount: Decimal

    var id: String { matchKey }
}

/// One month's spending picture for the spend-over-time trend.
struct SpendingTrendPoint: Equatable, Sendable, Identifiable {
    let month: Date
    let spending: Decimal
    let groceries: Decimal
    let income: Decimal

    var id: Date { month }
}

/// A store's share of receipt spending for a month.
struct StoreShare: Equatable, Sendable, Identifiable {
    let storeName: String
    let total: Decimal
    /// Fraction of the month's receipt spending (0...1).
    let fraction: Double

    var id: String { storeName }
}

/// How hard spending is pressing against income for a month.
enum BudgetPressureLevel: String, Equatable, Sendable {
    case noIncomeData
    case comfortable
    case tight
    case over

    var displayName: String {
        switch self {
        case .noIncomeData:
            return "Add income to track budget"
        case .comfortable:
            return "Comfortable"
        case .tight:
            return "Tight"
        case .over:
            return "Over budget"
        }
    }

    var systemImage: String {
        switch self {
        case .noIncomeData:
            return "questionmark.circle"
        case .comfortable:
            return "checkmark.circle"
        case .tight:
            return "exclamationmark.circle"
        case .over:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct BudgetPressure: Equatable, Sendable {
    let level: BudgetPressureLevel
    let spending: Decimal
    let income: Decimal
    /// spending ÷ income, or `nil` when there is no income to compare against.
    let ratio: Double?
}

/// A category whose current-month spending is meaningfully above its recent baseline.
struct SpendingAnomaly: Equatable, Sendable, Identifiable {
    let category: ExpenseCategory
    let currentTotal: Decimal
    let baselineAverage: Decimal
    /// (current − baseline) ÷ baseline.
    let deltaFraction: Double

    var id: String { category.rawValue }
}

/// Stateless derivation of spending summaries and recurring-expense suggestions. Capture stores the
/// raw expenses/income; this engine derives the conclusions so they can be recomputed any time.
enum SpendingInsightEngine {
    /// Minimum occurrences before a pattern is conservative enough to suggest.
    static let recurringMinOccurrences = 3

    /// Maximum fractional deviation from the mean amount before a pattern is too irregular to call
    /// recurring.
    static let recurringAmountTolerance = 0.30

    /// Spending ÷ income below this is "comfortable".
    static let budgetComfortableRatio = 0.7

    /// How many months of history a spending anomaly is measured against.
    static let anomalyBaselineMonths = 3

    /// A category must be at least this far above its baseline (1.4 = 40%) to flag as an anomaly.
    static let anomalyMultiplier = 1.4

    /// Minimum baseline and absolute overspend (avoids flagging noise on tiny categories).
    static let anomalyMinimumAmount = Decimal(20)

    /// Only receipts the user has reviewed count toward spending — a `pendingReview` capture may
    /// still carry an unverified OCR/model total, so it must never reach the spending picture.
    static func reviewedReceipts(_ receipts: [ReceiptCapture]) -> [ReceiptCapture] {
        receipts.filter { $0.reviewState == .reviewed }
    }

    /// Spending math is single-currency: the engine sums only amounts in the app's reporting currency.
    /// A record in another currency (e.g. a foreign-currency receipt) is excluded rather than added as
    /// if it were the same currency — cross-currency conversion is a separate effort (see the doc).
    static let reportingCurrency = AppCurrency.defaultCode

    /// Receipts that count toward spending: reviewed AND in the reporting currency.
    static func spendingReceipts(_ receipts: [ReceiptCapture]) -> [ReceiptCapture] {
        reviewedReceipts(receipts).filter { $0.currencyCode == reportingCurrency }
    }

    private static func reportingExpenses(_ expenses: [ExpenseEntry]) -> [ExpenseEntry] {
        expenses.filter { $0.currencyCode == reportingCurrency }
    }

    private static func reportingIncome(_ income: [IncomeEntry]) -> [IncomeEntry] {
        income.filter { $0.currencyCode == reportingCurrency }
    }

    static func monthlySummary(
        month: Date,
        expenses: [ExpenseEntry],
        income: [IncomeEntry],
        receipts: [ReceiptCapture],
        calendar: Calendar = .current
    ) -> MonthlySummary {
        let expenses = reportingExpenses(expenses)
        let income = reportingIncome(income)
        let monthExpenses = expenses.filter { MonthBucket.contains($0.date, month: month, calendar: calendar) }
        let monthIncome = income.filter { MonthBucket.contains($0.date, month: month, calendar: calendar) }
        let monthReceipts = spendingReceipts(receipts).filter {
            MonthBucket.contains($0.purchaseDate ?? $0.capturedAt, month: month, calendar: calendar)
        }

        var categoryTotals: [ExpenseCategory: Decimal] = [:]
        for expense in monthExpenses {
            categoryTotals[expense.category, default: 0] += expense.amount
        }

        var receiptTotalsByCategory: [ExpenseCategory: Decimal] = [:]
        for receipt in monthReceipts {
            receiptTotalsByCategory[receipt.category, default: 0] += (receipt.total ?? 0)
        }

        return MonthlySummary(
            month: MonthBucket.start(of: month, calendar: calendar),
            categoryTotals: categoryTotals,
            manualExpensesTotal: monthExpenses.reduce(Decimal(0)) { $0 + $1.amount },
            receiptTotalsByCategory: receiptTotalsByCategory,
            incomeTotal: monthIncome.reduce(Decimal(0)) { $0 + $1.amount }
        )
    }

    /// Detects repeated expenses that look weekly/biweekly/monthly. Conservative: requires at least
    /// `recurringMinOccurrences` occurrences at a regular interval with consistent amounts, and skips
    /// patterns the user already confirmed or dismissed.
    static func detectRecurring(
        expenses: [ExpenseEntry],
        existingRules: [RecurringExpenseRule],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [RecurringSuggestion] {
        let suppressed = Set(
            existingRules
                .filter { $0.status == .confirmed || $0.status == .dismissed }
                .map(\.matchKey)
        )

        let expenses = reportingExpenses(expenses)
        let groups = Dictionary(grouping: expenses, by: matchKey(for:))
        var suggestions: [RecurringSuggestion] = []

        for (key, group) in groups {
            guard !suppressed.contains(key), group.count >= recurringMinOccurrences else {
                continue
            }

            let sorted = group.sorted { $0.date < $1.date }

            // Only suggest merchant-identified patterns. Merchant-less expenses fall back to a
            // category bucket (see `matchKey`), which can merge unrelated expenses of similar amount
            // into a false "recurring" pattern. We still group them for confirmed-rule matching, but
            // we don't guess a suggestion from a category alone.
            let hasMerchant = !(sorted[0].merchant?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            guard hasMerchant else {
                continue
            }

            let dates = sorted.map(\.date)
            let intervals = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) / 86_400 }
            guard let cadence = cadence(forIntervals: intervals) else {
                continue
            }

            // Only surface patterns that are still live: the most recent occurrence must fall within
            // ~1.5 cadence intervals of `now`, otherwise the pattern has gone silent.
            if let lastDate = dates.last {
                let daysSinceLast = now.timeIntervalSince(lastDate) / 86_400
                guard daysSinceLast <= cadence.approximateDays * 1.5 else {
                    continue
                }
            }

            let amounts = sorted.map(\.amount)
            guard let averageAmount = consistentMeanAmount(amounts) else {
                continue
            }

            suggestions.append(
                RecurringSuggestion(
                    matchKey: key,
                    displayLabel: displayLabel(for: sorted[0]),
                    cadence: cadence,
                    occurrenceCount: group.count,
                    averageAmount: averageAmount
                )
            )
        }

        return suggestions.sorted {
            $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending
        }
    }

    /// Spending over the last `months` calendar months ending at `through` (oldest first).
    static func spendTrend(
        months: Int,
        through: Date,
        expenses: [ExpenseEntry],
        income: [IncomeEntry],
        receipts: [ReceiptCapture],
        calendar: Calendar = .current
    ) -> [SpendingTrendPoint] {
        guard months > 0 else {
            return []
        }
        return stride(from: months - 1, through: 0, by: -1).compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: through) else {
                return nil
            }
            let summary = monthlySummary(
                month: monthDate,
                expenses: expenses,
                income: income,
                receipts: receipts,
                calendar: calendar
            )
            return SpendingTrendPoint(
                month: summary.month,
                spending: summary.spendingTotal,
                groceries: summary.groceriesTotal,
                income: summary.incomeTotal
            )
        }
    }

    /// Each store's share of the month's receipt spending, ranked highest first.
    static func storeShares(
        month: Date,
        receipts: [ReceiptCapture],
        calendar: Calendar = .current
    ) -> [StoreShare] {
        let monthReceipts = spendingReceipts(receipts).filter {
            MonthBucket.contains($0.purchaseDate ?? $0.capturedAt, month: month, calendar: calendar)
        }
        let grandTotal = monthReceipts.reduce(Decimal(0)) { $0 + ($1.total ?? 0) }
        guard grandTotal > 0 else {
            return []
        }
        let grandDouble = (grandTotal as NSDecimalNumber).doubleValue

        let grouped = Dictionary(grouping: monthReceipts) { receipt in
            receipt.storeChainNameSnapshot ?? receipt.storeLocationNameSnapshot ?? "Unknown"
        }

        return grouped
            .map { name, group in
                let total = group.reduce(Decimal(0)) { $0 + ($1.total ?? 0) }
                return StoreShare(
                    storeName: name,
                    total: total,
                    fraction: (total as NSDecimalNumber).doubleValue / grandDouble
                )
            }
            .sorted { $0.total > $1.total }
    }

    /// How spending compares to income for the month.
    static func budgetPressure(for summary: MonthlySummary) -> BudgetPressure {
        let spending = summary.spendingTotal
        let income = summary.incomeTotal
        guard income > 0 else {
            return BudgetPressure(level: .noIncomeData, spending: spending, income: income, ratio: nil)
        }

        let ratio = (spending as NSDecimalNumber).doubleValue / (income as NSDecimalNumber).doubleValue
        let level: BudgetPressureLevel
        switch ratio {
        case ..<budgetComfortableRatio:
            level = .comfortable
        case budgetComfortableRatio..<1.0:
            level = .tight
        default:
            level = .over
        }
        return BudgetPressure(level: level, spending: spending, income: income, ratio: ratio)
    }

    /// Categories whose current-month spending is meaningfully above their recent baseline. Grocery
    /// spend includes receipt totals. Conservative: requires a real baseline and both a percentage
    /// and absolute overshoot.
    static func spendingAnomalies(
        month: Date,
        baselineMonths: Int = anomalyBaselineMonths,
        expenses: [ExpenseEntry],
        receipts: [ReceiptCapture],
        calendar: Calendar = .current
    ) -> [SpendingAnomaly] {
        let current = categorySpending(month: month, expenses: expenses, receipts: receipts, calendar: calendar)

        var baselineMonthly: [[ExpenseCategory: Decimal]] = []
        for offset in 1...max(1, baselineMonths) {
            guard let baselineMonth = calendar.date(byAdding: .month, value: -offset, to: month) else {
                continue
            }
            baselineMonthly.append(
                categorySpending(month: baselineMonth, expenses: expenses, receipts: receipts, calendar: calendar)
            )
        }
        guard !baselineMonthly.isEmpty else {
            return []
        }

        var anomalies: [SpendingAnomaly] = []
        for category in ExpenseCategory.allCases {
            // Average only over months that actually had spend in this category. Dividing by the full
            // lookback would deflate the baseline for intermittent categories (e.g. a quarterly bill or
            // a brand-new category), making the current month trivially clear the multiplier and firing
            // a false "unusual this month". A category with no baseline history is skipped entirely.
            let monthlyAmounts = baselineMonthly.compactMap { $0[category] }
            guard !monthlyAmounts.isEmpty else {
                continue
            }
            let baselineSum = monthlyAmounts.reduce(Decimal(0), +)
            let baseline = baselineSum / Decimal(monthlyAmounts.count)
            let currentTotal = current[category] ?? 0

            guard baseline >= anomalyMinimumAmount else {
                continue
            }
            let baselineDouble = (baseline as NSDecimalNumber).doubleValue
            let currentDouble = (currentTotal as NSDecimalNumber).doubleValue
            guard
                baselineDouble > 0,
                currentDouble >= baselineDouble * anomalyMultiplier,
                currentTotal - baseline >= anomalyMinimumAmount
            else {
                continue
            }

            anomalies.append(
                SpendingAnomaly(
                    category: category,
                    currentTotal: currentTotal,
                    baselineAverage: baseline,
                    deltaFraction: (currentDouble - baselineDouble) / baselineDouble
                )
            )
        }

        return anomalies.sorted { $0.deltaFraction > $1.deltaFraction }
    }

    /// Per-category spending for a month, folding each receipt's total into its own category.
    private static func categorySpending(
        month: Date,
        expenses: [ExpenseEntry],
        receipts: [ReceiptCapture],
        calendar: Calendar
    ) -> [ExpenseCategory: Decimal] {
        var totals: [ExpenseCategory: Decimal] = [:]
        for expense in reportingExpenses(expenses) where MonthBucket.contains(expense.date, month: month, calendar: calendar) {
            totals[expense.category, default: 0] += expense.amount
        }
        let monthReceipts = spendingReceipts(receipts)
            .filter { MonthBucket.contains($0.purchaseDate ?? $0.capturedAt, month: month, calendar: calendar) }
        for receipt in monthReceipts {
            totals[receipt.category, default: 0] += (receipt.total ?? 0)
        }
        return totals
    }

    /// Grouping key for recurrence: prefer the normalized merchant, otherwise the category.
    static func matchKey(for expense: ExpenseEntry) -> String {
        matchKey(merchant: expense.merchant, category: expense.category)
    }

    /// Grouping key computed from raw fields, so a not-yet-created expense can be matched against
    /// existing confirmed rules.
    static func matchKey(merchant: String?, category: ExpenseCategory) -> String {
        if let merchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines),
           !merchant.isEmpty {
            return "merchant:\(merchant.lowercased())"
        }
        return "category:\(category.rawValue)"
    }

    private static func displayLabel(for expense: ExpenseEntry) -> String {
        if let merchant = expense.merchant?.trimmingCharacters(in: .whitespacesAndNewlines),
           !merchant.isEmpty {
            return merchant
        }
        return expense.category.displayName
    }

    /// Classifies an interval series into a cadence, requiring the average to land in a cadence band
    /// and every interval to stay within ±50% of that cadence.
    private static func cadence(forIntervals intervals: [Double]) -> RecurrenceCadence? {
        guard !intervals.isEmpty else {
            return nil
        }
        let average = intervals.reduce(0, +) / Double(intervals.count)

        // Pick the cadence whose typical interval is closest to the observed average, then accept it
        // only when the average sits within ±50% of that cadence. Choosing by nearest cadence (rather
        // than hard-coded ranges) closes the dead bands a switch leaves — e.g. ~20-day or ~40-day
        // cadences that previously fell between cases and were silently dropped — while still
        // rejecting intervals that match no cadence at all.
        guard let cadence = RecurrenceCadence.allCases.min(by: {
            abs($0.approximateDays - average) < abs($1.approximateDays - average)
        }) else {
            return nil
        }

        let lower = cadence.approximateDays * 0.5
        let upper = cadence.approximateDays * 1.5
        guard average >= lower, average <= upper else {
            return nil
        }
        guard intervals.allSatisfy({ $0 >= lower && $0 <= upper }) else {
            return nil
        }
        return cadence
    }

    /// Returns the mean amount when amounts are consistent (each within `recurringAmountTolerance`
    /// of the mean), otherwise `nil`.
    private static func consistentMeanAmount(_ amounts: [Decimal]) -> Decimal? {
        guard !amounts.isEmpty else {
            return nil
        }
        let sum = amounts.reduce(Decimal(0), +)
        let mean = sum / Decimal(amounts.count)
        let meanDouble = (mean as NSDecimalNumber).doubleValue
        guard meanDouble > 0 else {
            return nil
        }

        let allConsistent = amounts.allSatisfy { amount in
            let value = (amount as NSDecimalNumber).doubleValue
            return abs(value - meanDouble) <= recurringAmountTolerance * meanDouble
        }
        return allConsistent ? mean : nil
    }
}
