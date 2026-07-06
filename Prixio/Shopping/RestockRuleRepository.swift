import Foundation
import SwiftData

/// Persists the user's restock-suggestion decisions (`RestockRule`). Mirrors
/// `ShoppingListRepository`'s commit/rollback discipline so a failed save never
/// leaves a half-applied rule in the context.
@MainActor
struct RestockRuleRepository {
    let context: ModelContext

    /// Persistence hook, overridable in tests to exercise the save-failure path.
    var persist: (ModelContext) throws -> Void = { try $0.save() }

    private func commit() throws {
        do {
            try persist(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Records that this item shouldn't be suggested for restock ("we don't buy it
    /// on a schedule"). Upserts on the item key so repeated dismissals never create
    /// duplicate rules, and a previously confirmed rule flips to dismissed.
    func dismiss(itemKey: String, displayName: String) throws {
        if let existing = try fetchRule(itemKey: itemKey) {
            existing.status = .dismissed
        } else {
            context.insert(RestockRule(itemKey: itemKey, displayName: displayName, status: .dismissed))
        }
        try commit()
    }

    private func fetchRule(itemKey: String) throws -> RestockRule? {
        let key = itemKey
        var descriptor = FetchDescriptor<RestockRule>(
            predicate: #Predicate { $0.itemKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
