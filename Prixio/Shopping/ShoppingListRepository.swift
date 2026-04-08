import Foundation
import SwiftData

@MainActor
struct ShoppingListRepository {
    static let defaultListName = "This trip"

    let context: ModelContext

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
        try context.save()
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
        try context.save()
        return item
    }

    func deleteItem(_ item: ShoppingListItem) throws {
        item.list?.updatedAt = .now
        context.delete(item)
        try context.save()
    }

    func setDone(_ isDone: Bool, for item: ShoppingListItem) throws {
        item.isDone = isDone
        item.doneAt = isDone ? .now : nil
        item.list?.updatedAt = .now
        try context.save()
    }

    func clearCompletedItems(in list: ShoppingList) throws {
        for item in list.items where item.isDone {
            context.delete(item)
        }
        list.updatedAt = .now
        try context.save()
    }
}
