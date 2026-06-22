import Foundation

/// One item the basket builder should price, identified by its normalized key with a display name
/// for surfacing missing-price warnings.
struct BasketItemInput: Equatable, Sendable {
    let itemKey: String
    let displayName: String
}

/// The cheapest recent price for a single item at a single store, used as the building block for
/// basket totals and the per-item split plan.
struct BasketStorePrice: Equatable, Sendable {
    let storeChainID: UUID?
    let storeLocationID: UUID?
    let storeName: String
    let price: Decimal
    let isStale: Bool
    /// Store coordinate (when known), used to weight how spread-out a split trip is so distant
    /// splits must clear a higher savings bar than nearby ones.
    var coordinateLat: Double? = nil
    var coordinateLon: Double? = nil

    /// Stable grouping identity: prefer the chain, then the specific location, and only fall back to
    /// the display name when neither id exists — so two distinct no-chain stores that happen to share
    /// a name are not merged into one.
    var identity: String {
        if let storeChainID {
            return "chain-\(storeChainID.uuidString)"
        }
        if let storeLocationID {
            return "loc-\(storeLocationID.uuidString)"
        }
        return "name-\(storeName)"
    }
}

/// An estimated basket total at one store, over the set of items that have a price *somewhere*.
struct StoreBasketEstimate: Identifiable, Equatable, Sendable {
    let storeChainID: UUID?
    let storeLocationID: UUID?
    let storeName: String
    let knownTotal: Decimal
    let knownItemCount: Int
    /// Display names of priced items this store does not have a price for.
    let missingItems: [String]
    let staleCount: Int

    /// Prefer the chain, then the location id, then the name — so two distinct no-chain stores with
    /// the same name remain separate rows rather than colliding in a `ForEach`.
    var id: String {
        if let storeChainID {
            return "chain-\(storeChainID.uuidString)"
        }
        if let storeLocationID {
            return "loc-\(storeLocationID.uuidString)"
        }
        return "name-\(storeName)"
    }

    /// True when this store has a price for every item that is priced anywhere.
    var coversAllPricedItems: Bool {
        missingItems.isEmpty
    }
}

/// A multi-store plan that buys each item at its cheapest store. Only surfaced when it beats the
/// best one-stop store by a meaningful margin (see `PriceInsightEngine.basketSplitMinSavings`).
struct SplitSuggestion: Equatable, Sendable {
    let stores: [StoreBasketEstimate]
    let combinedTotal: Decimal
    /// Savings versus the cheapest one-stop store, or `nil` when no single store covers every priced
    /// item (the split is then the only complete plan, with no one-stop baseline to compare against).
    let savingsVsSingle: Decimal?
}

/// A suggested cheaper alternative for a basket item: a different, similarly-named item the user has
/// priced for meaningfully less. Surfaced for the user to judge, never auto-applied.
struct BasketSubstitution: Equatable, Sendable {
    let originalItemName: String
    let originalPrice: Decimal
    let substituteItemName: String
    let substitutePrice: Decimal
    let substituteStoreName: String

    var savings: Decimal {
        originalPrice - substitutePrice
    }
}

/// The full basket-builder result: per-store totals, the cheapest one-stop option, an optional
/// split plan, and explicit coverage so missing prices are never silently treated as zero.
struct BasketEstimate: Equatable, Sendable {
    /// Per-store estimates ranked: stores covering every priced item first, then by coverage and
    /// total.
    let perStore: [StoreBasketEstimate]
    /// Cheapest store that covers every priced item, or the best-coverage store when none covers
    /// all.
    let cheapestSingleStore: StoreBasketEstimate?
    let split: SplitSuggestion?
    /// Number of distinct items with a price at any store.
    let pricedItemCount: Int
    /// Total distinct items requested.
    let totalItemCount: Int
    /// Display names of items with no price anywhere.
    let unpricedItemNames: [String]
    /// Cheaper similar-item suggestions, highest savings first.
    let substitutions: [BasketSubstitution]

    static let empty = BasketEstimate(
        perStore: [],
        cheapestSingleStore: nil,
        split: nil,
        pricedItemCount: 0,
        totalItemCount: 0,
        unpricedItemNames: [],
        substitutions: []
    )

    var hasAnyPrices: Bool {
        pricedItemCount > 0
    }
}
