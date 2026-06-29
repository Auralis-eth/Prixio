import Foundation
import Testing
@testable import Prixio

/// Tests for promoting saved `FlyerPriceRecord`s into the Compare item surface as
/// labeled "Flyer price" rows (the promotion step after MVP step 8).
@MainActor
@Suite
struct FlyerComparisonPromotionTests {
    private let viewModel = CompareViewModel()

    private func record(
        _ name: String,
        banner: String = "Safeway",
        price: String,
        regular: String? = nil
    ) -> FlyerPriceRecord {
        FlyerPriceRecord(
            dealKey: "\(banner)|\(ItemKeyNormalizer.normalize(name))|\(price)",
            bannerID: banner.lowercased(),
            bannerName: banner,
            productName: name,
            normalizedItemKey: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            regularPriceValue: regular.flatMap { Decimal(string: $0) },
            priceKindRaw: regular == nil ? "regular" : "sale",
            confidence: 0.9,
            sourceText: name
        )
    }

    @Test("A generic item rolls up matching flyer records, best price first")
    func rollsUpAndSortsByPrice() {
        let records = [
            record("Marble Cheddar", banner: "Safeway", price: "6.99"),
            record("Mozzarella", banner: "Walmart", price: "3.98"),
            record("Cream Cheese", banner: "Sobeys", price: "4.49")
        ]
        let rows = viewModel.flyerComparisonRows(itemKey: "cheese", records: records)
        // "cheese" head-noun rolls up cheddar/mozzarella/cream cheese? Head-noun rule:
        // only those whose head noun is "cheese" match. Cream Cheese -> head "cheese".
        // Marble Cheddar -> head "cheddar" (no match). Mozzarella -> head "mozzarella".
        // So only Cream Cheese matches the generic "cheese" query.
        #expect(rows.map(\.productName) == ["Cream Cheese"])
    }

    @Test("Specific query matches the right flyer records and orders by price")
    func specificQueryOrdersByPrice() {
        let records = [
            record("Whole Milk 2L", banner: "Safeway", price: "4.99"),
            record("Whole Milk 2L", banner: "Walmart", price: "3.79"),
            record("Whole Milk 2L", banner: "Sobeys", price: "4.29")
        ]
        let rows = viewModel.flyerComparisonRows(itemKey: "whole milk", records: records)
        #expect(rows.count == 3)
        #expect(rows.map(\.price) == [Decimal(string: "3.79")!, Decimal(string: "4.29")!, Decimal(string: "4.99")!])
        #expect(rows.first?.bannerName == "Walmart")
    }

    @Test("Carries regular price through for the strikethrough display")
    func carriesRegularPrice() {
        let rows = viewModel.flyerComparisonRows(
            itemKey: "butter",
            records: [record("Salted Butter", price: "4.49", regular: "5.99")]
        )
        #expect(rows.first?.regularPrice == Decimal(string: "5.99"))
    }

    @Test("Unrelated items promote no flyer rows")
    func unrelatedItemsProduceNoRows() {
        let rows = viewModel.flyerComparisonRows(
            itemKey: "bananas",
            records: [record("Paper Towels", price: "5.99")]
        )
        #expect(rows.isEmpty)
    }

    // MARK: - Browse-list promotion (flyer-only items)

    private func priceEntry(_ name: String, price: String) -> PriceEntry {
        PriceEntry(
            capturedAt: .now,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: .each,
            photoAssetId: "test"
        )
    }

    @Test("Flyer-only items appear in Browse, flagged, with the cheapest banner price")
    func flyerOnlyItemsAppearInBrowse() {
        viewModel.recompute(
            entries: [priceEntry("Whole Milk", price: "3.49")],
            flyerRecords: [
                record("Orange Juice", banner: "Walmart", price: "3.99"),
                record("Orange Juice", banner: "Safeway", price: "4.49")
            ],
            query: ""
        )
        let oj = viewModel.browseItems.first { $0.displayName == "Orange Juice" }
        #expect(oj != nil)
        #expect(oj?.isFlyerOnly == true)
        #expect(oj?.bestPrice == Decimal(string: "3.99"))   // cheapest banner
        #expect(oj?.storeCount == 2)                          // distinct banners
        // The captured item is still present and not flagged.
        #expect(viewModel.browseItems.first { $0.displayName == "Whole Milk" }?.isFlyerOnly == false)
    }

    @Test("A flyer item that matches a captured item is not duplicated as flyer-only")
    func capturedItemNotDuplicated() {
        viewModel.recompute(
            entries: [priceEntry("Butter", price: "5.49")],
            flyerRecords: [record("Butter", banner: "Walmart", price: "3.99")],
            query: ""
        )
        let butterRows = viewModel.browseItems.filter { $0.itemKey == ItemKeyNormalizer.normalize("Butter") }
        #expect(butterRows.count == 1)
        #expect(butterRows.first?.isFlyerOnly == false)
    }

    @Test("Flyer-only items are searchable")
    func flyerOnlyItemsAreSearchable() {
        viewModel.recompute(
            entries: [],
            flyerRecords: [record("Sourdough Bread", banner: "Sobeys", price: "2.99")],
            query: "bread"
        )
        #expect(viewModel.searchResults.contains { $0.displayName == "Sourdough Bread" && $0.isFlyerOnly })
    }
}
