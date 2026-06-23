import Foundation
import Testing
@testable import Prixio

/// Coverage for `PriceInsightEngine.computeTripWinner`, the only stable pure function on the engine
/// that had no dedicated tests. It groups per-item best-store suggestions into a single "where to
/// shop" winner, ranks the runners-up, and reports staleness — all deterministically, with no
/// dependency on the item-history surface.
struct PriceInsightTripWinnerTests {

    // MARK: - Fixtures

    private let costcoID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!
    private let walmartID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let loblawsID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func suggestion(
        chainID: UUID?,
        chainName: String?,
        locationID: UUID? = nil,
        locationName: String? = nil,
        price: String = "1.00",
        stalenessBucket: StalenessBucket = .fresh
    ) -> PriceInsightEngine.BestStoreSuggestion {
        let value = Decimal(string: price)!
        return PriceInsightEngine.BestStoreSuggestion(
            entryID: UUID(),
            itemKey: "milk",
            storeChainID: chainID,
            storeLocationID: locationID,
            storeChainName: chainName,
            storeLocationName: locationName,
            comparablePrice: value,
            packagePrice: value,
            comparableUnitType: .each,
            capturedAt: capturedAt,
            ageDays: 0,
            stalenessBucket: stalenessBucket,
            usedNormalizedPricing: false,
            storeCoordinateLat: nil,
            storeCoordinateLon: nil
        )
    }

    // MARK: - Unhappy paths (guards)

    @Test
    func computeTripWinner_returnsNil_givenNoSuggestions() {
        // Arrange / Act
        let result = PriceInsightEngine.computeTripWinner(suggestions: [], totalItems: 3)

        // Assert
        #expect(result == nil)
    }

    @Test
    func computeTripWinner_returnsNil_givenZeroTotalItems() {
        // Arrange
        let suggestions = [suggestion(chainID: costcoID, chainName: "Costco")]

        // Act
        let result = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 0)

        // Assert
        #expect(result == nil)
    }

    @Test
    func computeTripWinner_returnsNil_givenNegativeTotalItems() {
        // Arrange
        let suggestions = [suggestion(chainID: costcoID, chainName: "Costco")]

        // Act
        let result = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: -1)

        // Assert
        #expect(result == nil)
    }

    // MARK: - Happy path

    @Test
    func computeTripWinner_singleSuggestion_winsWithCountOne() {
        // Arrange
        let suggestions = [suggestion(chainID: costcoID, chainName: "Costco")]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 1)

        // Assert
        #expect(summary?.winner.chainID == costcoID)
        #expect(summary?.winner.chainName == "Costco")
        #expect(summary?.winnerCount == 1)
        #expect(summary?.totalItems == 1)
        #expect(summary?.staleCount == 0)
        #expect(summary?.rankedCounts.count == 1)
    }

    @Test
    func computeTripWinner_groupsByChain_andPicksMostFrequentStore() {
        // Arrange — Costco wins 3 items, Walmart 1.
        let suggestions = [
            suggestion(chainID: costcoID, chainName: "Costco"),
            suggestion(chainID: costcoID, chainName: "Costco"),
            suggestion(chainID: costcoID, chainName: "Costco"),
            suggestion(chainID: walmartID, chainName: "Walmart")
        ]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 4)

        // Assert
        #expect(summary?.winner.chainID == costcoID)
        #expect(summary?.winnerCount == 3)
        #expect(summary?.totalItems == 4)
        #expect(summary?.rankedCounts.count == 2)
    }

    @Test
    func computeTripWinner_ranksRunnersUpByCountDescending() {
        // Arrange — Costco 3, Loblaws 2, Walmart 1.
        let suggestions =
            Array(repeating: suggestion(chainID: costcoID, chainName: "Costco"), count: 3) +
            Array(repeating: suggestion(chainID: loblawsID, chainName: "Loblaws"), count: 2) +
            [suggestion(chainID: walmartID, chainName: "Walmart")]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 6)

        // Assert — ranked strictly by descending count.
        let counts = summary?.rankedCounts.map(\.count)
        #expect(counts == [3, 2, 1])
        #expect(summary?.rankedCounts.map(\.store.chainName) == ["Costco", "Loblaws", "Walmart"])
    }

    // MARK: - Edge cases

    @Test
    func computeTripWinner_breaksCountTie_byCaseInsensitiveName() {
        // Arrange — two stores tied at 1 each; "aldi" should sort before "Zellers" case-insensitively.
        let suggestions = [
            suggestion(chainID: walmartID, chainName: "Zellers"),
            suggestion(chainID: costcoID, chainName: "aldi")
        ]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 2)

        // Assert
        #expect(summary?.winner.chainName == "aldi")
        #expect(summary?.rankedCounts.map(\.store.chainName) == ["aldi", "Zellers"])
    }

    @Test
    func computeTripWinner_distinctChains_sharingAName_remainSeparateStores() {
        // Arrange — same display name but different chain IDs must not be merged.
        let suggestions = [
            suggestion(chainID: costcoID, chainName: "Market"),
            suggestion(chainID: walmartID, chainName: "Market")
        ]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 2)

        // Assert — two separate single-item stores, not one store with count 2.
        #expect(summary?.rankedCounts.count == 2)
        #expect(summary?.winnerCount == 1)
    }

    @Test
    func computeTripWinner_groupsByName_whenChainIDIsNil() {
        // Arrange — no chain IDs; identical names group together.
        let suggestions = [
            suggestion(chainID: nil, chainName: "Corner Store"),
            suggestion(chainID: nil, chainName: "Corner Store")
        ]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 2)

        // Assert
        #expect(summary?.rankedCounts.count == 1)
        #expect(summary?.winnerCount == 2)
        #expect(summary?.winner.chainName == "Corner Store")
    }

    @Test
    func computeTripWinner_fallsBackToLocationName_whenChainNameIsNil() {
        // Arrange — chain name missing, location name present.
        let suggestions = [
            suggestion(chainID: nil, chainName: nil, locationName: "5th Ave Grocer")
        ]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 1)

        // Assert
        #expect(summary?.winner.chainName == "5th Ave Grocer")
    }

    @Test
    func computeTripWinner_fallsBackToUnknown_whenNoNamesPresent() {
        // Arrange — neither chain nor location name.
        let suggestions = [
            suggestion(chainID: nil, chainName: nil, locationName: nil)
        ]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 1)

        // Assert
        #expect(summary?.winner.chainName == "Unknown")
    }

    @Test
    func computeTripWinner_countsOnlyStaleAndVeryStaleTowardStaleCount() {
        // Arrange — fresh + aging are not stale; stale + veryStale are.
        let suggestions = [
            suggestion(chainID: costcoID, chainName: "Costco", stalenessBucket: .fresh),
            suggestion(chainID: walmartID, chainName: "Walmart", stalenessBucket: .aging),
            suggestion(chainID: loblawsID, chainName: "Loblaws", stalenessBucket: .stale),
            suggestion(chainID: nil, chainName: "Bodega", stalenessBucket: .veryStale)
        ]

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 4)

        // Assert — only .stale and .veryStale count.
        #expect(summary?.staleCount == 2)
    }

    @Test
    func computeTripWinner_staleSuggestionsDoNotVote() {
        // `computeBestStoreForItem` falls back to the cheapest price in ALL history when nothing is
        // recent, so a single months-old scan can surface as a suggestion. It must not drive the
        // winner: a fresh Walmart price should win over a stale Costco one even though Costco appears
        // twice. The stale ones are still counted in `staleCount`.
        let suggestions = [
            suggestion(chainID: costcoID, chainName: "Costco", stalenessBucket: .veryStale),
            suggestion(chainID: costcoID, chainName: "Costco", stalenessBucket: .stale),
            suggestion(chainID: walmartID, chainName: "Walmart", stalenessBucket: .fresh)
        ]

        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 3)

        #expect(summary?.winner.chainID == walmartID)
        #expect(summary?.winnerCount == 1)
        #expect(summary?.staleCount == 2)
        // Stale-only Costco never enters the ranking.
        #expect(summary?.rankedCounts.count == 1)
    }

    @Test
    func computeTripWinner_returnsNil_whenEverySuggestionIsStale() {
        // With no fresh prices at all there is nothing trustworthy to recommend.
        let suggestions = [
            suggestion(chainID: costcoID, chainName: "Costco", stalenessBucket: .stale),
            suggestion(chainID: walmartID, chainName: "Walmart", stalenessBucket: .veryStale)
        ]

        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 2)

        #expect(summary == nil)
    }

    @Test
    func computeTripWinner_reportsTotalItems_independentlyOfWinnerCoverage() {
        // Arrange — winner covers 2 of a 5-item basket (the rest were unpriced upstream).
        let suggestions = Array(repeating: suggestion(chainID: costcoID, chainName: "Costco"), count: 2)

        // Act
        let summary = PriceInsightEngine.computeTripWinner(suggestions: suggestions, totalItems: 5)

        // Assert — totalItems is passed through verbatim, winnerCount reflects only suggestions.
        #expect(summary?.winnerCount == 2)
        #expect(summary?.totalItems == 5)
    }
}
