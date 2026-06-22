import Foundation
import SwiftData

@MainActor
struct IncomeRepository {
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

    func fetchAll() throws -> [IncomeEntry] {
        try context.fetch(
            FetchDescriptor<IncomeEntry>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    @discardableResult
    func add(amount: Decimal, label: String, date: Date) throws -> IncomeEntry {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let income = IncomeEntry(
            date: date,
            amount: amount,
            label: trimmedLabel.isEmpty ? "Income" : trimmedLabel
        )
        context.insert(income)
        try commit()
        return income
    }

    func delete(_ income: IncomeEntry) throws {
        context.delete(income)
        try commit()
    }
}
