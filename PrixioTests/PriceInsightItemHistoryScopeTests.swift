import Foundation
import Testing
@testable import Prixio

/// Complements `ItemPriceHistoryTests` by covering the `computeItemHistory` paths that suite leaves
/// open: the moderate `belowUsual`/`aboveUsual` anomaly bands, `location` scope, scope name matching
/// (case- and whitespace-insensitive), scope filters that exclude every entry, the `freshness`
/// field, and `displayName` passthrough.
struct PriceInsightItemHistoryScopeTests {

    private func entry(
        name: String,
        price: String,
        chainName: String? = nil,
        locationName: String? = nil,
        capturedDaysAgo: Int,
        now: Date
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: .each,
            storeChainNameSnapshot: chainName,
            storeLocationNameSnapshot: locationName,
            photoAssetId: ""
        )
    }

    // MARK: - Moderate anomaly bands

    @Test
    func flagsBelowUsual_whenLatestDipsModeratelyBelowMedian() throws {
        // Arrange — median 100; latest 88 sits below the usual band (90) but above the strong band (80).
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Eggs", price: "100", capturedDaysAgo: 20, now: now),
            entry(name: "Eggs", price: "100", capturedDaysAgo: 10, now: now),
            entry(name: "Eggs", price: "88", capturedDaysAgo: 1, now: now)
        ]

        // Act
        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Eggs",
            displayName: "Eggs",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        // Assert
        #expect(history.median == Decimal(100))
        #expect(history.latest.price == Decimal(88))
        #expect(history.anomaly == .belowUsual)
    }

    @Test
    func flagsAboveUsual_whenLatestRisesModeratelyAboveMedian() throws {
        // Arrange — median 100; latest 112 sits above the usual band (110) but below the strong band (120).
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Eggs", price: "100", capturedDaysAgo: 20, now: now),
            entry(name: "Eggs", price: "100", capturedDaysAgo: 10, now: now),
            entry(name: "Eggs", price: "112", capturedDaysAgo: 1, now: now)
        ]

        // Act
        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Eggs",
            displayName: "Eggs",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        // Assert
        #expect(history.median == Decimal(100))
        #expect(history.latest.price == Decimal(112))
        #expect(history.anomaly == .aboveUsual)
    }

    // MARK: - Scope filtering

    @Test
    func locationScope_summarizesOnlyThatLocationsObservations() throws {
        // Arrange — two no-chain stores; only the Downtown observations should be in scope.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Bread", price: "3.00", locationName: "Downtown", capturedDaysAgo: 10, now: now),
            entry(name: "Bread", price: "3.50", locationName: "Downtown", capturedDaysAgo: 2, now: now),
            entry(name: "Bread", price: "9.00", locationName: "Uptown", capturedDaysAgo: 1, now: now)
        ]

        // Act
        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Bread",
            displayName: "Bread",
            useNormalizedPricing: false,
            allEntries: entries,
            scope: .location(name: "Downtown"),
            now: now
        ))

        // Assert — the Uptown 9.00 outlier is excluded.
        #expect(history.scope == .location(name: "Downtown"))
        #expect(history.observationCount == 2)
        #expect(history.highest.price == Decimal(string: "3.50"))
    }

    @Test
    func scopeMatchesStoreName_caseInsensitivelyAndIgnoringSurroundingWhitespace() throws {
        // Arrange — stored snapshot has padding and mixed case; scope name is lowercase and trimmed.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Milk", price: "4.00", chainName: "  Costco  ", capturedDaysAgo: 1, now: now)
        ]

        // Act
        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Milk",
            displayName: "Milk",
            useNormalizedPricing: false,
            allEntries: entries,
            scope: .chain(name: "costco"),
            now: now
        ))

        // Assert
        #expect(history.observationCount == 1)
    }

    @Test
    func returnsNil_whenScopeExcludesEveryEntry() {
        // Arrange — only Walmart entries, but the scope asks for Costco.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Milk", price: "4.00", chainName: "Walmart", capturedDaysAgo: 1, now: now)
        ]

        // Act
        let history = PriceInsightEngine.computeItemHistory(
            itemKey: "Milk",
            displayName: "Milk",
            useNormalizedPricing: false,
            allEntries: entries,
            scope: .chain(name: "Costco"),
            now: now
        )

        // Assert
        #expect(history == nil)
    }

    // MARK: - Freshness & display name

    @Test
    func freshnessReflectsTheAgeOfTheLatestObservation() throws {
        // Arrange — a single observation captured 40 days ago falls in the `.stale` bucket.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Rice", price: "12.00", capturedDaysAgo: 40, now: now)
        ]

        // Act
        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Rice",
            displayName: "Rice",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        // Assert — too few observations for a band, but freshness is still classified.
        #expect(history.freshness == .stale)
        #expect(history.hasUsualBand == false)
        #expect(history.anomaly == .insufficientData)
    }

    @Test
    func passesThroughDisplayName_whileKeyingOffNormalizedItemKey() throws {
        // Arrange — display name differs from the normalized key.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(name: "Bananas", price: "1.50", capturedDaysAgo: 1, now: now)
        ]

        // Act
        let history = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: "Bananas",
            displayName: "Organic Bananas",
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        ))

        // Assert — display name is verbatim; key is normalized (singularized "banana").
        #expect(history.displayName == "Organic Bananas")
        #expect(history.itemKey == ItemKeyNormalizer.normalize("Bananas"))
    }
}
