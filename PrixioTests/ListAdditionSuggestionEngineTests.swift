import Foundation
import Testing
@testable import Prixio

/// Tests for the deterministic "you usually buy this" engine behind the shopping
/// list's suggestion section.
@Suite("List addition suggestions")
struct ListAdditionSuggestionEngineTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ name: String, daysAgo: Int) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: "4.99")!,
            unitType: .each,
            photoAssetId: ""
        )
    }

    /// A weekly rhythm whose last purchase is `lastDaysAgo` days back.
    private func weeklyEntries(_ name: String, lastDaysAgo: Int) -> [PriceEntry] {
        [
            entry(name, daysAgo: lastDaysAgo + 21),
            entry(name, daysAgo: lastDaysAgo + 14),
            entry(name, daysAgo: lastDaysAgo + 7),
            entry(name, daysAgo: lastDaysAgo)
        ]
    }

    @Test("A due weekly item is suggested with its rhythm")
    func dueItemSuggested() {
        let suggestions = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: [],
            allEntries: weeklyEntries("Milk", lastDaysAgo: 9),
            now: now
        )
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.displayName == "Milk")
        #expect(suggestions.first?.medianIntervalDays == 7)
        #expect(suggestions.first?.daysSinceLastPurchase == 9)
        #expect(suggestions.first?.purchaseCount == 4)
    }

    @Test("An item bought recently is not yet due")
    func recentItemNotSuggested() {
        let suggestions = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: [],
            allEntries: weeklyEntries("Milk", lastDaysAgo: 3),
            now: now
        )
        #expect(suggestions.isEmpty)
    }

    @Test("Items already on the list are suppressed through the rollup, both directions")
    func listItemsSuppressed() {
        // Generic list "milk" covers the specific history "Almond Milk"…
        let specific = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: [ItemKeyNormalizer.normalize("milk")],
            allEntries: weeklyEntries("Almond Milk", lastDaysAgo: 9),
            now: now
        )
        #expect(specific.isEmpty)
        // …and a specific list item covers its broader history key.
        let broader = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: [ItemKeyNormalizer.normalize("Daisy Sour Cream")],
            allEntries: weeklyEntries("Sour Cream", lastDaysAgo: 9),
            now: now
        )
        #expect(broader.isEmpty)
    }

    @Test("Too few purchase days, or an implausible cadence, claims nothing")
    func thinOrIrregularHistoryStaysSilent() {
        // Two purchases: below the minimum.
        let thin = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: [],
            allEntries: [entry("Milk", daysAgo: 14), entry("Milk", daysAgo: 7)],
            now: now
        )
        #expect(thin.isEmpty)

        // Three same-week scans of one shop collapse to too-fast gaps.
        let artifact = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: [],
            allEntries: [
                entry("Milk", daysAgo: 12),
                entry("Milk", daysAgo: 11),
                entry("Milk", daysAgo: 10)
            ],
            now: now
        )
        #expect(artifact.isEmpty)

        // Multiple captures on the same day are a single purchase.
        let sameDay = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: [],
            allEntries: [
                entry("Milk", daysAgo: 10),
                entry("Milk", daysAgo: 10),
                entry("Milk", daysAgo: 5)
            ],
            now: now
        )
        #expect(sameDay.isEmpty)
    }

    @Test("Suggestions rank most-overdue first and respect the cap")
    func mostOverdueFirstAndCapped() {
        var entries: [PriceEntry] = []
        entries += weeklyEntries("Milk", lastDaysAgo: 8)      // ratio 8/7
        entries += weeklyEntries("Eggs", lastDaysAgo: 21)     // ratio 3.0
        entries += weeklyEntries("Bread", lastDaysAgo: 10)    // ratio 10/7
        entries += weeklyEntries("Butter", lastDaysAgo: 14)   // ratio 2.0

        let suggestions = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: [],
            allEntries: entries,
            now: now
        )
        #expect(suggestions.count == ListAdditionSuggestionEngine.maxSuggestions)
        #expect(suggestions.map(\.displayName) == ["Eggs", "Butter", "Bread"])
    }
}
