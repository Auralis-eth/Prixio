import SwiftData
import SwiftUI

struct SpendingRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseEntry.date, order: .reverse) private var expenses: [ExpenseEntry]
    @Query(sort: \IncomeEntry.date, order: .reverse) private var income: [IncomeEntry]
    @Query(sort: \ReceiptCapture.capturedAt, order: .reverse) private var receipts: [ReceiptCapture]
    @Query(sort: \RecurringExpenseRule.createdAt, order: .reverse) private var rules: [RecurringExpenseRule]

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = SpendingViewModel()
    @State private var isShowingAddExpense = false
    @State private var isShowingAddIncome = false
    @State private var selectedReceipt: ReceiptCapture?

    /// Set when a spending mutation fails to persist, surfaced as an alert so an add/delete/resolve that
    /// didn't actually save can't silently feed wrong budget/spending conclusions.
    @State private var saveErrorMessage: String?

    /// Confirmed recurring rules, newest first.
    private var confirmedRules: [RecurringExpenseRule] {
        rules.filter { $0.status == .confirmed }
    }

    /// The month the screen summarizes. Refreshed on appear and when the app returns to the foreground
    /// so a session left running (or backgrounded) across a month boundary doesn't keep headlining and
    /// filtering the previous month. `@State`, not a stored `let`, because the view identity persists
    /// across re-renders and a `let` would freeze the value at first init.
    @State private var month = MonthBucket.start(of: .now)

    /// A content fingerprint of the queried data so the spending picture recomputes on *edits*, not
    /// just insertions/deletions. `@Query` re-renders the view when any tracked `@Model` field changes,
    /// and this signature changes with it — catching a receipt being reviewed/recategorized, an amount
    /// corrected, or a rule's status flipping, none of which change array counts.
    private var spendingSignature: Int {
        var hasher = Hasher()
        for expense in expenses {
            hasher.combine(expense.id)
            hasher.combine(expense.amount)
            hasher.combine(expense.date)
            hasher.combine(expense.category)
            hasher.combine(expense.currencyCode)
            hasher.combine(expense.recurringRuleID)
        }
        for entry in income {
            hasher.combine(entry.id)
            hasher.combine(entry.amount)
            hasher.combine(entry.date)
            hasher.combine(entry.currencyCode)
        }
        for receipt in receipts {
            hasher.combine(receipt.id)
            hasher.combine(receipt.total)
            hasher.combine(receipt.reviewState)
            hasher.combine(receipt.category)
            hasher.combine(receipt.currencyCode)
            hasher.combine(receipt.purchaseDate)
        }
        for rule in rules {
            hasher.combine(rule.id)
            hasher.combine(rule.status)
            hasher.combine(rule.expectedAmount)
        }
        return hasher.finalize()
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection

                if viewModel.trend.contains(where: { $0.spending > 0 || $0.income > 0 }) {
                    Section("Spend over time") {
                        SpendingTrendChart(trend: viewModel.trend)
                    }
                }

                if !viewModel.anomalies.isEmpty {
                    Section("Unusual this month") {
                        ForEach(viewModel.anomalies) { anomaly in
                            anomalyRow(anomaly)
                        }
                    }
                }

                if !viewModel.storeShares.isEmpty {
                    Section("Where spending goes") {
                        ForEach(viewModel.storeShares) { share in
                            storeShareRow(share)
                        }
                    }
                }

                if !viewModel.suggestions.isEmpty {
                    Section("Recurring patterns") {
                        ForEach(viewModel.suggestions) { suggestion in
                            RecurringSuggestionCard(
                                suggestion: suggestion,
                                onConfirm: { resolve(suggestion, status: .confirmed) },
                                onDismiss: { resolve(suggestion, status: .dismissed) }
                            )
                        }
                    }
                }

                confirmedRecurringSection

                expensesSection
                incomeSection
                receiptsSection
            }
            .navigationTitle("Spending")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingAddExpense = true
                        } label: {
                            Label("Add Expense", systemImage: "minus.circle")
                        }
                        Button {
                            isShowingAddIncome = true
                        } label: {
                            Label("Add Income", systemImage: "plus.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task { refreshMonth(); recompute() }
        .onChange(of: spendingSignature) { _, _ in recompute() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshMonth()
            recompute()
        }
        .sheet(isPresented: $isShowingAddExpense) {
            AddExpenseSheet { amount, category, merchant, note, date in
                addExpense(amount: amount, category: category, merchant: merchant, note: note, date: date)
            }
        }
        .sheet(isPresented: $isShowingAddIncome) {
            AddIncomeSheet { amount, label, date in
                addIncome(amount: amount, label: label, date: date)
            }
        }
        .sheet(item: $selectedReceipt) { receipt in
            ReceiptReviewView(
                viewModel: ReceiptReviewViewModel(capture: receipt, context: modelContext),
                onClose: {
                    selectedReceipt = nil
                    recompute()
                }
            )
        }
        .alert(
            "Couldn’t Save",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            ),
            presenting: saveErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var summarySection: some View {
        Section(MonthBucket.displayName(for: month)) {
            summaryRow(title: "Income", value: viewModel.summary.incomeTotal)
            summaryRow(title: "Groceries", value: viewModel.summary.groceriesTotal)
            summaryRow(title: "Bills", value: viewModel.summary.billsTotal)
            summaryRow(title: "Subscriptions", value: viewModel.summary.subscriptionsTotal)
            HStack {
                Text("Net")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(CurrencyFormatter.shared.display(viewModel.summary.net))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(viewModel.summary.net < 0 ? .red : .primary)
            }

            budgetPressureRow
        }
    }

    private var budgetPressureRow: some View {
        let pressure = viewModel.budgetPressure
        return HStack {
            Label(pressure.level.displayName, systemImage: pressure.level.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(budgetPressureTint(pressure.level))
            Spacer()
            if let ratio = pressure.ratio {
                Text("\(Int((ratio * 100).rounded()))% of income")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func budgetPressureTint(_ level: BudgetPressureLevel) -> Color {
        switch level {
        case .comfortable:
            return .green
        case .tight:
            return .orange
        case .over:
            return .red
        case .noIncomeData:
            return .secondary
        }
    }

    private func anomalyRow(_ anomaly: SpendingAnomaly) -> some View {
        HStack {
            Label(anomaly.category.displayName, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.shared.display(anomaly.currentTotal))
                    .monospacedDigit()
                Text("+\(Int((anomaly.deltaFraction * 100).rounded()))% vs usual \(CurrencyFormatter.shared.display(anomaly.baselineAverage))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func storeShareRow(_ share: StoreShare) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(share.storeName)
                    .font(.subheadline)
                Spacer()
                Text("\(CurrencyFormatter.shared.display(share.total)) · \(Int((share.fraction * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: min(max(share.fraction, 0), 1))
                .tint(.accentColor)
        }
    }

    private func summaryRow(title: String, value: Decimal) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(CurrencyFormatter.shared.display(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var expensesSection: some View {
        if viewModel.monthExpenses.isEmpty {
            Section {
                ContentUnavailableView(
                    "No expenses yet",
                    systemImage: "creditcard",
                    description: Text("Add a manual expense or income to start tracking household spending.")
                )
            }
        } else {
            Section("Expenses") {
                ForEach(viewModel.monthExpenses) { expense in
                    expenseRow(expense)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                deleteExpense(expense)
                            }
                        }
                }
            }
        }
    }

    private func expenseRow(_ expense: ExpenseEntry) -> some View {
        HStack {
            Label(expense.category.displayName, systemImage: expense.category.systemImage)
                .labelStyle(.titleAndIcon)
            VStack(alignment: .leading) {
                if let merchant = expense.merchant {
                    Text(merchant)
                        .font(.subheadline)
                }
            }
            Spacer()
            Text(CurrencyFormatter.shared.display(expense.amount))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var confirmedRecurringSection: some View {
        if !confirmedRules.isEmpty {
            Section("Confirmed recurring") {
                ForEach(confirmedRules) { rule in
                    confirmedRuleRow(rule)
                        .swipeActions(edge: .trailing) {
                            Button("Remove", role: .destructive) {
                                deleteRule(rule)
                            }
                        }
                }
            }
        }
    }

    private func confirmedRuleRow(_ rule: RecurringExpenseRule) -> some View {
        HStack {
            Label(rule.displayLabel, systemImage: "arrow.triangle.2.circlepath")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(rule.cadence.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let expected = rule.expectedAmount {
                    Text("~\(CurrencyFormatter.shared.display(expected))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var incomeSection: some View {
        if !viewModel.monthIncome.isEmpty {
            Section("Income") {
                ForEach(viewModel.monthIncome) { entry in
                    HStack {
                        Label(entry.label, systemImage: "plus.circle")
                        Spacer()
                        Text(CurrencyFormatter.shared.display(entry.amount))
                            .monospacedDigit()
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            deleteIncome(entry)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var receiptsSection: some View {
        if !viewModel.monthReceipts.isEmpty {
            Section("Receipts") {
                ForEach(viewModel.monthReceipts) { receipt in
                    Button {
                        selectedReceipt = receipt
                    } label: {
                        receiptRow(receipt)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            deleteReceipt(receipt)
                        }
                    }
                }
            }
        }
    }

    private func receiptRow(_ receipt: ReceiptCapture) -> some View {
        let isReviewed = receipt.reviewState == .reviewed
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.storeChainNameSnapshot ?? receipt.storeLocationNameSnapshot ?? "Unknown store")
                    .font(.subheadline)
                HStack(spacing: 6) {
                    Label(receipt.category.displayName, systemImage: receipt.category.systemImage)
                        .labelStyle(.titleAndIcon)
                    Text("·")
                    Text((receipt.purchaseDate ?? receipt.capturedAt).formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let total = receipt.total {
                    Text(CurrencyFormatter.shared.display(total))
                        .monospacedDigit()
                }
                Label(isReviewed ? "Reviewed" : "Needs review", systemImage: isReviewed ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption2)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(isReviewed ? Color.secondary : Color.orange)
            }
        }
    }

    /// Advances `month` to the current month if the calendar has rolled over since it was last set.
    private func refreshMonth() {
        let current = MonthBucket.start(of: .now)
        if current != month {
            month = current
        }
    }

    private func recompute() {
        // Keep confirmed rules' expected amount / last-matched date current as new expenses arrive.
        try? RecurringExpenseRepository(context: modelContext).refreshConfirmedRules(rules, expenses: expenses)
        viewModel.recompute(
            month: month,
            expenses: expenses,
            income: income,
            receipts: receipts,
            rules: rules
        )
    }

    private func addExpense(
        amount: Decimal,
        category: ExpenseCategory,
        merchant: String?,
        note: String?,
        date: Date
    ) {
        // Tag the new expense if it matches a confirmed recurring rule.
        let matchKey = SpendingInsightEngine.matchKey(merchant: merchant, category: category)
        let ruleID = confirmedRules.first { $0.matchKey == matchKey }?.id
        do {
            _ = try ExpenseRepository(context: modelContext).add(
                amount: amount,
                category: category,
                merchant: merchant,
                note: note,
                date: date,
                recurringRuleID: ruleID
            )
        } catch {
            saveErrorMessage = "Couldn’t save this expense. Please try again."
        }
        recompute()
    }

    private func addIncome(amount: Decimal, label: String, date: Date) {
        do {
            _ = try IncomeRepository(context: modelContext).add(amount: amount, label: label, date: date)
        } catch {
            saveErrorMessage = "Couldn’t save this income. Please try again."
        }
        recompute()
    }

    private func deleteExpense(_ expense: ExpenseEntry) {
        do {
            try ExpenseRepository(context: modelContext).delete(expense)
        } catch {
            saveErrorMessage = "Couldn’t delete this expense. Please try again."
        }
        recompute()
    }

    private func deleteIncome(_ income: IncomeEntry) {
        do {
            try IncomeRepository(context: modelContext).delete(income)
        } catch {
            saveErrorMessage = "Couldn’t delete this income. Please try again."
        }
        recompute()
    }

    private func deleteReceipt(_ receipt: ReceiptCapture) {
        do {
            modelContext.delete(receipt)
            try modelContext.save()
        } catch {
            // Roll back the pending delete so the receipt doesn't vanish from the list while still
            // persisted, and tell the user instead of swallowing the failure.
            modelContext.rollback()
            saveErrorMessage = "Couldn’t delete this receipt. Please try again."
        }
        recompute()
    }

    private func deleteRule(_ rule: RecurringExpenseRule) {
        do {
            try RecurringExpenseRepository(context: modelContext).delete(rule, expenses: expenses)
        } catch {
            saveErrorMessage = "Couldn’t remove this recurring rule. Please try again."
        }
        recompute()
    }

    private func resolve(_ suggestion: RecurringSuggestion, status: RecurringRuleStatus) {
        do {
            _ = try RecurringExpenseRepository(context: modelContext).resolve(
                suggestion: suggestion,
                status: status,
                expenses: expenses
            )
        } catch {
            saveErrorMessage = "Couldn’t save your choice. Please try again."
        }
        recompute()
    }
}
