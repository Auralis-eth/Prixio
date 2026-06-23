import Foundation
import Testing
@testable import Prixio

/// Coverage for the basket builder's **normalized (per-unit) pricing** path.
///
/// `BasketEstimateTests` exercises only `useNormalizedPricing: false` (package prices). This suite
/// fills the complementary gap: when `useNormalizedPricing: true`, `computeBasketEstimate` /
/// `pricesByStore` must compare on `normalizedUnitPriceValue`, drop entries that lack a normalized
/// price, and keep a single unit family (never blending e.g. $/kg with $/100 g) so a deceptively
/// small per-100 g number can't undercut a $/kg comparison.
struct BasketEstimateNormalizedPricingTests {
    private let costco = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!
    private let walmart = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let loblaws = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Builds a normalized-priced entry. `packagePrice` and `normalizedPrice` are intentionally
    /// independent so tests can prove the engine compares on the *normalized* value, not the package
    /// value.
    private func normalizedEntry(
        name: String,
        packagePrice: String,
        normalizedPrice: String?,
        normalizedUnit: UnitType?,
        chainID: UUID,
        chainName: String,
        capturedDaysAgo: Int = 1
    ) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: Decimal(string: packagePrice)!,
            unitType: .each,
            normalizedUnitPriceValue: normalizedPrice.flatMap { Decimal(string: $0) },
            normalizedUnitType: normalizedUnit,
            storeChainId: chainID,
            storeChainNameSnapshot: chainName,
            photoAssetId: ""
        )
    }

    private func basketItems(_ names: String...) -> [BasketItemInput] {
        names.map { BasketItemInput(itemKey: ItemKeyNormalizer.normalize($0), displayName: $0) }
    }

    // MARK: - Happy path

    @Test
    func computeBasketEstimate_picksCheapestByNormalizedUnitPrice_notPackagePrice() {
        // StoreA's bag costs more (12.00) but is cheaper per kg (3.00/kg); StoreB's bag is cheaper
        // (5.00) but pricier per kg (5.00/kg). Under normalized pricing, StoreA must win.
        let entries = [
            normalizedEntry(name: "Rice", packagePrice: "12.00", normalizedPrice: "3.00", normalizedUnit: .kg, chainID: costco, chainName: "Costco"),
            normalizedEntry(name: "Rice", packagePrice: "5.00", normalizedPrice: "5.00", normalizedUnit: .kg, chainID: walmart, chainName: "Walmart")
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Rice"),
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        )

        #expect(estimate.pricedItemCount == 1)
        #expect(estimate.cheapestSingleStore?.storeName == "Costco")
        // The total reflects the normalized unit price (3.00), not either package price.
        #expect(estimate.cheapestSingleStore?.knownTotal == Decimal(string: "3.00"))
    }

    // MARK: - Unit-family safety

    @Test
    func computeBasketEstimate_excludesMinorityUnitFamily_soSmallerUnitDoesNotFakeLowPrice() {
        // Two stores price cheese per kg; a third prices it per 100 g. The per-100 g number (2.00) is
        // numerically the smallest, but it belongs to a different unit family and must be dropped so
        // it cannot masquerade as the cheapest. Dominant family is kg (2 entries vs 1).
        let entries = [
            normalizedEntry(name: "Cheese", packagePrice: "20.00", normalizedPrice: "10.00", normalizedUnit: .kg, chainID: costco, chainName: "Costco"),
            normalizedEntry(name: "Cheese", packagePrice: "16.00", normalizedPrice: "8.00", normalizedUnit: .kg, chainID: walmart, chainName: "Walmart"),
            normalizedEntry(name: "Cheese", packagePrice: "4.00", normalizedPrice: "2.00", normalizedUnit: .hundredGrams, chainID: loblaws, chainName: "Loblaws")
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Cheese"),
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        )

        // Loblaws (per-100 g, minority family) is excluded entirely.
        #expect(estimate.perStore.count == 2)
        #expect(estimate.perStore.allSatisfy { $0.storeName != "Loblaws" })
        // Cheapest within the dominant kg family is Walmart at 8.00/kg.
        #expect(estimate.cheapestSingleStore?.storeName == "Walmart")
        #expect(estimate.cheapestSingleStore?.knownTotal == Decimal(string: "8.00"))
    }

    // MARK: - Edge / unhappy paths

    @Test
    func computeBasketEstimate_treatsPackageOnlyItemAsUnpriced_underNormalizedMode() {
        // The only entry for Butter has no normalized unit price, so under normalized pricing it has
        // no comparable price and must surface as unpriced rather than silently using the package price.
        let entries = [
            normalizedEntry(name: "Butter", packagePrice: "6.00", normalizedPrice: nil, normalizedUnit: nil, chainID: costco, chainName: "Costco")
        ]

        let estimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems("Butter"),
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        )

        #expect(estimate.hasAnyPrices == false)
        #expect(estimate.pricedItemCount == 0)
        #expect(estimate.unpricedItemNames == ["Butter"])
        #expect(estimate.cheapestSingleStore == nil)
    }

    @Test
    func pricesByStore_returnsCheapestNormalizedPricePerStore() {
        // Two captures at Costco for the same item; the cheaper normalized price should represent the
        // store. Walmart contributes a single, pricier entry.
        let entries = [
            normalizedEntry(name: "Milk", packagePrice: "9.00", normalizedPrice: "3.00", normalizedUnit: .liter, chainID: costco, chainName: "Costco"),
            normalizedEntry(name: "Milk", packagePrice: "8.00", normalizedPrice: "2.50", normalizedUnit: .liter, chainID: costco, chainName: "Costco"),
            normalizedEntry(name: "Milk", packagePrice: "4.00", normalizedPrice: "4.00", normalizedUnit: .liter, chainID: walmart, chainName: "Walmart")
        ]

        let byStore = PriceInsightEngine.pricesByStore(
            itemKey: "Milk",
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        )

        #expect(byStore.count == 2)
        let costcoKey = "chain-\(costco.uuidString)"
        let walmartKey = "chain-\(walmart.uuidString)"
        #expect(byStore[costcoKey]?.price == Decimal(string: "2.50"))
        #expect(byStore[walmartKey]?.price == Decimal(string: "4.00"))
    }

    @Test
    func pricesByStore_flagsStaleEntriesByCaptureAge() {
        // A single entry captured ~120 days ago is well past the staleness window, so its store price
        // must be flagged stale (the recent-window filter falls back to all entries when none are recent).
        let entries = [
            normalizedEntry(name: "Eggs", packagePrice: "6.00", normalizedPrice: "6.00", normalizedUnit: .each, chainID: costco, chainName: "Costco", capturedDaysAgo: 120)
        ]

        let byStore = PriceInsightEngine.pricesByStore(
            itemKey: "Eggs",
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        )

        let costcoKey = "chain-\(costco.uuidString)"
        #expect(byStore[costcoKey]?.isStale == true)
    }

    @Test
    func pricesByStore_returnsEmpty_whenNoNormalizedDataUnderNormalizedMode() {
        // Package-only data + normalized mode => nothing comparable => empty result (never a zero price).
        let entries = [
            normalizedEntry(name: "Bread", packagePrice: "3.00", normalizedPrice: nil, normalizedUnit: nil, chainID: costco, chainName: "Costco")
        ]

        let byStore = PriceInsightEngine.pricesByStore(
            itemKey: "Bread",
            useNormalizedPricing: true,
            allEntries: entries,
            now: now
        )

        #expect(byStore.isEmpty)
    }
}
