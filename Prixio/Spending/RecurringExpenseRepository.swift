import Foundation
import SwiftData

@MainActor
struct RecurringExpenseRepository {
    let context: ModelContext

    /// Persistence hook, overridable in tests to exercise the save-failure path. Defaults to the real
    /// `ModelContext.save()`. Mirrors `ReceiptLinePromoter.persist`.
    var persist: (ModelContext) throws -> Void = { try $0.save() }

    /// Commits pending changes, rolling back to the last saved state if the save fails so a failed
    /// resolve/delete never leaves a half-applied change (an orphan rule, a cleared back-link without
    /// the delete) in the context. Rethrows so the caller can surface the error to the user.
    private func commit() throws {
        do {
            try persist(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func fetchAll() throws -> [RecurringExpenseRule] {
        try context.fetch(
            FetchDescriptor<RecurringExpenseRule>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    /// Records the user's response to a recurring suggestion as a durable rule. Confirming creates a
    /// confirmed rule and tags the matching expenses (so the rule links back to its history);
    /// dismissing creates a dismissed rule so the same pattern is not suggested again.
    @discardableResult
    func resolve(
        suggestion: RecurringSuggestion,
        status: RecurringRuleStatus,
        expenses: [ExpenseEntry] = [],
        now: Date = .now
    ) throws -> RecurringExpenseRule {
        let rule = RecurringExpenseRule(
            matchKey: suggestion.matchKey,
            displayLabel: suggestion.displayLabel,
            cadence: suggestion.cadence,
            expectedAmount: suggestion.averageAmount,
            status: status,
            lastMatchedAt: status == .confirmed ? now : nil
        )
        context.insert(rule)

        if status == .confirmed {
            for expense in expenses where SpendingInsightEngine.matchKey(for: expense) == rule.matchKey {
                expense.recurringRuleID = rule.id
            }
        }

        try commit()
        return rule
    }

    /// Recomputes each confirmed rule's expected amount (the mean of its current matching expenses)
    /// and last-matched date, so the displayed figure tracks reality instead of staying frozen at
    /// confirm time. Only writes when a value actually changes, to avoid redundant saves and view
    /// churn (and so it is safe to call on every recompute).
    func refreshConfirmedRules(_ rules: [RecurringExpenseRule], expenses: [ExpenseEntry]) throws {
        var didChange = false
        for rule in rules where rule.status == .confirmed {
            let matches = expenses.filter { SpendingInsightEngine.matchKey(for: $0) == rule.matchKey }
            guard !matches.isEmpty else {
                continue
            }
            let mean = matches.reduce(Decimal(0)) { $0 + $1.amount } / Decimal(matches.count)
            let latest = matches.map(\.date).max()
            if rule.expectedAmount != mean {
                rule.expectedAmount = mean
                didChange = true
            }
            if rule.lastMatchedAt != latest {
                rule.lastMatchedAt = latest
                didChange = true
            }
        }
        if didChange {
            try commit()
        }
    }

    /// Removes a confirmed/dismissed rule, clearing the back-link on any expenses it tagged. Deleting
    /// a confirmed rule lets the pattern be suggested again.
    func delete(_ rule: RecurringExpenseRule, expenses: [ExpenseEntry] = []) throws {
        for expense in expenses where expense.recurringRuleID == rule.id {
            expense.recurringRuleID = nil
        }
        context.delete(rule)
        try commit()
    }
}
