import Foundation
import SwiftData
import Testing
@testable import Prixio

@MainActor
struct ShoppingListViewModelTests {
    @Test
    func repositoryCreatesDefaultListAutomatically() throws {
        let container = try ModelContainer(
            for: PriceEntry.self,
                StoreChain.self,
                StoreLocation.self,
                ShoppingList.self,
                ShoppingListItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let repository = ShoppingListRepository(context: context)

        let list = try repository.fetchOrCreateDefaultList()

        #expect(list.name == ShoppingListRepository.defaultListName)
        #expect(try context.fetch(FetchDescriptor<ShoppingList>()).count == 1)
    }

    @Test
    func repositoryAddsAndDeletesItems() throws {
        let container = try ModelContainer(
            for: PriceEntry.self,
                StoreChain.self,
                StoreLocation.self,
                ShoppingList.self,
                ShoppingListItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let repository = ShoppingListRepository(context: context)
        let list = try repository.fetchOrCreateDefaultList()

        let item = try repository.addItem(to: list, displayName: "Milk")
        #expect(list.items.count == 1)

        try repository.deleteItem(item)
        #expect(try context.fetch(FetchDescriptor<ShoppingListItem>()).isEmpty)
    }

    @Test
    func activeAndCompletedRowsSplitCorrectly() {
        let viewModel = ShoppingListViewModel()
        let activeItem = ShoppingListItem(itemKey: "milk", displayName: "Milk", isDone: false)
        let completedItem = ShoppingListItem(itemKey: "eggs", displayName: "Eggs", isDone: true)

        viewModel.recompute(items: [activeItem, completedItem], entries: [], userLocation: nil)

        #expect(viewModel.activeRows.map(\.displayName) == ["Milk"])
        #expect(viewModel.completedRows.map(\.displayName) == ["Eggs"])
    }

    @Test
    func rowsWithNoSuggestionsStillAppear() {
        let viewModel = ShoppingListViewModel()
        let item = ShoppingListItem(itemKey: "milk", displayName: "Milk")

        viewModel.recompute(items: [item], entries: [], userLocation: nil)

        #expect(viewModel.activeRows.count == 1)
        #expect(viewModel.activeRows.first?.displayName == "Milk")
    }

    @Test
    func missingSuggestionRequestsNudge() {
        let viewModel = ShoppingListViewModel()
        let item = ShoppingListItem(itemKey: "milk", displayName: "Milk")

        viewModel.recompute(items: [item], entries: [], userLocation: nil)

        #expect(viewModel.activeRows.first?.shouldNudgeForFreshness == true)
    }

    @Test
    func staleSuggestionRequestsNudge() {
        let viewModel = ShoppingListViewModel()
        let now = Date(timeIntervalSince1970: 6_000_000)
        let item = ShoppingListItem(itemKey: "milk", displayName: "Milk")
        let entries = [
            makeEntry(item: "milk", chainName: "Co-op", price: "4.00", capturedAt: now.addingTimeInterval(-45 * 86_400))
        ]

        viewModel.recompute(items: [item], entries: entries, userLocation: nil, now: now)

        #expect(viewModel.activeRows.first?.shouldNudgeForFreshness == true)
    }

    @Test
    func freshSuggestionDoesNotRequestNudge() {
        let viewModel = ShoppingListViewModel()
        let now = Date(timeIntervalSince1970: 7_000_000)
        let item = ShoppingListItem(itemKey: "milk", displayName: "Milk")
        let entries = [
            makeEntry(item: "milk", chainName: "Co-op", price: "4.00", capturedAt: now.addingTimeInterval(-2 * 86_400))
        ]

        viewModel.recompute(items: [item], entries: entries, userLocation: nil, now: now)

        #expect(viewModel.activeRows.first?.shouldNudgeForFreshness == false)
    }

    private func makeEntry(item: String, chainName: String, price: String, capturedAt: Date) -> PriceEntry {
        PriceEntry(
            capturedAt: capturedAt,
            itemNameRaw: item.capitalized,
            itemNameNormalized: item,
            priceValue: Decimal(string: price)!,
            unitType: .each,
            unitQuantityValue: nil,
            normalizedUnitPriceValue: Decimal(string: price)!,
            normalizedUnitType: .each,
            storeChainId: nil,
            storeLocationId: nil,
            storeChainNameSnapshot: chainName,
            storeLocationNameSnapshot: nil,
            photoAssetId: ""
        )
    }
}
