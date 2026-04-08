import CoreLocation
import Foundation
import Testing
@testable import Prixio

@MainActor
struct CompareFlowViewModelTests {
    @Test
    func searchReturnsMatchingItemsForNormalizedKeys() {
        let viewModel = CompareViewModel()
        let entries = [
            makeEntry(itemName: "Milk", normalizedName: "milk", chainName: "Store A", capturedAtDaysAgo: 1),
            makeEntry(itemName: "Bananas", normalizedName: "bananas", chainName: "Store B", capturedAtDaysAgo: 2)
        ]

        viewModel.recompute(entries: entries, query: "milk")

        #expect(viewModel.searchResults.map(\.itemKey) == ["milk"])
    }

    @Test
    func emptyQueryReturnsBrowseModeWithoutSearchResults() {
        let viewModel = CompareViewModel()
        let entries = [
            makeEntry(itemName: "Milk", normalizedName: "milk", chainName: "Store A", capturedAtDaysAgo: 1),
            makeEntry(itemName: "Bananas", normalizedName: "bananas", chainName: "Store B", capturedAtDaysAgo: 2)
        ]

        viewModel.recompute(entries: entries, query: "")

        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.browseItems.map(\.itemKey) == ["bananas", "milk"])
    }

    @Test
    func suggestedCardsOnlyAppearForItemsTrackedAtMultipleStores() {
        let viewModel = CompareViewModel()
        let entries = [
            makeEntry(itemName: "Milk", normalizedName: "milk", chainName: "Store A", capturedAtDaysAgo: 1),
            makeEntry(itemName: "Milk", normalizedName: "milk", chainName: "Store B", capturedAtDaysAgo: 2),
            makeEntry(itemName: "Eggs", normalizedName: "eggs", chainName: "Store A", capturedAtDaysAgo: 1)
        ]

        viewModel.recompute(entries: entries, query: "")

        #expect(viewModel.suggestedCards.map(\.itemKey) == ["milk"])
    }

    @Test
    func itemDetailRowsSortByStalenessThenPriceThenRecency() {
        let viewModel = CompareViewModel()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let entries = [
            makeEntry(
                itemName: "Milk",
                normalizedName: "milk",
                chainName: "Fresh Cheap",
                capturedAt: now.addingTimeInterval(-2 * 86_400),
                normalizedPrice: "4.50",
                normalizedUnitType: .liter
            ),
            makeEntry(
                itemName: "Milk",
                normalizedName: "milk",
                chainName: "Fresh Expensive",
                capturedAt: now.addingTimeInterval(-1 * 86_400),
                normalizedPrice: "5.25",
                normalizedUnitType: .liter
            ),
            makeEntry(
                itemName: "Milk",
                normalizedName: "milk",
                chainName: "Stale Cheap",
                capturedAt: now.addingTimeInterval(-50 * 86_400),
                normalizedPrice: "3.25",
                normalizedUnitType: .liter
            )
        ]

        let state = viewModel.buildItemComparisonState(
            itemKey: "milk",
            entries: entries,
            mode: .perUnit,
            userLocation: nil,
            now: now
        )

        #expect(state.rows.map(\.displayStoreName) == ["Fresh Cheap", "Fresh Expensive", "Stale Cheap"])
    }

    @Test
    func trendBadgeReturnsFlatWithinTwoPercentDeadband() {
        let viewModel = CompareViewModel()
        let now = Date(timeIntervalSince1970: 3_000_000)
        let sharedStoreID = UUID()
        let entries = [
            makeEntry(
                itemName: "Milk",
                normalizedName: "milk",
                chainName: "Store A",
                chainID: sharedStoreID,
                capturedAt: now.addingTimeInterval(-1 * 86_400),
                normalizedPrice: "5.00",
                normalizedUnitType: .liter
            ),
            makeEntry(
                itemName: "Milk",
                normalizedName: "milk",
                chainName: "Store A",
                chainID: sharedStoreID,
                capturedAt: now.addingTimeInterval(-5 * 86_400),
                normalizedPrice: "4.95",
                normalizedUnitType: .liter
            )
        ]

        let state = viewModel.buildItemComparisonState(
            itemKey: "milk",
            entries: entries,
            mode: .perUnit,
            userLocation: nil,
            now: now
        )

        #expect(state.rows.first?.trendDirection == .flat)
    }

    @Test
    func mixedUnitFamilyNoteAppearsWhenComparableEntriesSpanDifferentFamilies() {
        let viewModel = CompareViewModel()
        let now = Date(timeIntervalSince1970: 4_000_000)
        let entries = [
            makeEntry(
                itemName: "Juice",
                normalizedName: "juice",
                chainName: "Store A",
                capturedAt: now.addingTimeInterval(-1 * 86_400),
                normalizedPrice: "3.00",
                normalizedUnitType: .liter
            ),
            makeEntry(
                itemName: "Juice",
                normalizedName: "juice",
                chainName: "Store B",
                capturedAt: now.addingTimeInterval(-2 * 86_400),
                normalizedPrice: "1.50",
                normalizedUnitType: .each
            )
        ]

        let state = viewModel.buildItemComparisonState(
            itemKey: "juice",
            entries: entries,
            mode: .perUnit,
            userLocation: nil,
            now: now
        )

        #expect(state.showsMixedUnitFamilyNote == true)
    }

    @Test
    func distanceValueIsAbsentWhenUserLocationIsUnavailable() {
        let viewModel = CompareViewModel()
        let entries = [
            makeEntry(
                itemName: "Milk",
                normalizedName: "milk",
                chainName: "Store A",
                capturedAtDaysAgo: 1,
                normalizedPrice: "4.50",
                normalizedUnitType: .liter,
                latitude: 51.0,
                longitude: -114.0
            )
        ]

        let state = viewModel.buildItemComparisonState(
            itemKey: "milk",
            entries: entries,
            mode: .perUnit,
            userLocation: nil
        )

        #expect(state.rows.first?.distanceMeters == nil)
    }

    private func makeEntry(
        itemName: String,
        normalizedName: String,
        chainName: String,
        chainID: UUID = UUID(),
        capturedAtDaysAgo daysAgo: Int,
        normalizedPrice: String? = "4.00",
        normalizedUnitType: UnitType? = .liter,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> PriceEntry {
        makeEntry(
            itemName: itemName,
            normalizedName: normalizedName,
            chainName: chainName,
            chainID: chainID,
            capturedAt: Date().addingTimeInterval(TimeInterval(daysAgo) * -86_400),
            normalizedPrice: normalizedPrice,
            normalizedUnitType: normalizedUnitType,
            latitude: latitude,
            longitude: longitude
        )
    }

    private func makeEntry(
        itemName: String,
        normalizedName: String,
        chainName: String,
        chainID: UUID = UUID(),
        capturedAt: Date,
        normalizedPrice: String? = "4.00",
        normalizedUnitType: UnitType? = .liter,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> PriceEntry {
        PriceEntry(
            capturedAt: capturedAt,
            itemNameRaw: itemName,
            itemNameNormalized: normalizedName,
            priceValue: Decimal(string: "5.00")!,
            unitType: .each,
            unitQuantityValue: nil,
            normalizedUnitPriceValue: normalizedPrice.flatMap { Decimal(string: $0) },
            normalizedUnitType: normalizedUnitType,
            storeChainId: chainID,
            storeLocationId: nil,
            storeChainNameSnapshot: chainName,
            storeLocationNameSnapshot: nil,
            storeCoordinateLat: latitude,
            storeCoordinateLon: longitude,
            photoAssetId: ""
        )
    }
}
