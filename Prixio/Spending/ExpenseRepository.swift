import Foundation
import SwiftData

@MainActor
struct ExpenseRepository {
    let context: ModelContext

    /// Persistence hook, overridable in tests to exercise the save-failure path. Defaults to the real
    /// `ModelContext.save()`. Mirrors `ReceiptLinePromoter.persist`.
    var persist: (ModelContext) throws -> Void = { try $0.save() }

    /// Commits pending changes, rolling back to the last saved state if the save fails so a failed
    /// add/delete never leaves a half-applied change in the context. Rethrows so the caller can
    /// surface the error to the user.
    private func commit() throws {
        do {
            try persist(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func fetchAll() throws -> [ExpenseEntry] {
        try context.fetch(
            FetchDescriptor<ExpenseEntry>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    @discardableResult
    func add(
        amount: Decimal,
        category: ExpenseCategory,
        merchant: String?,
        note: String?,
        date: Date,
        recurringRuleID: UUID? = nil
    ) throws -> ExpenseEntry {
        let trimmedMerchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expense = ExpenseEntry(
            date: date,
            amount: amount,
            category: category,
            merchant: (trimmedMerchant?.isEmpty ?? true) ? nil : trimmedMerchant,
            note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote,
            recurringRuleID: recurringRuleID
        )
        context.insert(expense)
        try commit()
        return expense
    }

    func delete(_ expense: ExpenseEntry) throws {
        context.delete(expense)
        try commit()
    }
}
