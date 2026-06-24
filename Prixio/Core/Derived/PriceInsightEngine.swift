import Foundation

enum PriceInsightEngine {
    static let recentWindowDays = 30

    struct BestStoreSuggestion: Equatable, Sendable {
        let entryID: UUID
        let itemKey: String
        let storeChainID: UUID?
        let storeLocationID: UUID?
        let storeChainName: String?
        let storeLocationName: String?
        let comparablePrice: Decimal
        let packagePrice: Decimal
        let comparableUnitType: UnitType
        let capturedAt: Date
        let ageDays: Int
        let stalenessBucket: StalenessBucket
        let usedNormalizedPricing: Bool
        let storeCoordinateLat: Double?
        let storeCoordinateLon: Double?

        var isStale: Bool {
            stalenessBucket.isStale
        }
    }

    struct TripWinnerSummary: Equatable, Sendable {
        struct Store: Hashable, Equatable, Sendable {
            let chainID: UUID?
            let chainName: String
        }

        let winner: Store
        let winnerCount: Int
        let totalItems: Int
        let staleCount: Int
        let rankedCounts: [(store: Store, count: Int)]

        static func == (lhs: TripWinnerSummary, rhs: TripWinnerSummary) -> Bool {
            lhs.winner == rhs.winner &&
            lhs.winnerCount == rhs.winnerCount &&
            lhs.totalItems == rhs.totalItems &&
            lhs.staleCount == rhs.staleCount &&
            lhs.rankedCounts.elementsEqual(rhs.rankedCounts) { left, right in
                left.store == right.store && left.count == right.count
            }
        }
    }

    static func computeBestStoreForItem(
        itemKey: String,
        allEntries: [PriceEntry],
        now: Date = .now
    ) -> BestStoreSuggestion? {
        let normalizedKey = ItemKeyNormalizer.normalize(itemKey)
        let matchingEntries = allEntries.filter {
            ItemKeyNormalizer.matches(queryKey: normalizedKey, entryKey: $0.itemNameNormalized)
        }
        guard !matchingEntries.isEmpty else {
            return nil
        }

        let useNormalizedPricing = matchingEntries.contains { $0.normalizedUnitPriceValue != nil }
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: now) ?? now
        let candidateEntries = comparableEntries(from: matchingEntries, useNormalizedPricing: useNormalizedPricing)
        let recentEntries = candidateEntries.filter { $0.capturedAt >= recentCutoff }
        let pool = recentEntries.isEmpty ? candidateEntries : recentEntries

        guard let bestEntry = bestEntry(in: pool, useNormalizedPricing: useNormalizedPricing) else {
            return nil
        }

        let ageDays = ageInDays(since: bestEntry.capturedAt, now: now)
        return BestStoreSuggestion(
            entryID: bestEntry.id,
            itemKey: normalizedKey,
            storeChainID: bestEntry.storeChainId,
            storeLocationID: bestEntry.storeLocationId,
            storeChainName: bestEntry.storeChainNameSnapshot,
            storeLocationName: bestEntry.storeLocationNameSnapshot,
            comparablePrice: comparablePrice(for: bestEntry, useNormalizedPricing: useNormalizedPricing),
            packagePrice: bestEntry.priceValue,
            comparableUnitType: comparableUnitType(for: bestEntry, useNormalizedPricing: useNormalizedPricing),
            capturedAt: bestEntry.capturedAt,
            ageDays: ageDays,
            stalenessBucket: stalenessBucket(for: bestEntry.capturedAt, now: now),
            usedNormalizedPricing: useNormalizedPricing,
            storeCoordinateLat: bestEntry.storeCoordinateLat,
            storeCoordinateLon: bestEntry.storeCoordinateLon
        )
    }

    /// Builds the full item-history summary used by the item detail surface: latest, lowest,
    /// highest, the "usual" band (median ± tolerance), an anomaly read on the latest price, and a
    /// chronological timeline for charting. Returns `nil` when no comparable entries exist.
    ///
    /// `useNormalizedPricing` selects per-unit (normalized) vs per-package comparison so the
    /// summary tracks whichever mode the UI is showing. When fewer than
    /// `priceMemoryMinObservations` entries exist, the usual band is suppressed and the anomaly is
    /// reported as `.insufficientData`.
    static func computeItemHistory(
        itemKey: String,
        displayName: String,
        useNormalizedPricing: Bool,
        allEntries: [PriceEntry],
        scope: PriceHistoryScope = .allStores,
        now: Date = .now
    ) -> ItemPriceHistory? {
        let normalizedKey = ItemKeyNormalizer.normalize(itemKey)
        let matchingEntries = allEntries
            .filter { ItemKeyNormalizer.matches(queryKey: normalizedKey, entryKey: $0.itemNameNormalized) }
            .filter { entryMatches(scope: scope, entry: $0) }
        let candidates = comparableEntries(from: matchingEntries, useNormalizedPricing: useNormalizedPricing)
        guard !candidates.isEmpty else {
            return nil
        }

        let timeline = candidates
            .sorted { $0.capturedAt < $1.capturedAt }
            .map { point(for: $0, useNormalizedPricing: useNormalizedPricing) }

        guard
            let latest = timeline.last,
            let lowest = timeline.min(by: { $0.price < $1.price }),
            let highest = timeline.max(by: { $0.price < $1.price })
        else {
            return nil
        }

        let sortedPrices = timeline.map(\.price).sorted(by: <)
        let observationCount = timeline.count
        let hasUsualBand = observationCount >= priceMemoryMinObservations
        let median = median(of: sortedPrices) ?? latest.price

        let usualLow: Decimal
        let usualHigh: Decimal
        let anomaly: PriceAnomaly
        if hasUsualBand, median > 0 {
            usualLow = median * (Decimal(1) - priceMemoryBandTolerance)
            usualHigh = median * (Decimal(1) + priceMemoryBandTolerance)
            anomaly = classifyAnomaly(latest: latest.price, median: median)
        } else {
            usualLow = median
            usualHigh = median
            anomaly = .insufficientData
        }

        return ItemPriceHistory(
            itemKey: normalizedKey,
            displayName: displayName,
            scope: scope,
            observationCount: observationCount,
            latest: latest,
            lowest: lowest,
            highest: highest,
            median: median,
            usualLow: usualLow,
            usualHigh: usualHigh,
            hasUsualBand: hasUsualBand,
            freshness: stalenessBucket(for: latest.date, now: now),
            anomaly: anomaly,
            timeline: timeline
        )
    }

    /// Classifies a price against a historical median. The "usual" band is ± `priceMemoryBandTolerance`
    /// (10%); a move beyond twice that band is treated as a strong signal (`likelySale` / `unusuallyHigh`).
    static func classifyAnomaly(latest: Decimal, median: Decimal) -> PriceAnomaly {
        guard median > 0 else {
            return .insufficientData
        }
        let strongBand = priceMemoryBandTolerance * 2
        let usualLow = median * (Decimal(1) - priceMemoryBandTolerance)
        let usualHigh = median * (Decimal(1) + priceMemoryBandTolerance)
        let strongLow = median * (Decimal(1) - strongBand)
        let strongHigh = median * (Decimal(1) + strongBand)

        if latest <= strongLow {
            return .likelySale
        }
        if latest < usualLow {
            return .belowUsual
        }
        if latest >= strongHigh {
            return .unusuallyHigh
        }
        if latest > usualHigh {
            return .aboveUsual
        }
        return .nearUsual
    }

    /// Whether an entry belongs to a given history scope. Chain/location scopes match the relevant
    /// store-name snapshot case-insensitively; `allStores` matches everything.
    private static func entryMatches(scope: PriceHistoryScope, entry: PriceEntry) -> Bool {
        switch scope {
        case .allStores:
            return true
        case .chain(let name):
            return normalizedStoreName(entry.storeChainNameSnapshot) == normalizedStoreName(name)
        case .location(let name):
            return normalizedStoreName(entry.storeLocationNameSnapshot) == normalizedStoreName(name)
        }
    }

    private static func normalizedStoreName(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The store scopes that have history for an item, for offering a chain-vs-location breakdown.
    /// Always leads with `.allStores`, then each chain (most observations first), then locations for
    /// any entries that carry no chain — so chain-level history is preferred but no-chain stores are
    /// still reachable.
    static func availableStoreScopes(
        itemKey: String,
        allEntries: [PriceEntry]
    ) -> [PriceHistoryScope] {
        let normalizedKey = ItemKeyNormalizer.normalize(itemKey)
        let matching = allEntries.filter {
            ItemKeyNormalizer.matches(queryKey: normalizedKey, entryKey: $0.itemNameNormalized)
        }
        guard !matching.isEmpty else {
            return [.allStores]
        }

        func ranked(_ names: [String]) -> [String] {
            let counts: [String: Int] = names.reduce(into: [:]) { result, name in
                result[name, default: 0] += 1
            }
            return counts.keys.sorted { lhs, rhs in
                let lhsCount = counts[lhs] ?? 0
                let rhsCount = counts[rhs] ?? 0
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }

        let chainNames = matching.compactMap { entry -> String? in
            let name = (entry.storeChainNameSnapshot ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        let locationNamesWithoutChain = matching.compactMap { entry -> String? in
            guard (entry.storeChainNameSnapshot ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let name = (entry.storeLocationNameSnapshot ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }

        var scopes: [PriceHistoryScope] = [.allStores]
        scopes += ranked(chainNames).map { .chain(name: $0) }
        scopes += ranked(locationNamesWithoutChain).map { .location(name: $0) }
        // A single store offers no useful breakdown beyond "All stores".
        return scopes.count > 2 ? scopes : [.allStores]
    }

    static func computeTripWinner(
        suggestions: [BestStoreSuggestion],
        totalItems: Int
    ) -> TripWinnerSummary? {
        guard !suggestions.isEmpty, totalItems > 0 else {
            return nil
        }

        // Only fresh suggestions vote for the winner. `computeBestStoreForItem` falls back to the
        // cheapest price in ALL history when nothing is in the recent window, so a single months-old
        // scan could otherwise drive a confident "shop here" recommendation. Stale suggestions are
        // still counted in `staleCount` so the UI can explain how much of the basket lacked recent
        // prices — they just don't get a vote.
        let staleCount = suggestions.filter(\.isStale).count
        let voting = suggestions.filter { !$0.isStale }
        guard !voting.isEmpty else {
            return nil
        }

        let grouped = Dictionary(grouping: voting) { suggestion in
            TripWinnerSummary.Store(
                chainID: suggestion.storeChainID,
                chainName: suggestion.storeChainName ?? suggestion.storeLocationName ?? "Unknown"
            )
        }

        let rankedCounts = grouped
            .map { (store: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.store.chainName.localizedCaseInsensitiveCompare(rhs.store.chainName) == .orderedAscending
            }

        guard let winner = rankedCounts.first else {
            return nil
        }

        return TripWinnerSummary(
            winner: winner.store,
            winnerCount: winner.count,
            totalItems: totalItems,
            staleCount: staleCount,
            rankedCounts: rankedCounts
        )
    }

    /// Minimum absolute saving (in currency units) before a split trip is worth suggesting over a
    /// one-stop store.
    static let basketSplitMinSavings = Decimal(2)

    /// Minimum saving as a fraction of the one-stop total before a split trip is worth suggesting.
    static let basketSplitMinSavingsFraction = Decimal(5) / Decimal(100)

    /// Convenience penalty: each store a split adds beyond a single stop must "earn" at least this
    /// much extra saving. A 3-store split therefore has to beat a one-stop store by more than a
    /// 2-store split would — so the builder doesn't recommend running all over town for loose change.
    static let basketSplitPerExtraStopSavings = Decimal(string: "1.50")!

    /// Distance penalty: each kilometre of spread between the farthest two split stores adds this
    /// much to the required saving (capped by `basketSplitMaxDistancePenalty`). Only applied when the
    /// split stores carry coordinates.
    static let basketSplitPerKilometreSavings = Decimal(string: "0.15")!

    /// Upper bound on the distance penalty so a very spread-out split can't demand an absurd saving.
    static let basketSplitMaxDistancePenalty = Decimal(8)

    /// The cheapest recent price for a single item at each store, keyed by a stable store identity.
    /// Mirrors `computeBestStoreForItem`'s recent-window logic but keeps one entry per store.
    static func pricesByStore(
        itemKey: String,
        useNormalizedPricing: Bool,
        allEntries: [PriceEntry],
        now: Date = .now
    ) -> [String: BasketStorePrice] {
        let normalizedKey = ItemKeyNormalizer.normalize(itemKey)
        let matching = allEntries.filter {
            ItemKeyNormalizer.matches(queryKey: normalizedKey, entryKey: $0.itemNameNormalized)
        }
        let candidates = comparableEntries(from: matching, useNormalizedPricing: useNormalizedPricing)
        guard !candidates.isEmpty else {
            return [:]
        }

        let recentCutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: now) ?? now
        let grouped = Dictionary(grouping: candidates, by: storeIdentity(for:))

        var result: [String: BasketStorePrice] = [:]
        for (identity, entries) in grouped {
            let recent = entries.filter { $0.capturedAt >= recentCutoff }
            let pool = recent.isEmpty ? entries : recent
            guard let best = bestEntry(in: pool, useNormalizedPricing: useNormalizedPricing) else {
                continue
            }
            result[identity] = BasketStorePrice(
                storeChainID: best.storeChainId,
                storeLocationID: best.storeLocationId,
                storeName: best.storeChainNameSnapshot ?? best.storeLocationNameSnapshot ?? "Unknown",
                price: comparablePrice(for: best, useNormalizedPricing: useNormalizedPricing),
                isStale: stalenessBucket(for: best.capturedAt, now: now).isStale,
                coordinateLat: best.storeCoordinateLat,
                coordinateLon: best.storeCoordinateLon
            )
        }
        return result
    }

    /// Estimates the basket total at each store, the cheapest one-stop option, and an optional
    /// per-item split plan. Items without any price are reported in `unpricedItemNames` rather than
    /// treated as zero, and splits are only suggested when savings clear both thresholds.
    static func computeBasketEstimate(
        items: [BasketItemInput],
        useNormalizedPricing: Bool,
        allEntries: [PriceEntry],
        now: Date = .now
    ) -> BasketEstimate {
        // De-duplicate items by key, keeping the first display name.
        var seenKeys = Set<String>()
        let distinctItems = items.compactMap { item -> BasketItemInput? in
            let key = ItemKeyNormalizer.normalize(item.itemKey)
            guard !key.isEmpty, !seenKeys.contains(key) else {
                return nil
            }
            seenKeys.insert(key)
            return BasketItemInput(itemKey: key, displayName: item.displayName)
        }

        struct Accumulator {
            var storeChainID: UUID?
            var storeLocationID: UUID?
            var storeName: String
            var total: Decimal
            var coveredKeys: [String]
            var staleCount: Int
        }

        var accumulators: [String: Accumulator] = [:]
        var pricedItemKeys = Set<String>()
        var cheapestByItem: [String: BasketStorePrice] = [:]

        for item in distinctItems {
            let byStore = pricesByStore(
                itemKey: item.itemKey,
                useNormalizedPricing: useNormalizedPricing,
                allEntries: allEntries,
                now: now
            )
            guard !byStore.isEmpty else {
                continue
            }
            pricedItemKeys.insert(item.itemKey)

            var cheapest: BasketStorePrice?
            for (identity, price) in byStore {
                var accumulator = accumulators[identity] ?? Accumulator(
                    storeChainID: price.storeChainID,
                    storeLocationID: price.storeLocationID,
                    storeName: price.storeName,
                    total: 0,
                    coveredKeys: [],
                    staleCount: 0
                )
                accumulator.total += price.price
                accumulator.coveredKeys.append(item.itemKey)
                if price.isStale {
                    accumulator.staleCount += 1
                }
                accumulators[identity] = accumulator

                if let current = cheapest {
                    if price.price < current.price {
                        cheapest = price
                    }
                } else {
                    cheapest = price
                }
            }
            cheapestByItem[item.itemKey] = cheapest
        }

        let pricedItemCount = pricedItemKeys.count
        let unpricedItemNames = distinctItems
            .filter { !pricedItemKeys.contains($0.itemKey) }
            .map(\.displayName)

        let displayNameByKey = Dictionary(uniqueKeysWithValues: distinctItems.map { ($0.itemKey, $0.displayName) })
        let perStore = accumulators.values
            .map { accumulator -> StoreBasketEstimate in
                let covered = Set(accumulator.coveredKeys)
                let missing = pricedItemKeys
                    .subtracting(covered)
                    .compactMap { displayNameByKey[$0] }
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                return StoreBasketEstimate(
                    storeChainID: accumulator.storeChainID,
                    storeLocationID: accumulator.storeLocationID,
                    storeName: accumulator.storeName,
                    knownTotal: accumulator.total,
                    knownItemCount: accumulator.coveredKeys.count,
                    missingItems: missing,
                    staleCount: accumulator.staleCount
                )
            }
            .sorted(by: rankStoreEstimates)

        let storesCoveringAll = perStore.filter { $0.coversAllPricedItems && $0.knownItemCount == pricedItemCount }
        let oneStop = storesCoveringAll.min { $0.knownTotal < $1.knownTotal }
        let cheapestSingleStore = oneStop ?? perStore.first

        let split = makeSplit(
            oneStop: oneStop,
            cheapestByItem: cheapestByItem
        )

        let substitutionSuggestions = substitutions(
            pricedItemKeys: pricedItemKeys,
            cheapestByItem: cheapestByItem,
            displayNameByKey: displayNameByKey,
            allEntries: allEntries,
            useNormalizedPricing: useNormalizedPricing,
            now: now
        )

        return BasketEstimate(
            perStore: perStore,
            cheapestSingleStore: cheapestSingleStore,
            split: split,
            pricedItemCount: pricedItemCount,
            totalItemCount: distinctItems.count,
            unpricedItemNames: unpricedItemNames,
            substitutions: substitutionSuggestions
        )
    }

    /// Ranks store estimates for display: stores covering every priced item first, then by coverage
    /// (more items), then by lower total, then by name.
    private static func rankStoreEstimates(_ lhs: StoreBasketEstimate, _ rhs: StoreBasketEstimate) -> Bool {
        if lhs.coversAllPricedItems != rhs.coversAllPricedItems {
            return lhs.coversAllPricedItems
        }
        if lhs.knownItemCount != rhs.knownItemCount {
            return lhs.knownItemCount > rhs.knownItemCount
        }
        if lhs.knownTotal != rhs.knownTotal {
            return lhs.knownTotal < rhs.knownTotal
        }
        return lhs.storeName.localizedCaseInsensitiveCompare(rhs.storeName) == .orderedAscending
    }

    /// Builds a split suggestion (each item at its cheapest store). When a one-stop store covers every
    /// priced item, the split is only surfaced if it beats that store by enough to justify the extra
    /// stops and travel (see the convenience/distance penalties). When no single store covers
    /// everything, the split is the only complete plan, so it is surfaced without a savings claim.
    private static func makeSplit(
        oneStop: StoreBasketEstimate?,
        cheapestByItem: [String: BasketStorePrice]
    ) -> SplitSuggestion? {
        let picks = Array(cheapestByItem.values)
        let grouped = Dictionary(grouping: picks, by: \.identity)
        guard grouped.count > 1 else {
            return nil
        }

        let combinedTotal = picks.reduce(Decimal(0)) { $0 + $1.price }

        let savings: Decimal?
        if let oneStop {
            let delta = oneStop.knownTotal - combinedTotal
            let requiredSaving = requiredSplitSaving(
                stops: grouped.count,
                storeGroups: grouped
            )
            guard
                oneStop.knownTotal > 0,
                delta >= requiredSaving,
                delta / oneStop.knownTotal >= basketSplitMinSavingsFraction
            else {
                return nil
            }
            savings = delta
        } else {
            // No single store covers every priced item; the split is the only way to get everything.
            savings = nil
        }

        let stores = grouped.values
            .map { storePicks -> StoreBasketEstimate in
                let first = storePicks[0]
                return StoreBasketEstimate(
                    storeChainID: first.storeChainID,
                    storeLocationID: first.storeLocationID,
                    storeName: first.storeName,
                    knownTotal: storePicks.reduce(Decimal(0)) { $0 + $1.price },
                    knownItemCount: storePicks.count,
                    missingItems: [],
                    staleCount: storePicks.filter(\.isStale).count
                )
            }
            .sorted { $0.knownTotal > $1.knownTotal }

        return SplitSuggestion(stores: stores, combinedTotal: combinedTotal, savingsVsSingle: savings)
    }

    /// The minimum saving a split must clear over the one-stop store, accounting for convenience: a
    /// base floor, an extra-stop penalty that grows with the number of stores, and a distance penalty
    /// based on how far apart the split stores are when their coordinates are known.
    private static func requiredSplitSaving(
        stops: Int,
        storeGroups: [String: [BasketStorePrice]]
    ) -> Decimal {
        // Extra stops beyond the single store the split replaces (a 2-store split = 1 extra stop).
        let extraStops = max(0, stops - 1)
        let stopPenalty = basketSplitPerExtraStopSavings * Decimal(extraStops)

        let coordinates = storeGroups.values.compactMap { group -> (lat: Double, lon: Double)? in
            guard let lat = group.first?.coordinateLat, let lon = group.first?.coordinateLon else {
                return nil
            }
            return (lat, lon)
        }
        var maxKilometres = 0.0
        for i in coordinates.indices {
            for j in coordinates.indices where j > i {
                maxKilometres = max(
                    maxKilometres,
                    haversineKilometres(coordinates[i], coordinates[j])
                )
            }
        }
        let rawDistancePenalty = basketSplitPerKilometreSavings * Decimal(maxKilometres)
        let distancePenalty = min(basketSplitMaxDistancePenalty, rawDistancePenalty)

        // The base floor and stop penalty cover the same "is it worth a detour" concern, so take the
        // larger of the two rather than stacking them, then add travel distance on top.
        return max(basketSplitMinSavings, stopPenalty) + distancePenalty
    }

    /// Great-circle distance between two coordinates in kilometres (Haversine). Kept self-contained
    /// so the engine stays a pure Foundation type with no CoreLocation dependency.
    private static func haversineKilometres(
        _ a: (lat: Double, lon: Double),
        _ b: (lat: Double, lon: Double)
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180

        let sinLat = sin(dLat / 2)
        let sinLon = sin(dLon / 2)
        let latTerm: Double = sinLat * sinLat
        let lonTerm: Double = sinLon * sinLon * cos(lat1) * cos(lat2)
        let h = latTerm + lonTerm
        return 2 * earthRadiusKm * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Stable per-store grouping identity: prefer the chain, fall back to the snapshot name.
    /// A substitute must be at least this fraction cheaper than the basket item to be suggested.
    static let substitutionMinSavingsFraction = Decimal(1) / Decimal(4) // 25%

    /// Cheapest comparable price for every distinct item in history, keyed by normalized item name.
    /// Used as the candidate pool for substitution suggestions.
    private static func cheapestByDistinctItem(
        allEntries: [PriceEntry],
        useNormalizedPricing: Bool,
        now: Date
    ) -> [String: (name: String, price: Decimal, store: String, unitFamily: UnitType?)] {
        // Substitutes are only offered from recent evidence: a stale (e.g. months-old) price must not
        // be presented as a current cheaper alternative, so candidates outside the recent window are
        // dropped (no fall-back to old data, unlike per-item store pricing where some price beats none).
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: now) ?? now
        var result: [String: (name: String, price: Decimal, store: String, unitFamily: UnitType?)] = [:]
        for (key, entries) in Dictionary(grouping: allEntries, by: \.itemNameNormalized) {
            let comparable = comparableEntries(from: entries, useNormalizedPricing: useNormalizedPricing)
                .filter { $0.capturedAt >= recentCutoff }
            guard let best = bestEntry(in: comparable, useNormalizedPricing: useNormalizedPricing) else {
                continue
            }
            result[key] = (
                name: best.itemNameRaw,
                price: comparablePrice(for: best, useNormalizedPricing: useNormalizedPricing),
                store: best.storeChainNameSnapshot ?? best.storeLocationNameSnapshot ?? "Unknown",
                // The unit family of the comparable price, in either mode: the normalized unit ($/L,
                // $/kg…) when normalized, otherwise the package `unitType` ($/each, $/kg loose…).
                // Substitutions must stay within one family in BOTH modes (see `substitutions`).
                unitFamily: comparableUnitType(for: best, useNormalizedPricing: useNormalizedPricing)
            )
        }
        return result
    }

    /// Whether two normalized item names are close enough to suggest one as a substitute for the other.
    /// Conservative: they must share a token (length ≥ 3) that is the head noun (last token) of at least
    /// one of them — so "almond milk"/"soy milk" match on "milk", but "apple juice"/"apple sauce" (shared
    /// "apple", not a head noun) do not.
    private static func areSubstitutable(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs != rhs else {
            return false
        }
        let lhsTokens = lhs.split(separator: " ").map(String.init)
        let rhsTokens = rhs.split(separator: " ").map(String.init)
        let shared = Set(lhsTokens).intersection(rhsTokens).filter { $0.count >= 3 }
        guard !shared.isEmpty else {
            return false
        }
        let lhsHead = lhsTokens.last
        let rhsHead = rhsTokens.last
        return (lhsHead.map(shared.contains) ?? false) || (rhsHead.map(shared.contains) ?? false)
    }

    /// Builds cheaper-alternative suggestions for the priced basket items: for each, the cheapest
    /// similarly-named item in history that beats it by at least `substitutionMinSavingsFraction`.
    private static func substitutions(
        pricedItemKeys: Set<String>,
        cheapestByItem: [String: BasketStorePrice],
        displayNameByKey: [String: String],
        allEntries: [PriceEntry],
        useNormalizedPricing: Bool,
        now: Date
    ) -> [BasketSubstitution] {
        let catalog = cheapestByDistinctItem(allEntries: allEntries, useNormalizedPricing: useNormalizedPricing, now: now)
        var result: [BasketSubstitution] = []
        for key in pricedItemKeys {
            guard let original = cheapestByItem[key] else {
                continue
            }
            // A substitute is only comparable when it shares the basket item's unit family — in BOTH
            // modes. Normalized prices are per-unit ($/L vs $/each); package prices are shelf prices in
            // `unitType` ($/each bag vs $/kg loose). Comparing across families would fire a meaningless
            // "cheaper" suggestion, so we require equality (a nil original family suggests nothing).
            let originalFamily = catalog[key]?.unitFamily
            let ceiling = original.price * (Decimal(1) - substitutionMinSavingsFraction)
            var best: (name: String, price: Decimal, store: String, unitFamily: UnitType?)?
            for (otherKey, candidate) in catalog where otherKey != key {
                guard areSubstitutable(key, otherKey), candidate.price <= ceiling else {
                    continue
                }
                if candidate.unitFamily != originalFamily {
                    continue
                }
                if let current = best {
                    if candidate.price < current.price {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
            if let best {
                result.append(BasketSubstitution(
                    originalItemName: displayNameByKey[key] ?? key,
                    originalPrice: original.price,
                    substituteItemName: best.name,
                    substitutePrice: best.price,
                    substituteStoreName: best.store
                ))
            }
        }
        return result.sorted { $0.savings > $1.savings }
    }

    private static func storeIdentity(for entry: PriceEntry) -> String {
        if let chainID = entry.storeChainId {
            return "chain-\(chainID.uuidString)"
        }
        if let locationID = entry.storeLocationId {
            return "loc-\(locationID.uuidString)"
        }
        return "name-\(entry.storeChainNameSnapshot ?? entry.storeLocationNameSnapshot ?? "unknown")"
    }

    static func ageInDays(since capturedAt: Date, now: Date = .now) -> Int {
        max(0, Int(now.timeIntervalSince(capturedAt) / 86_400))
    }

    static func stalenessBucket(for capturedAt: Date, now: Date = .now) -> StalenessBucket {
        let ageDays = ageInDays(since: capturedAt, now: now)
        switch ageDays {
        case 0...7:
            return .fresh
        case 8...30:
            return .aging
        case 31...90:
            return .stale
        default:
            return .veryStale
        }
    }

    /// Median of an already-ascending-sorted list of prices. Single source of truth for the
    /// "usual" math shared by `computePriceMemory` and `computeItemHistory`.
    static func median(of sortedValues: [Decimal]) -> Decimal? {
        guard !sortedValues.isEmpty else {
            return nil
        }
        let count = sortedValues.count
        if count % 2 == 1 {
            return sortedValues[count / 2]
        }
        return (sortedValues[count / 2 - 1] + sortedValues[count / 2]) / 2
    }

    private static func point(
        for entry: PriceEntry,
        useNormalizedPricing: Bool
    ) -> PricePoint {
        PricePoint(
            entryID: entry.id,
            date: entry.capturedAt,
            price: comparablePrice(for: entry, useNormalizedPricing: useNormalizedPricing),
            unitType: comparableUnitType(for: entry, useNormalizedPricing: useNormalizedPricing),
            storeName: entry.storeChainNameSnapshot ?? entry.storeLocationNameSnapshot,
            usedNormalizedPricing: useNormalizedPricing
        )
    }

    private static func comparableEntries(
        from entries: [PriceEntry],
        useNormalizedPricing: Bool
    ) -> [PriceEntry] {
        guard useNormalizedPricing else {
            // Package mode compares `priceValue`, the shelf price expressed in `unitType`. A $/each
            // package price and a $/kg loose price are not comparable, so blending them would produce
            // a meaningless lowest/median/cheapest pick (and the basket builder runs in this mode).
            // Keep only the dominant `unitType` family — the package-mode mirror of the guard below.
            guard let dominantUnit = dominantPackageUnitType(in: entries) else {
                return entries
            }
            return entries.filter { $0.unitType == dominantUnit }
        }
        let normalized = entries.filter { $0.normalizedUnitPriceValue != nil }
        // Only compare within a single unit family. Blending e.g. $/kg with $/each or $/100g would
        // produce a meaningless lowest/median/usual band and fire false anomaly flags, so we keep
        // only the dominant family — mirroring the per-unit guard in `computePriceMemory`.
        guard let dominantUnit = dominantNormalizedUnitType(in: normalized) else {
            return normalized
        }
        return normalized.filter { $0.normalizedUnitType == dominantUnit }
    }

    /// The package `unitType` with the most observations (ties broken by the most recent capture).
    /// Returns `nil` only for an empty input. Package mode's analogue of `dominantNormalizedUnitType`.
    private static func dominantPackageUnitType(in entries: [PriceEntry]) -> UnitType? {
        guard !entries.isEmpty else {
            return nil
        }
        return Dictionary(grouping: entries, by: \.unitType)
            .max { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count < rhs.value.count
                }
                let lhsLatest = lhs.value.map(\.capturedAt).max() ?? .distantPast
                let rhsLatest = rhs.value.map(\.capturedAt).max() ?? .distantPast
                return lhsLatest < rhsLatest
            }?
            .key
    }

    /// The normalized unit family with the most observations (ties broken by the most recent
    /// capture), or `nil` when no entry carries a normalized unit type.
    private static func dominantNormalizedUnitType(in entries: [PriceEntry]) -> UnitType? {
        let typed = entries.compactMap { entry -> (unit: UnitType, capturedAt: Date)? in
            guard let unit = entry.normalizedUnitType else {
                return nil
            }
            return (unit, entry.capturedAt)
        }
        guard !typed.isEmpty else {
            return nil
        }
        return Dictionary(grouping: typed, by: \.unit)
            .max { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count < rhs.value.count
                }
                let lhsLatest = lhs.value.map(\.capturedAt).max() ?? .distantPast
                let rhsLatest = rhs.value.map(\.capturedAt).max() ?? .distantPast
                return lhsLatest < rhsLatest
            }?
            .key
    }

    private static func bestEntry(
        in entries: [PriceEntry],
        useNormalizedPricing: Bool
    ) -> PriceEntry? {
        entries.min { lhs, rhs in
            let lhsPrice = comparablePrice(for: lhs, useNormalizedPricing: useNormalizedPricing)
            let rhsPrice = comparablePrice(for: rhs, useNormalizedPricing: useNormalizedPricing)

            if lhsPrice != rhsPrice {
                return lhsPrice < rhsPrice
            }

            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt > rhs.capturedAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func comparablePrice(
        for entry: PriceEntry,
        useNormalizedPricing: Bool
    ) -> Decimal {
        if useNormalizedPricing, let normalizedPrice = entry.normalizedUnitPriceValue {
            return normalizedPrice
        }
        return entry.priceValue
    }

    private static func comparableUnitType(
        for entry: PriceEntry,
        useNormalizedPricing: Bool
    ) -> UnitType {
        if useNormalizedPricing, let normalizedUnitType = entry.normalizedUnitType {
            return normalizedUnitType
        }
        return entry.unitType
    }
}
