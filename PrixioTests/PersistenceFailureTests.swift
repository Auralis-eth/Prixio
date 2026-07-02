import Foundation
import SwiftData
import Testing
@testable import Prixio

/// Coverage for the persistence-failure handling added to the shopping, spending, and compare
/// mutation paths. Each repository routes its `context.save()` through an injectable `persist` seam
/// and a `commit()` that rolls back on failure, so a failed add/delete/toggle can no longer leave a
/// half-applied change in the context (which the SwiftUI views would then render as if it had worked).
///
/// Every test seeds state with a real save, then swaps in a throwing `persist` seam to drive the
/// failure path, and asserts both that the error propagates (so the view can surface an alert) and
/// that the data is left intact by the rollback.
///
/// Serialized: each test spins up its own in-memory `ModelContainer`, and running several with
/// overlapping `@Model` types concurrently can abort under SwiftData on the current OS beta. These
/// tests are fast and self-contained, so serial execution costs nothing and removes the flake.
@Suite(.serialized)
struct PersistenceFailureTests {
    private struct SaveFailure: Error {}
    private let throwingPersist: (ModelContext) throws -> Void = { _ in throw SaveFailure() }

    // MARK: - Shopping

    @MainActor
    private func makeShoppingContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ShoppingList.self, ShoppingListItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test(.tags(.simulatorCrash), .disabled("Crashes test host (signal abrt) on iOS 27 beta simulator even in isolation; recheck after next beta"))
    @MainActor
    func shoppingAddItem_throwsAndPersistsNothing_whenSaveFails() throws {
        let context = try makeShoppingContext()
        let list = ShoppingList(name: "This trip")
        context.insert(list)
        try context.save()

        var repository = ShoppingListRepository(context: context)
        repository.persist = throwingPersist

        #expect(throws: SaveFailure.self) {
            _ = try repository.addItem(to: list, displayName: "Milk", quantityNote: nil)
        }

        // Rollback undid the insert and the relationship append — nothing leaked into the store.
        #expect(try context.fetch(FetchDescriptor<ShoppingListItem>()).isEmpty)
        #expect(list.items.isEmpty)
    }

    @Test
    @MainActor
    func shoppingDeleteItem_throwsAndKeepsItem_whenSaveFails() throws {
        let context = try makeShoppingContext()
        let list = ShoppingList(name: "This trip")
        context.insert(list)
        let item = try ShoppingListRepository(context: context).addItem(
            to: list, displayName: "Milk", quantityNote: nil
        )

        var failing = ShoppingListRepository(context: context)
        failing.persist = throwingPersist

        #expect(throws: SaveFailure.self) {
            try failing.deleteItem(item)
        }

        // Rollback restored the pending delete: the item is still there.
        #expect(try context.fetch(FetchDescriptor<ShoppingListItem>()).count == 1)
    }

    @Test
    @MainActor
    func shoppingSetDone_throwsAndRevertsFlag_whenSaveFails() throws {
        let context = try makeShoppingContext()
        let list = ShoppingList(name: "This trip")
        context.insert(list)
        let item = try ShoppingListRepository(context: context).addItem(
            to: list, displayName: "Milk", quantityNote: nil
        )
        #expect(item.isDone == false)

        var failing = ShoppingListRepository(context: context)
        failing.persist = throwingPersist

        #expect(throws: SaveFailure.self) {
            try failing.setDone(true, for: item)
        }

        // The in-memory mutation is rolled back to the last saved state.
        #expect(item.isDone == false)
        #expect(item.doneAt == nil)
    }

    // MARK: - Spending

    @MainActor
    private func makeSpendingContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ExpenseEntry.self, IncomeEntry.self, RecurringExpenseRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test
    @MainActor
    func expenseAdd_throwsAndPersistsNothing_whenSaveFails() throws {
        let context = try makeSpendingContext()
        var failing = ExpenseRepository(context: context)
        failing.persist = throwingPersist

        #expect(throws: SaveFailure.self) {
            _ = try failing.add(amount: 42, category: .utilities, merchant: "Hydro", note: nil, date: .now)
        }

        #expect(try context.fetch(FetchDescriptor<ExpenseEntry>()).isEmpty)
    }

    @Test
    @MainActor
    func expenseDelete_throwsAndKeepsEntry_whenSaveFails() throws {
        let context = try makeSpendingContext()
        let expense = try ExpenseRepository(context: context).add(
            amount: 5, category: .other, merchant: nil, note: nil, date: .now
        )

        var failing = ExpenseRepository(context: context)
        failing.persist = throwingPersist

        #expect(throws: SaveFailure.self) {
            try failing.delete(expense)
        }

        #expect(try context.fetch(FetchDescriptor<ExpenseEntry>()).count == 1)
    }

    @Test
    @MainActor
    func incomeDelete_throwsAndKeepsEntry_whenSaveFails() throws {
        let context = try makeSpendingContext()
        let income = try IncomeRepository(context: context).add(amount: 2000, label: "Pay", date: .now)

        var failing = IncomeRepository(context: context)
        failing.persist = throwingPersist

        #expect(throws: SaveFailure.self) {
            try failing.delete(income)
        }

        #expect(try context.fetch(FetchDescriptor<IncomeEntry>()).count == 1)
    }

    @Test
    @MainActor
    func recurringResolve_throwsAndPersistsNoRule_whenSaveFails() throws {
        let context = try makeSpendingContext()
        var failing = RecurringExpenseRepository(context: context)
        failing.persist = throwingPersist

        let suggestion = RecurringSuggestion(
            matchKey: "merchant:netflix",
            displayLabel: "Netflix",
            cadence: .monthly,
            occurrenceCount: 3,
            averageAmount: Decimal(string: "15")!
        )

        #expect(throws: SaveFailure.self) {
            _ = try failing.resolve(suggestion: suggestion, status: .confirmed, expenses: [])
        }

        #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).isEmpty)
    }

    @Test
    @MainActor
    func recurringDelete_throwsAndKeepsRuleAndBackLink_whenSaveFails() throws {
        let context = try makeSpendingContext()
        let rule = RecurringExpenseRule(matchKey: "merchant:netflix", displayLabel: "Netflix", status: .confirmed)
        context.insert(rule)
        let tagged = ExpenseEntry(amount: 15, category: .subscriptions, merchant: "Netflix", recurringRuleID: rule.id)
        context.insert(tagged)
        try context.save()

        var failing = RecurringExpenseRepository(context: context)
        failing.persist = throwingPersist

        #expect(throws: SaveFailure.self) {
            try failing.delete(rule, expenses: [tagged])
        }

        // Rollback covers the whole unit of work: the rule survives AND the back-link that `delete`
        // clears before removing the rule is restored, so the expense isn't left orphaned.
        #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).count == 1)
        #expect(tagged.recurringRuleID == rule.id)
    }

    // MARK: - Compare (price history)

    @MainActor
    private func makeCompareContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func makePriceEntry(in context: ModelContext) throws -> PriceEntry {
        let entry = PriceEntry(
            capturedAt: .now,
            itemNameRaw: "Milk",
            itemNameNormalized: "milk",
            priceValue: Decimal(string: "4.99")!,
            unitType: .each,
            photoAssetId: ""
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    @Test
    @MainActor
    func priceEntryDelete_removesEntry_onSuccess() throws {
        let context = try makeCompareContext()
        let entry = try makePriceEntry(in: context)

        try PriceEntryRepository(context: context).delete(entry)

        #expect(try context.fetch(FetchDescriptor<PriceEntry>()).isEmpty)
    }

    @Test
    @MainActor
    func priceEntryDelete_throwsAndKeepsEntry_whenSaveFails() throws {
        let context = try makeCompareContext()
        _ = try makePriceEntry(in: context)
        let entry = try context.fetch(FetchDescriptor<PriceEntry>())[0]

        var failing = PriceEntryRepository(context: context)
        failing.persist = throwingPersist

        #expect(throws: SaveFailure.self) {
            try failing.delete(entry)
        }

        // A failed delete must not leave the entry hidden-but-not-deleted: it still feeds price
        // history, basket estimates, and comparisons, so it must remain fetchable.
        #expect(try context.fetch(FetchDescriptor<PriceEntry>()).count == 1)
    }
}
