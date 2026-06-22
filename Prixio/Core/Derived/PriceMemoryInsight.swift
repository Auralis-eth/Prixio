import Foundation

/// A conservative, history-relative read on a price the user is about to save: is it below, near,
/// or above what they have usually paid for this same item (in the same unit)? Derived from saved
/// `PriceEntry` history only — it never makes a claim without enough evidence.
struct PriceMemoryInsight: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case belowUsual
        case nearUsual
        case aboveUsual
    }

    let level: Level
    let observationCount: Int
    let usualLow: Decimal
    let usualHigh: Decimal
    let unitType: UnitType
    /// Freshness of the most recent observation backing this insight.
    let freshness: StalenessBucket
}

extension PriceInsightEngine {
    /// The minimum number of comparable observations required before we make any usual/unusual
    /// claim. Below this the history is too thin to be trustworthy, so `computePriceMemory` returns
    /// `nil` and the UI stays silent.
    static let priceMemoryMinObservations = 3

    /// Half-width of the "near usual" band, expressed as a fraction of the median (±10%).
    static let priceMemoryBandTolerance = Decimal(string: "0.10")!

    /// Compares a candidate price against the user's own history for the same normalized item and
    /// unit. Returns `nil` when the item name is empty or there are fewer than
    /// `priceMemoryMinObservations` comparable entries.
    ///
    /// Only entries sharing the candidate's `unitType` are considered, so incompatible unit
    /// families (e.g. per-kg vs each) are never compared as if equivalent.
    static func computePriceMemory(
        itemName: String,
        currentPrice: Decimal,
        unitType: UnitType,
        allEntries: [PriceEntry],
        now: Date = .now
    ) -> PriceMemoryInsight? {
        let normalizedKey = ItemKeyNormalizer.normalize(itemName)
        guard !normalizedKey.isEmpty else {
            return nil
        }

        let matchingEntries = allEntries.filter {
            $0.itemNameNormalized == normalizedKey && $0.unitType == unitType
        }
        guard matchingEntries.count >= priceMemoryMinObservations else {
            return nil
        }

        let sortedPrices = matchingEntries.map(\.priceValue).sorted(by: <)
        let median = median(of: sortedPrices) ?? sortedPrices[0]
        let usualLow = median * (Decimal(1) - priceMemoryBandTolerance)
        let usualHigh = median * (Decimal(1) + priceMemoryBandTolerance)

        let level: PriceMemoryInsight.Level
        if currentPrice < usualLow {
            level = .belowUsual
        } else if currentPrice > usualHigh {
            level = .aboveUsual
        } else {
            level = .nearUsual
        }

        let freshestCapture = matchingEntries.map(\.capturedAt).max() ?? now

        return PriceMemoryInsight(
            level: level,
            observationCount: matchingEntries.count,
            usualLow: usualLow,
            usualHigh: usualHigh,
            unitType: unitType,
            freshness: stalenessBucket(for: freshestCapture, now: now)
        )
    }
}

/// A scan-review read on the *current store*: for the matched item, is this store usually cheaper,
/// about average, or more expensive than the other stores the user has seen it at? Derived from saved
/// `PriceEntry` history (same item, same unit), chain-first.
struct StoreMemoryInsight: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case cheaperHere
        case averageHere
        case expensiveHere
    }

    let level: Level
    /// Display name of the current store/chain.
    let storeName: String
    /// Comparable observations for this item at the current store/chain.
    let observationCount: Int
    /// Number of distinct stores/chains compared.
    let storeCount: Int
    /// Freshness of the most recent observation at the current store.
    let freshness: StalenessBucket
}

extension PriceInsightEngine {
    /// Compares the current store's typical price for an item against the other stores' typical prices.
    /// Chain-first (groups by chain-name snapshot, falling back to location name). Returns `nil` unless
    /// the item has comparable history at the current store AND at least one other store, with at least
    /// `priceMemoryMinObservations` observations overall — so a cheaper/expensive claim is grounded and
    /// not an overfit to a single old scan. Same unit family as `computePriceMemory`.
    static func computeStoreMemory(
        itemName: String,
        currentStoreName: String?,
        unitType: UnitType,
        allEntries: [PriceEntry],
        now: Date = .now
    ) -> StoreMemoryInsight? {
        let normalizedKey = ItemKeyNormalizer.normalize(itemName)
        let storeName = (currentStoreName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty, !storeName.isEmpty else {
            return nil
        }

        let matching = allEntries.filter {
            $0.itemNameNormalized == normalizedKey && $0.unitType == unitType
        }

        func storeKey(for entry: PriceEntry) -> String {
            (entry.storeChainNameSnapshot ?? entry.storeLocationNameSnapshot ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        let grouped = Dictionary(grouping: matching.filter { !storeKey(for: $0).isEmpty }, by: storeKey(for:))
        let totalObservations = grouped.values.reduce(0) { $0 + $1.count }
        let currentKey = storeName.lowercased()
        guard
            grouped.count >= 2,
            totalObservations >= priceMemoryMinObservations,
            let currentGroup = grouped[currentKey]
        else {
            return nil
        }

        let currentMedian = median(of: currentGroup.map(\.priceValue).sorted(by: <)) ?? currentGroup[0].priceValue
        let otherMedians = grouped
            .filter { $0.key != currentKey }
            .compactMap { median(of: $0.value.map(\.priceValue).sorted(by: <)) }
        guard let otherTypical = median(of: otherMedians.sorted(by: <)), otherTypical > 0 else {
            return nil
        }

        let level: StoreMemoryInsight.Level
        if currentMedian < otherTypical * (Decimal(1) - priceMemoryBandTolerance) {
            level = .cheaperHere
        } else if currentMedian > otherTypical * (Decimal(1) + priceMemoryBandTolerance) {
            level = .expensiveHere
        } else {
            level = .averageHere
        }

        let freshest = currentGroup.map(\.capturedAt).max() ?? now
        return StoreMemoryInsight(
            level: level,
            storeName: currentGroup.first?.storeChainNameSnapshot ?? storeName,
            observationCount: currentGroup.count,
            storeCount: grouped.count,
            freshness: stalenessBucket(for: freshest, now: now)
        )
    }
}
