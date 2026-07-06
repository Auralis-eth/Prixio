import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct RestockSuggestionsTests {
    /// Fixed "today" so due/overdue math is deterministic regardless of when tests run.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self, RestockRule.self,
                ShoppingList.self, ShoppingListItem.self, PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func day(_ offset: Int) -> Date {
        let today = Calendar.current.startOfDay(for: now)
        return Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    private func line(_ name: String) -> ReceiptLineItem {
        ReceiptLineItem(
            lineText: name,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name)
        )
    }

    private func receipt(daysAgo: Int, lines: [ReceiptLineItem]) -> ReceiptCapture {
        ReceiptCapture(
            capturedAt: day(-daysAgo),
            purchaseDate: day(-daysAgo),
            reviewState: .reviewed,
            lineItems: lines
        )
    }

    /// Weekly purchases whose next buy is due today — always yields a suggestion.
    private func dueWeeklyReceipts(names: [String]) -> [ReceiptCapture] {
        [21, 14, 7].map { daysAgo in
            receipt(daysAgo: daysAgo, lines: names.map(line))
        }
    }

    private func makeEntry(item: String, capturedAt: Date) -> PriceEntry {
        PriceEntry(
            capturedAt: capturedAt,
            itemNameRaw: item,
            itemNameNormalized: ItemKeyNormalizer.normalize(item),
            priceValue: Decimal(4),
            unitType: .each,
            photoAssetId: "test"
        )
    }

    // MARK: - Repository

    @Test
    func dismissUpsertsASingleDismissedRule() throws {
        let context = try makeContext()
        let repository = RestockRuleRepository(context: context)

        try repository.dismiss(itemKey: "milk", displayName: "Milk")
        try repository.dismiss(itemKey: "milk", displayName: "Milk")

        let rules = try context.fetch(FetchDescriptor<RestockRule>())
        #expect(rules.count == 1)
        #expect(rules.first?.status == .dismissed)
    }

    @Test
    func dismissFlipsAConfirmedRule() throws {
        let context = try makeContext()
        context.insert(RestockRule(itemKey: "milk", displayName: "Milk", status: .confirmed))
        try context.save()

        try RestockRuleRepository(context: context).dismiss(itemKey: "milk", displayName: "Milk")

        let rules = try context.fetch(FetchDescriptor<RestockRule>())
        #expect(rules.count == 1)
        #expect(rules.first?.status == .dismissed)
    }

    // MARK: - View model plumbing

    @Test
    func dueReceiptCadenceSurfacesARestockSuggestion() throws {
        let context = try makeContext()
        let receipts = dueWeeklyReceipts(names: ["Milk"])
        receipts.forEach(context.insert)
        try context.save()

        let viewModel = ShoppingListViewModel()
        viewModel.recompute(items: [], entries: [], receipts: receipts, userLocation: nil, now: now)

        #expect(viewModel.restockSuggestions.map(\.cadence.itemKey) == ["milk"])
        #expect(viewModel.restockSuggestions.first?.urgency == .dueSoon(daysRemaining: 0))
    }

    @Test
    func itemAlreadyOnListSuppressesItsSuggestionAcrossRollup() throws {
        let context = try makeContext()
        // Receipt history for the specific product; the list holds the generic word.
        let receipts = dueWeeklyReceipts(names: ["2% Milk"])
        receipts.forEach(context.insert)
        let listItem = ShoppingListItem(itemKey: "milk", displayName: "Milk", isDone: true)
        context.insert(listItem)
        try context.save()

        let viewModel = ShoppingListViewModel()
        viewModel.recompute(items: [listItem], entries: [], receipts: receipts, userLocation: nil, now: now)

        #expect(viewModel.restockSuggestions.isEmpty)
    }

    @Test
    func dismissedRuleSuppressesSuggestionThroughTheViewModel() throws {
        let context = try makeContext()
        let receipts = dueWeeklyReceipts(names: ["Milk"])
        receipts.forEach(context.insert)
        let rule = RestockRule(itemKey: "milk", displayName: "Milk", status: .dismissed)
        context.insert(rule)
        try context.save()

        let viewModel = ShoppingListViewModel()
        viewModel.recompute(
            items: [],
            entries: [],
            receipts: receipts,
            restockRules: [rule],
            userLocation: nil,
            now: now
        )

        #expect(viewModel.restockSuggestions.isEmpty)
    }

    @Test
    func restockSectionIsCappedToStayANudge() throws {
        let context = try makeContext()
        let receipts = dueWeeklyReceipts(names: ["Apples", "Bananas", "Carrots", "Dates"])
        receipts.forEach(context.insert)
        try context.save()

        let viewModel = ShoppingListViewModel()
        viewModel.recompute(items: [], entries: [], receipts: receipts, userLocation: nil, now: now)

        #expect(viewModel.restockSuggestions.count == ShoppingListViewModel.maxRestockSuggestions)
    }

    @Test
    func receiptEvidenceOutranksCaptureRhythmForTheSameItem() throws {
        let context = try makeContext()
        // The same item has both a capture rhythm (PriceEntry) and a purchase
        // rhythm (receipts): it must appear once, in the restock section only.
        let entries = [21, 14, 7].map { makeEntry(item: "Milk", capturedAt: day(-$0)) }
        entries.forEach(context.insert)
        let receipts = dueWeeklyReceipts(names: ["Milk"])
        receipts.forEach(context.insert)
        try context.save()

        let viewModel = ShoppingListViewModel()
        viewModel.recompute(items: [], entries: entries, receipts: receipts, userLocation: nil, now: now)

        #expect(viewModel.restockSuggestions.map(\.cadence.itemKey) == ["milk"])
        #expect(viewModel.listAdditionSuggestions.isEmpty)
    }

    @Test
    func captureRhythmStillSurfacesWhenNoReceiptEvidenceExists() throws {
        let context = try makeContext()
        let entries = [21, 14, 7].map { makeEntry(item: "Milk", capturedAt: day(-$0)) }
        entries.forEach(context.insert)
        try context.save()

        let viewModel = ShoppingListViewModel()
        viewModel.recompute(items: [], entries: entries, receipts: [], userLocation: nil, now: now)

        #expect(viewModel.restockSuggestions.isEmpty)
        #expect(viewModel.listAdditionSuggestions.map(\.itemKey) == ["milk"])
    }
}
