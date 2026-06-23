import Foundation
import SwiftData
import Testing
@testable import Prixio

@MainActor
@Suite(.serialized)
struct ShoppingListRepositoryTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ShoppingList.self, ShoppingListItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func date(_ daysFromEpoch: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(daysFromEpoch) * 86_400)
    }

    @Test
    func fetchOrCreateDefaultList_returnsExistingActiveDefaultList() throws {
        let context = try makeContext()
        let existing = ShoppingList(name: ShoppingListRepository.defaultListName)
        context.insert(existing)
        try context.save()
        let repository = ShoppingListRepository(context: context)

        let list = try repository.fetchOrCreateDefaultList()

        #expect(list.id == existing.id)
        #expect(try context.fetch(FetchDescriptor<ShoppingList>()).count == 1)
    }

    @Test
    func fetchOrCreateDefaultList_ignoresArchivedDefaultListAndCreatesActiveList() throws {
        let context = try makeContext()
        let archived = ShoppingList(name: ShoppingListRepository.defaultListName, isArchived: true)
        context.insert(archived)
        try context.save()
        let repository = ShoppingListRepository(context: context)

        let active = try repository.fetchOrCreateDefaultList()
        let lists = try context.fetch(FetchDescriptor<ShoppingList>())

        #expect(active.id != archived.id)
        #expect(active.isArchived == false)
        #expect(lists.count == 2)
    }

    @Test
    func fetchLists_returnsNewestUpdatedListsFirst() throws {
        let context = try makeContext()
        context.insert(ShoppingList(name: "Old", updatedAt: date(1)))
        context.insert(ShoppingList(name: "New", updatedAt: date(3)))
        context.insert(ShoppingList(name: "Middle", updatedAt: date(2)))
        try context.save()
        let repository = ShoppingListRepository(context: context)

        let lists = try repository.fetchLists()

        #expect(lists.map(\.name) == ["New", "Middle", "Old"])
    }

    @Test
    func addItem_trimsDisplayNameAndQuantityAndNormalizesItemKey() throws {
        let repository = ShoppingListRepository(context: try makeContext())
        let list = try repository.fetchOrCreateDefaultList()

        let item = try repository.addItem(to: list, displayName: "  Organic Milk  ", quantityNote: "  2 bags  ")

        #expect(item.displayName == "Organic Milk")
        #expect(item.quantityNote == "2 bags")
        #expect(item.itemKey == ItemKeyNormalizer.normalize("Organic Milk"))
        #expect(item.list?.id == list.id)
        #expect(list.items.map(\.id).contains(item.id))
    }

    @Test
    func addItem_keepsEmptyQuantityAsEmptyString_givenWhitespaceQuantity() throws {
        let repository = ShoppingListRepository(context: try makeContext())
        let list = try repository.fetchOrCreateDefaultList()

        let item = try repository.addItem(to: list, displayName: "Bread", quantityNote: "   ")

        #expect(item.quantityNote == "")
    }

    @Test
    func setDone_setsDoneAtWhenDoneAndClearsDoneAtWhenReopened() throws {
        let repository = ShoppingListRepository(context: try makeContext())
        let list = try repository.fetchOrCreateDefaultList()
        let item = try repository.addItem(to: list, displayName: "Eggs")

        try repository.setDone(true, for: item)
        let doneAt = item.doneAt
        try repository.setDone(false, for: item)

        #expect(doneAt != nil)
        #expect(item.isDone == false)
        #expect(item.doneAt == nil)
    }

    @Test
    func deleteItem_removesItemAndDetachesFromList() throws {
        let context = try makeContext()
        let repository = ShoppingListRepository(context: context)
        let list = try repository.fetchOrCreateDefaultList()
        let item = try repository.addItem(to: list, displayName: "Milk")

        try repository.deleteItem(item)
        let items = try context.fetch(FetchDescriptor<ShoppingListItem>())

        #expect(items.isEmpty)
        #expect(list.items.isEmpty)
    }

    @Test
    func clearCompletedItems_deletesOnlyCompletedItems() throws {
        let context = try makeContext()
        let repository = ShoppingListRepository(context: context)
        let list = try repository.fetchOrCreateDefaultList()
        let active = try repository.addItem(to: list, displayName: "Milk")
        let completed = try repository.addItem(to: list, displayName: "Eggs")
        try repository.setDone(true, for: completed)

        try repository.clearCompletedItems(in: list)
        let items = try context.fetch(FetchDescriptor<ShoppingListItem>())

        #expect(items.map(\.id) == [active.id])
        #expect(list.items.allSatisfy { !$0.isDone })
    }
}
