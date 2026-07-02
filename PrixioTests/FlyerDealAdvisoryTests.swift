import Foundation
import Testing
@testable import Prixio

/// Tests for the shopping list's advisory-only flyer line. Basket totals stay
/// capture-only; the advisory reports potential savings against each item's cheapest
/// captured package price and never feeds an estimate.
@MainActor
struct FlyerDealAdvisoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(
        _ name: String,
        banner: String,
        price: String,
        saleEnd: Date? = nil
    ) -> FlyerPriceRecord {
        FlyerPriceRecord(
            savedAt: now,
            dealKey: "\(banner)|\(ItemKeyNormalizer.normalize(name))|\(price)",
            bannerID: banner.lowercased(),
            bannerName: banner,
            fetchedAt: now,
            productName: name,
            normalizedItemKey: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            priceKindRaw: "sale",
            saleEndDate: saleEnd,
            confidence: 0.9,
            sourceText: name
        )
    }

    private func entry(_ name: String, price: String) -> PriceEntry {
        PriceEntry(
            capturedAt: now.addingTimeInterval(-86_400),
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: .each,
            photoAssetId: "test"
        )
    }

    private func item(_ name: String) -> BasketItemInput {
        BasketItemInput(itemKey: ItemKeyNormalizer.normalize(name), displayName: name)
    }

    @Test("Savings sum the captured baseline minus the banner's best flyer price per item")
    func computesSavingsAgainstCapturedBaseline() {
        let advisory = FlyerDealAdvisory.compute(
            items: [item("Milk"), item("Eggs")],
            records: [
                record("Whole Milk", banner: "Walmart", price: "3.49"),
                record("Large Eggs", banner: "Walmart", price: "3.99")
            ],
            entries: [entry("Whole Milk", price: "4.49"), entry("Large Eggs", price: "4.99")],
            now: now
        )

        #expect(advisory?.bannerName == "Walmart")
        #expect(advisory?.matchedItemCount == 2)
        #expect(advisory?.estimatedSavings == Decimal(string: "2.00"))
    }

    @Test("Without a captured baseline the advisory reports matches but claims no savings")
    func noBaselineMeansNoSavingsClaim() {
        let advisory = FlyerDealAdvisory.compute(
            items: [item("Juice")],
            records: [record("Orange Juice", banner: "Walmart", price: "3.99")],
            entries: [],
            now: now
        )

        #expect(advisory?.matchedItemCount == 1)
        #expect(advisory?.estimatedSavings == nil)
        #expect(advisory?.message.contains("Walmart") == true)
    }

    @Test("A flyer price above the captured baseline is a match but not a saving")
    func flyerPriceAboveBaselineClaimsNoSavings() {
        let advisory = FlyerDealAdvisory.compute(
            items: [item("Milk")],
            records: [record("Whole Milk", banner: "Walmart", price: "5.99")],
            entries: [entry("Whole Milk", price: "4.49")],
            now: now
        )

        #expect(advisory?.matchedItemCount == 1)
        #expect(advisory?.estimatedSavings == nil)
    }

    @Test("The banner with the highest savings wins")
    func picksBannerWithHighestSavings() {
        let advisory = FlyerDealAdvisory.compute(
            items: [item("Milk")],
            records: [
                record("Whole Milk", banner: "Safeway", price: "4.24"),
                record("Whole Milk", banner: "Walmart", price: "3.49")
            ],
            entries: [entry("Whole Milk", price: "4.49")],
            now: now
        )

        #expect(advisory?.bannerName == "Walmart")
        #expect(advisory?.estimatedSavings == Decimal(string: "1.00"))
    }

    @Test("Expired flyer records are ignored")
    func expiredRecordsAreIgnored() {
        let advisory = FlyerDealAdvisory.compute(
            items: [item("Milk")],
            records: [record("Whole Milk", banner: "Walmart", price: "3.49", saleEnd: now.addingTimeInterval(-3 * 86_400))],
            entries: [entry("Whole Milk", price: "4.49")],
            now: now
        )

        #expect(advisory == nil)
    }

    @Test("Unrelated records produce no advisory")
    func unrelatedRecordsProduceNoAdvisory() {
        let advisory = FlyerDealAdvisory.compute(
            items: [item("Bananas")],
            records: [record("Paper Towels", banner: "Walmart", price: "5.99")],
            entries: [],
            now: now
        )

        #expect(advisory == nil)
    }
}
