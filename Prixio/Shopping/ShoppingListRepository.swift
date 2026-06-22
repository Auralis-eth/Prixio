import Foundation
import SwiftData

@MainActor
struct ShoppingListRepository {
    static let defaultListName = "This trip"

    let context: ModelContext

    /// Persistence hook, overridable in tests to exercise the save-failure path. Defaults to the real
    /// `ModelContext.save()`. Mirrors `ReceiptLinePromoter.persist`.
    var persist: (ModelContext) throws -> Void = { try $0.save() }

    /// Commits pending changes, rolling back to the last saved state if the save fails so a failed
    /// mutation never leaves a half-applied insert/delete in the context. Rethrows so the caller can
    /// surface the error to the user.
    private func commit() throws {
        do {
            try persist(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func fetchLists() throws -> [ShoppingList] {
        try context.fetch(
            FetchDescriptor<ShoppingList>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )
    }

    func fetchOrCreateDefaultList() throws -> ShoppingList {
        let listName = Self.defaultListName
        let descriptor = FetchDescriptor<ShoppingList>(
            predicate: #Predicate<ShoppingList> {
                $0.name == listName && $0.isArchived == false
            }
        )

        if let existingList = try context.fetch(descriptor).first {
            return existingList
        }

        let list = ShoppingList(name: Self.defaultListName)
        context.insert(list)
        try commit()
        return list
    }

    func addItem(
        to list: ShoppingList,
        displayName: String,
        quantityNote: String? = nil
    ) throws -> ShoppingListItem {
        let item = ShoppingListItem(
            itemKey: ItemKeyNormalizer.normalize(displayName),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            quantityNote: quantityNote?.trimmingCharacters(in: .whitespacesAndNewlines),
            list: list
        )
        list.items.append(item)
        list.updatedAt = .now
        context.insert(item)
        try commit()
        return item
    }

    func deleteItem(_ item: ShoppingListItem) throws {
        item.list?.updatedAt = .now
        context.delete(item)
        try commit()
    }

    func setDone(_ isDone: Bool, for item: ShoppingListItem) throws {
        item.isDone = isDone
        item.doneAt = isDone ? .now : nil
        item.list?.updatedAt = .now
        try commit()
    }

    func clearCompletedItems(in list: ShoppingList) throws {
        for item in list.items where item.isDone {
            context.delete(item)
        }
        list.updatedAt = .now
        try commit()
    }
}
