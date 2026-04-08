import Foundation
import Testing
@testable import Prixio

@MainActor
struct TripRecommendationTests {
    @Test
    func strongWinnerWhenTopChainMeetsSixtyPercentThreshold() {
        let viewModel = ShoppingListViewModel()
        let items = [
            makeItem(name: "Milk"),
            makeItem(name: "Eggs"),
            makeItem(name: "Bread"),
            makeItem(name: "Butter"),
            makeItem(name: "Cheese")
        ]
        let now = Date(timeIntervalSince1970: 2_000_000)
        let entries = [
            makeEntry(item: "milk", chainName: "Co-op", price: "4.00", capturedAt: now.addingTimeInterval(-1 * 86_400)),
            makeEntry(item: "eggs", chainName: "Co-op", price: "3.00", capturedAt: now.addingTimeInterval(-1 * 86_400)),
            makeEntry(item: "bread", chainName: "Co-op", price: "2.00", capturedAt: now.addingTimeInterval(-1 * 86_400)),
            makeEntry(item: "butter", chainName: "Sobeys", price: "5.00", capturedAt: now.addingTimeInterval(-1 * 86_400)),
            makeEntry(item: "cheese", chainName: "Sobeys", price: "6.00", capturedAt: now.addingTimeInterval(-1 * 86_400))
        ]

        viewModel.recompute(items: items, entries: entries, userLocation: nil, now: now)

        #expect(
            viewModel.tripRecommendation ==
            .strongWinner(chainID: nil, chainName: "Co-op", count: 3, total: 5, staleCount: 0)
        )
    }

    @Test
    func splitTripWhenThresholdIsNotMet() {
        let viewModel = ShoppingListViewModel()
        let items = [
            makeItem(name: "Milk"),
            makeItem(name: "Eggs"),
            makeItem(name: "Bread"),
            makeItem(name: "Butter")
        ]
        let now = Date(timeIntervalSince1970: 3_000_000)
        let entries = [
            makeEntry(item: "milk", chainName: "Co-op", price: "4.00", capturedAt: now.addingTimeInterval(-1 * 86_400)),
            makeEntry(item: "eggs", chainName: "Co-op", price: "3.00", capturedAt: now.addingTimeInterval(-1 * 86_400)),
            makeEntry(item: "bread", chainName: "Sobeys", price: "2.00", capturedAt: now.addingTimeInterval(-1 * 86_400)),
            makeEntry(item: "butter", chainName: "Walmart", price: "5.00", capturedAt: now.addingTimeInterval(-1 * 86_400))
        ]

        viewModel.recompute(items: items, entries: entries, userLocation: nil, now: now)

        #expect(
            viewModel.tripRecommendation ==
            .splitTrip(
                primaryChainID: nil,
                primaryChainName: "Co-op",
                primaryCount: 2,
                secondaryChainID: nil,
                secondaryChainName: "Sobeys",
                secondaryCount: 1,
                staleCount: 0
            )
        )
    }

    @Test
    func insufficientDataWhenTooFewPricedSuggestionsExist() {
        let viewModel = ShoppingListViewModel()
        let items = [
            makeItem(name: "Milk"),
            makeItem(name: "Eggs")
        ]
        let now = Date(timeIntervalSince1970: 4_000_000)
        let entries = [
            makeEntry(item: "milk", chainName: "Co-op", price: "4.00", capturedAt: now.addingTimeInterval(-1 * 86_400))
        ]

        viewModel.recompute(items: items, entries: entries, userLocation: nil, now: now)

        #expect(viewModel.tripRecommendation == .insufficientData)
    }

    @Test
    func staleItemCountIsIncludedInRecommendation() {
        let viewModel = ShoppingListViewModel()
        let items = [
            makeItem(name: "Milk"),
            makeItem(name: "Eggs"),
            makeItem(name: "Bread")
        ]
        let now = Date(timeIntervalSince1970: 5_000_000)
        let entries = [
            makeEntry(item: "milk", chainName: "Co-op", price: "4.00", capturedAt: now.addingTimeInterval(-40 * 86_400)),
            makeEntry(item: "eggs", chainName: "Co-op", price: "3.00", capturedAt: now.addingTimeInterval(-1 * 86_400)),
            makeEntry(item: "bread", chainName: "Co-op", price: "2.00", capturedAt: now.addingTimeInterval(-1 * 86_400))
        ]

        viewModel.recompute(items: items, entries: entries, userLocation: nil, now: now)

        #expect(
            viewModel.tripRecommendation ==
            .strongWinner(chainID: nil, chainName: "Co-op", count: 3, total: 3, staleCount: 1)
        )
    }

    private func makeItem(name: String) -> ShoppingListItem {
        ShoppingListItem(itemKey: ItemKeyNormalizer.normalize(name), displayName: name)
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
