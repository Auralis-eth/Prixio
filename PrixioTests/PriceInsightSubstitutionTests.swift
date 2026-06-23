import Foundation
import Testing
@testable import Prixio

/// Coverage for basket **substitution** suggestions, focused on the unit-family safety rule: under
/// normalized (per-unit) pricing a substitute must share the basket item's unit family, so a `$/each`
/// price can never masquerade as cheaper than a `$/L` price (which would violate the engine's own
/// "never compare incompatible unit families" rule).
struct PriceInsightSubstitutionTests {
    private let storeA = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
    private let storeB = UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(
        name: String,
        normalizedPrice: String,
        normalizedUnit: UnitType,
        chainID: UUID,
        chainName: String
    ) -> PriceEntry {
        PriceEntry(
            capturedAt: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: normalizedPrice)!,
            unitType: normalizedUnit,
            normalizedUnitPriceValue: Decimal(string: normalizedPrice),
            normalizedUnitType: normalizedUnit,
            storeChainId: chainID,
            storeChainNameSnapshot: chainName,
            photoAssetId: ""
        )
    }

    private func basket(_ name: String) -> [BasketItemInput] {
        [BasketItemInput(itemKey: ItemKeyNormalizer.normalize(name), displayName: name)]
    }

    // MARK: - Happy path

    @Test
    func suggestsCheaperSubstituteInSameUnitFamily() {
        // Almond milk 5.00/L; soy milk 3.00/L — same unit family and ≥25% cheaper, so it's suggested.
        let entries = [
            entry(name: "Almond Milk", normalizedPrice: "5.00", normalizedUnit: .liter, chainID: storeA, chainName: "StoreA"),
            entry(name: "Soy Milk", normalizedPrice: "3.00", normalizedUnit: .liter, chainID: storeB, chainName: "StoreB")
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basket("Almond Milk"),
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        )

        #expect(estimate.substitutions.count == 1)
        #expect(estimate.substitutions.first?.substituteItemName == "Soy Milk")
    }

    // MARK: - Unit-family safety

    @Test
    func doesNotSuggestSubstituteFromDifferentUnitFamily() {
        // Almond milk 5.00/L; soy milk 1.00/each — the per-each number looks cheaper, but it belongs to
        // a different unit family, so comparing the two is meaningless and must NOT yield a suggestion.
        let entries = [
            entry(name: "Almond Milk", normalizedPrice: "5.00", normalizedUnit: .liter, chainID: storeA, chainName: "StoreA"),
            entry(name: "Soy Milk", normalizedPrice: "1.00", normalizedUnit: .each, chainID: storeB, chainName: "StoreB")
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basket("Almond Milk"),
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        )

        #expect(estimate.substitutions.isEmpty)
    }
}

/// Coverage for unit-family safety in **package** pricing mode — the mode the production basket
/// builder (`ShoppingListViewModel`) actually runs in. In package mode `priceValue` is the shelf
/// price expressed in `unitType`, so a `$/each` bag and a `$/kg` loose price are not comparable;
/// pooling and substitution must both stay within one `unitType` family or they produce a nonsense
/// "cheaper" pick.
struct PriceInsightPackageUnitFamilyTests {
    private let storeA = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func packageEntry(
        name: String,
        price: String,
        unit: UnitType,
        chainID: UUID,
        chainName: String,
        capturedDaysAgo: Int = 1
    ) -> PriceEntry {
        PriceEntry(
            capturedAt: Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: price)!,
            unitType: unit,
            storeChainId: chainID,
            storeChainNameSnapshot: chainName,
            photoAssetId: ""
        )
    }

    private func basket(_ name: String) -> [BasketItemInput] {
        [BasketItemInput(itemKey: ItemKeyNormalizer.normalize(name), displayName: name)]
    }

    // MARK: - #1 Substitution unit-family safety in package mode

    @Test
    func packageModeSuggestsSubstituteInSameUnitFamily() {
        // Both priced per-each: soy milk ($3.00/each) is ≥25% cheaper than almond milk ($5.00/each)
        // and shares the unit family, so it's a valid substitute.
        let entries = [
            packageEntry(name: "Almond Milk", price: "5.00", unit: .each, chainID: storeA, chainName: "StoreA"),
            packageEntry(name: "Soy Milk", price: "3.00", unit: .each, chainID: storeA, chainName: "StoreA")
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basket("Almond Milk"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.substitutions.first?.substituteItemName == "Soy Milk")
    }

    @Test
    func packageModeRejectsSubstituteFromDifferentUnitFamily() {
        // Almond milk is $5.00/each; soy milk is $1.00/L. The per-litre number looks cheaper but is a
        // different unit family — comparing them is meaningless, so NO substitute is suggested. This is
        // the exact gap the production path (useNormalizedPricing: false) previously left open.
        let entries = [
            packageEntry(name: "Almond Milk", price: "5.00", unit: .each, chainID: storeA, chainName: "StoreA"),
            packageEntry(name: "Soy Milk", price: "1.00", unit: .liter, chainID: storeA, chainName: "StoreA")
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basket("Almond Milk"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.substitutions.isEmpty)
    }

    @Test
    func packageModeRejectsSubstituteSharingOnlyANonHeadToken() {
        // "Apple Juice" vs "Apple Sauce" share the modifier "apple", but their head nouns (juice/sauce)
        // differ — they're different products. Even a much cheaper apple sauce must NOT be offered as a
        // substitute for apple juice. Guards the other half of the head-noun rule (shared token must be
        // a head noun of one side), which the cheaper-same-family happy path doesn't exercise.
        let entries = [
            packageEntry(name: "Apple Juice", price: "5.00", unit: .each, chainID: storeA, chainName: "StoreA"),
            packageEntry(name: "Apple Sauce", price: "2.00", unit: .each, chainID: storeA, chainName: "StoreA")
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basket("Apple Juice"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.substitutions.isEmpty)
    }

    // MARK: - #2 Mixed-unit pooling in package-mode history

    @Test
    func packageModeHistoryExcludesIncompatibleCheaperUnit() {
        // Bananas recorded twice per-each and once per-kg. The per-kg $1.20 is numerically the lowest
        // but belongs to a different unit family, so it must NOT pool into the per-each history as the
        // "lowest" price. The dominant family (.each, 2 of 3) wins and the per-kg entry is dropped.
        let entries = [
            packageEntry(name: "Bananas", price: "4.00", unit: .each, chainID: storeA, chainName: "StoreA", capturedDaysAgo: 3),
            packageEntry(name: "Bananas", price: "4.50", unit: .each, chainID: storeA, chainName: "StoreA", capturedDaysAgo: 2),
            packageEntry(name: "Bananas", price: "1.20", unit: .kg, chainID: storeA, chainName: "StoreA", capturedDaysAgo: 1)
        ]

        let history = try! #require(
            PriceInsightEngine.computeItemHistory(
                itemKey: "Bananas",
                displayName: "Bananas",
                useNormalizedPricing: false,
                allEntries: entries,
                now: now
            )
        )

        #expect(history.observationCount == 2)
        #expect(history.lowest.price == Decimal(string: "4.00"))
        #expect(history.highest.price == Decimal(string: "4.50"))
        #expect(!history.timeline.contains { $0.price == Decimal(string: "1.20") })
    }

    @Test
    func packageModeBasketUsesDominantUnitNotIncompatibleCheaperOne() {
        // The same mixed-unit item in the basket: the per-store total must use the dominant per-each
        // price ($4.00), never the incompatible per-kg $1.20.
        let entries = [
            packageEntry(name: "Bananas", price: "4.00", unit: .each, chainID: storeA, chainName: "StoreA", capturedDaysAgo: 3),
            packageEntry(name: "Bananas", price: "4.50", unit: .each, chainID: storeA, chainName: "StoreA", capturedDaysAgo: 2),
            packageEntry(name: "Bananas", price: "1.20", unit: .kg, chainID: storeA, chainName: "StoreA", capturedDaysAgo: 1)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basket("Bananas"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.cheapestSingleStore?.knownTotal == Decimal(string: "4.00"))
    }

    // MARK: - Substitution staleness gate

    @Test
    func doesNotSuggestStaleSubstitute() {
        // Soy milk is cheaper and the same unit family, but its only price is ~4 months old. A stale
        // price must not be offered as a current cheaper alternative, so no substitution is suggested.
        let entries = [
            packageEntry(name: "Almond Milk", price: "5.00", unit: .each, chainID: storeA, chainName: "StoreA", capturedDaysAgo: 1),
            packageEntry(name: "Soy Milk", price: "3.00", unit: .each, chainID: storeA, chainName: "StoreA", capturedDaysAgo: 120)
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basket("Almond Milk"),
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        #expect(estimate.substitutions.isEmpty)
    }
}
