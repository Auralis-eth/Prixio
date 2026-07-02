import Combine
import CoreLocation
import Foundation

@MainActor
final class ShoppingListViewModel: ObservableObject {
    @Published private(set) var activeRows: [ShoppingListRowData] = []
    @Published private(set) var completedRows: [ShoppingListRowData] = []
    @Published private(set) var tripRecommendation: TripRecommendation = .insufficientData
    @Published private(set) var basketEstimate: BasketEstimate = .empty
    /// Advisory-only flyer line ("Flyer deals could save ~$X at Y"); never feeds the
    /// basket totals.
    @Published private(set) var flyerAdvisory: FlyerDealAdvisory?

    func recompute(
        items: [ShoppingListItem],
        entries: [PriceEntry],
        flyerRecords: [FlyerPriceRecord] = [],
        userLocation: CLLocation?,
        now: Date = .now
    ) {
        let suggestionsByItemKey = Dictionary(uniqueKeysWithValues: Set(items.map(\.itemKey)).map { itemKey in
            (
                itemKey,
                PriceInsightEngine.computeBestStoreForItem(
                    itemKey: itemKey,
                    allEntries: entries,
                    now: now
                )
            )
        })

        let rows = items.map { item in
            makeRow(
                for: item,
                suggestion: suggestionsByItemKey[item.itemKey] ?? nil,
                userLocation: userLocation,
                now: now
            )
        }

        activeRows = rows.filter { !$0.isDone }
        completedRows = rows.filter(\.isDone)
        tripRecommendation = makeTripRecommendation(from: activeRows)

        // Basket totals use package prices (you buy a package, not a normalized unit).
        let basketItems = activeRows.map { BasketItemInput(itemKey: $0.itemKey, displayName: $0.displayName) }
        basketEstimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems,
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        flyerAdvisory = FlyerDealAdvisory.compute(
            items: basketItems,
            records: flyerRecords,
            entries: entries,
            now: now
        )
    }

    private func makeRow(
        for item: ShoppingListItem,
        suggestion: PriceInsightEngine.BestStoreSuggestion?,
        userLocation: CLLocation?,
        now _: Date
    ) -> ShoppingListRowData {
        let distanceMeters = distanceMeters(from: userLocation, suggestion: suggestion)
        let ageText = suggestion.map { "\($0.ageDays)d" }
        let bestStoreName = suggestion?.storeChainName ?? suggestion?.storeLocationName
        let bestPriceText = suggestion.map {
            "\(CurrencyFormatter.shared.display($0.comparablePrice))/\($0.comparableUnitType.displayName)"
        }

        return ShoppingListRowData(
            itemID: item.id,
            itemKey: item.itemKey,
            displayName: item.displayName,
            brand: item.brand,
            quantityNote: item.quantityNote,
            isDone: item.isDone,
            suggestion: suggestion,
            bestStoreName: bestStoreName,
            bestPriceText: bestPriceText,
            ageText: ageText,
            stalenessBucket: suggestion?.stalenessBucket,
            distanceMeters: distanceMeters
        )
    }

    private func makeTripRecommendation(from activeRows: [ShoppingListRowData]) -> TripRecommendation {
        guard activeRows.count >= 2 else {
            return .insufficientData
        }

        let suggestions = activeRows.compactMap(\.suggestion)
        guard suggestions.count >= 2 else {
            return .insufficientData
        }

        guard let winnerSummary = PriceInsightEngine.computeTripWinner(
            suggestions: suggestions,
            totalItems: activeRows.count
        ) else {
            return .insufficientData
        }

        let threshold = Double(activeRows.count) * 0.6
        if Double(winnerSummary.winnerCount) >= threshold {
            return .strongWinner(
                chainID: winnerSummary.winner.chainID,
                chainName: winnerSummary.winner.chainName,
                count: winnerSummary.winnerCount,
                total: activeRows.count,
                staleCount: winnerSummary.staleCount
            )
        }

        let secondary = winnerSummary.rankedCounts.dropFirst().first
        return .splitTrip(
            primaryChainID: winnerSummary.winner.chainID,
            primaryChainName: winnerSummary.winner.chainName,
            primaryCount: winnerSummary.winnerCount,
            secondaryChainID: secondary?.store.chainID,
            secondaryChainName: secondary?.store.chainName,
            secondaryCount: secondary?.count,
            staleCount: winnerSummary.staleCount
        )
    }

    private func distanceMeters(
        from userLocation: CLLocation?,
        suggestion: PriceInsightEngine.BestStoreSuggestion?
    ) -> CLLocationDistance? {
        guard
            let userLocation,
            let latitude = suggestion?.storeCoordinateLat,
            let longitude = suggestion?.storeCoordinateLon
        else {
            return nil
        }

        return userLocation.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }
}
