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
        let matchingEntries = allEntries.filter { $0.itemNameNormalized == normalizedKey }
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
            usedNormalizedPricing: useNormalizedPricing
        )
    }

    static func computeTripWinner(
        suggestions: [BestStoreSuggestion],
        totalItems: Int
    ) -> TripWinnerSummary? {
        guard !suggestions.isEmpty, totalItems > 0 else {
            return nil
        }

        let grouped = Dictionary(grouping: suggestions) { suggestion in
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
            staleCount: suggestions.filter(\.isStale).count,
            rankedCounts: rankedCounts
        )
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

    private static func comparableEntries(
        from entries: [PriceEntry],
        useNormalizedPricing: Bool
    ) -> [PriceEntry] {
        if useNormalizedPricing {
            return entries.filter { $0.normalizedUnitPriceValue != nil }
        }
        return entries
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
