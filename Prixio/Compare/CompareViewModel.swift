import Combine
import CoreLocation
import Foundation

@MainActor
final class CompareViewModel: ObservableObject {
    struct SuggestedComparisonCard: Identifiable, Equatable {
        let itemKey: String
        let displayName: String
        let storeCount: Int
        let latestCapturedAt: Date

        var id: String {
            itemKey
        }
    }

    struct RecentCaptureRow: Identifiable, Equatable {
        let entryID: UUID
        let itemKey: String
        let displayName: String
        let storeName: String
        let capturedAt: Date
        let price: Decimal
        let unitLabel: String

        var id: UUID {
            entryID
        }
    }

    struct BrowseItemRow: Identifiable, Equatable {
        let itemKey: String
        let displayName: String
        let bestPrice: Decimal?
        let bestPriceUnitLabel: String?
        let storeCount: Int

        var id: String {
            itemKey
        }
    }

    struct ItemComparisonState: Equatable {
        let rows: [StoreComparisonRow]
        let showsMixedUnitFamilyNote: Bool
    }

    /// A saved flyer price promoted into the comparison surface. Kept distinct from
    /// `StoreComparisonRow` (in-person captures) so it can be labeled "Flyer price"
    /// and never presented as an equal-confidence scanned price.
    struct FlyerComparisonRow: Identifiable, Equatable {
        let recordID: UUID
        let bannerName: String
        let productName: String
        let price: Decimal
        let regularPrice: Decimal?
        let saleEndDate: Date?
        let memberOnly: Bool
        let confidence: Float
        let storeContext: String?

        var id: UUID { recordID }
    }

    @Published private(set) var suggestedCards: [SuggestedComparisonCard] = []
    @Published private(set) var recentCaptures: [RecentCaptureRow] = []
    @Published private(set) var browseItems: [BrowseItemRow] = []
    @Published private(set) var searchResults: [BrowseItemRow] = []

    func recompute(
        entries: [PriceEntry],
        query: String,
        now: Date = .now
    ) {
        let groupedEntries = Dictionary(grouping: entries, by: \.itemNameNormalized)

        suggestedCards = groupedEntries.values
            .compactMap(makeSuggestedCard(for:))
            .sorted { lhs, rhs in
                if lhs.storeCount != rhs.storeCount {
                    return lhs.storeCount > rhs.storeCount
                }
                if lhs.latestCapturedAt != rhs.latestCapturedAt {
                    return lhs.latestCapturedAt > rhs.latestCapturedAt
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        recentCaptures = entries
            .sorted { $0.capturedAt > $1.capturedAt }
            .map(makeRecentCaptureRow(from:))

        browseItems = groupedEntries.values
            .map { makeBrowseRow(for: $0, now: now) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

        let normalizedQuery = ItemKeyNormalizer.normalize(query)
        if normalizedQuery.isEmpty {
            searchResults = []
        } else {
            searchResults = browseItems.filter { row in
                row.itemKey.contains(normalizedQuery) ||
                row.displayName.lowercased().contains(normalizedQuery)
            }
        }
    }

    func buildItemComparisonState(
        itemKey: String,
        entries: [PriceEntry],
        mode: CompareDisplayMode,
        userLocation: CLLocation?,
        now: Date = .now
    ) -> ItemComparisonState {
        let normalizedKey = ItemKeyNormalizer.normalize(itemKey)
        let matchingEntries = entries.filter {
            ItemKeyNormalizer.matches(queryKey: normalizedKey, entryKey: $0.itemNameNormalized)
        }
        let candidateEntries = comparableEntries(from: matchingEntries, mode: mode)

        guard !candidateEntries.isEmpty else {
            return ItemComparisonState(rows: [], showsMixedUnitFamilyNote: false)
        }

        let dominantFamily = dominantUnitFamily(for: candidateEntries, mode: mode)
        let filteredEntries = dominantFamily.map { family in
            candidateEntries.filter { unitFamily(for: $0, mode: mode) == family }
        } ?? candidateEntries

        let groupedByStore = Dictionary(grouping: filteredEntries, by: storeKey(for:))

        let rows = groupedByStore.values
            .compactMap { latestComparableEntry in
                guard let latestEntry = latestComparableEntry.max(by: { $0.capturedAt < $1.capturedAt }) else {
                    return nil
                }

                return StoreComparisonRow(
                    storeChainID: latestEntry.storeChainId,
                    storeLocationID: latestEntry.storeLocationId,
                    displayStoreName: latestEntry.storeChainNameSnapshot ?? latestEntry.storeLocationNameSnapshot ?? "Unknown",
                    storeLocationName: latestEntry.storeLocationNameSnapshot,
                    bestEntryID: latestEntry.id,
                    displayPrice: displayPrice(for: latestEntry, mode: mode),
                    displayUnit: displayUnit(for: latestEntry, mode: mode),
                    capturedAt: latestEntry.capturedAt,
                    distanceMeters: distanceMeters(from: userLocation, to: latestEntry),
                    trendDirection: trendDirection(for: latestComparableEntry, mode: mode),
                    stalenessBucket: PriceInsightEngine.stalenessBucket(for: latestEntry.capturedAt, now: now)
                )
            }
            .sorted(by: compareRows)

        let showsMixedUnitFamilyNote: Bool
        if let dominantFamily {
            showsMixedUnitFamilyNote = Set(candidateEntries.compactMap {
                unitFamily(for: $0, mode: mode)
            }).count > 1 && candidateEntries.contains {
                unitFamily(for: $0, mode: mode) != dominantFamily
            }
        } else {
            showsMixedUnitFamilyNote = false
        }

        return ItemComparisonState(rows: rows, showsMixedUnitFamilyNote: showsMixedUnitFamilyNote)
    }

    /// Item-level price history (latest/lowest/highest/usual band + anomaly + timeline) for the
    /// detail surface, tracking the current per-unit/per-package display mode.
    func buildItemHistory(
        itemKey: String,
        displayName: String,
        entries: [PriceEntry],
        mode: CompareDisplayMode,
        scope: PriceHistoryScope = .allStores,
        now: Date = .now
    ) -> ItemPriceHistory? {
        PriceInsightEngine.computeItemHistory(
            itemKey: itemKey,
            displayName: displayName,
            useNormalizedPricing: mode == .perUnit,
            allEntries: entries,
            scope: scope,
            now: now
        )
    }

    /// Saved flyer prices that match this item, promoted into the comparison surface
    /// as clearly-labeled "Flyer price" rows (best price first). Uses the same
    /// generic-query→specific-product rule as captured comparisons, so "cheese" rolls
    /// up "Marble Cheddar". Kept separate from `StoreComparisonRow` so scraped flyer
    /// data is never shown as an equal-confidence in-person scan.
    func flyerComparisonRows(
        itemKey: String,
        records: [FlyerPriceRecord]
    ) -> [FlyerComparisonRow] {
        let normalizedKey = ItemKeyNormalizer.normalize(itemKey)
        return records
            .filter { ItemKeyNormalizer.matches(queryKey: normalizedKey, entryKey: $0.normalizedItemKey) }
            .map { record in
                FlyerComparisonRow(
                    recordID: record.id,
                    bannerName: record.bannerName,
                    productName: record.productName,
                    price: record.priceValue,
                    regularPrice: record.regularPriceValue,
                    saleEndDate: record.saleEndDate,
                    memberOnly: record.memberOnly,
                    confidence: record.confidence,
                    storeContext: record.storeContext
                )
            }
            .sorted { lhs, rhs in
                if lhs.price != rhs.price {
                    return lhs.price < rhs.price
                }
                return lhs.bannerName.localizedCaseInsensitiveCompare(rhs.bannerName) == .orderedAscending
            }
    }

    /// Store scopes (all-stores plus per-chain/-location) that have history for this item, used to
    /// offer a chain-vs-location breakdown in the detail surface.
    func availableHistoryScopes(itemKey: String, entries: [PriceEntry]) -> [PriceHistoryScope] {
        PriceInsightEngine.availableStoreScopes(itemKey: itemKey, allEntries: entries)
    }

    private func makeSuggestedCard(for entries: [PriceEntry]) -> SuggestedComparisonCard? {
        let storeCount = distinctStoreCount(for: entries)
        guard storeCount >= 2, let latestEntry = entries.max(by: { $0.capturedAt < $1.capturedAt }) else {
            return nil
        }

        return SuggestedComparisonCard(
            itemKey: latestEntry.itemNameNormalized,
            displayName: latestEntry.itemNameRaw,
            storeCount: storeCount,
            latestCapturedAt: latestEntry.capturedAt
        )
    }

    private func makeRecentCaptureRow(from entry: PriceEntry) -> RecentCaptureRow {
        RecentCaptureRow(
            entryID: entry.id,
            itemKey: entry.itemNameNormalized,
            displayName: entry.itemNameRaw,
            storeName: entry.storeChainNameSnapshot ?? entry.storeLocationNameSnapshot ?? "Unknown",
            capturedAt: entry.capturedAt,
            price: entry.priceValue,
            unitLabel: entry.unitType.displayName
        )
    }

    private func makeBrowseRow(for entries: [PriceEntry], now: Date) -> BrowseItemRow {
        let representativeEntry = entries.max(by: { $0.capturedAt < $1.capturedAt })
        let bestSuggestion = representativeEntry.map {
            PriceInsightEngine.computeBestStoreForItem(
                itemKey: $0.itemNameNormalized,
                allEntries: entries,
                now: now
            )
        } ?? nil

        return BrowseItemRow(
            itemKey: representativeEntry?.itemNameNormalized ?? "",
            displayName: representativeEntry?.itemNameRaw ?? "",
            bestPrice: bestSuggestion?.comparablePrice,
            bestPriceUnitLabel: bestSuggestion.map { unitLabel(for: $0.comparableUnitType) },
            storeCount: distinctStoreCount(for: entries)
        )
    }

    private func distinctStoreCount(for entries: [PriceEntry]) -> Int {
        Set(entries.map(storeKey(for:))).count
    }

    private func comparableEntries(from entries: [PriceEntry], mode: CompareDisplayMode) -> [PriceEntry] {
        switch mode {
        case .perUnit:
            return entries.filter { $0.normalizedUnitPriceValue != nil }
        case .perPackage:
            return entries
        }
    }

    private func dominantUnitFamily(for entries: [PriceEntry], mode: CompareDisplayMode) -> ComparisonUnitFamily? {
        let grouped = Dictionary(grouping: entries.compactMap { entry in
            unitFamily(for: entry, mode: mode).map { ($0, entry.capturedAt) }
        }, by: \.0)

        return grouped.max { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count < rhs.value.count
            }

            let lhsLatest = lhs.value.map(\.1).max() ?? .distantPast
            let rhsLatest = rhs.value.map(\.1).max() ?? .distantPast
            return lhsLatest < rhsLatest
        }?.key
    }

    private func unitFamily(for entry: PriceEntry, mode: CompareDisplayMode) -> ComparisonUnitFamily? {
        switch mode {
        case .perUnit:
            guard let normalizedUnitType = entry.normalizedUnitType else {
                return nil
            }
            return unitFamily(for: normalizedUnitType)
        case .perPackage:
            return .package
        }
    }

    private func unitFamily(for unitType: UnitType) -> ComparisonUnitFamily {
        switch unitType {
        case .each:
            return .each
        case .lb, .kg, .hundredGrams:
            return .weight
        case .liter:
            return .volume
        }
    }

    private func displayPrice(for entry: PriceEntry, mode: CompareDisplayMode) -> Decimal {
        switch mode {
        case .perUnit:
            return entry.normalizedUnitPriceValue ?? entry.priceValue
        case .perPackage:
            return entry.priceValue
        }
    }

    private func displayUnit(for entry: PriceEntry, mode: CompareDisplayMode) -> String {
        switch mode {
        case .perUnit:
            return unitLabel(for: entry.normalizedUnitType ?? entry.unitType)
        case .perPackage:
            return unitLabel(for: entry.unitType)
        }
    }

    private func unitLabel(for unitType: UnitType) -> String {
        unitType.displayName
    }

    private func storeKey(for entry: PriceEntry) -> String {
        if let storeLocationId = entry.storeLocationId {
            return "location-\(storeLocationId.uuidString)"
        }
        if let storeChainId = entry.storeChainId {
            return "chain-\(storeChainId.uuidString)"
        }
        return "snapshot-\(entry.storeChainNameSnapshot ?? entry.storeLocationNameSnapshot ?? "unknown")"
    }

    private func distanceMeters(from userLocation: CLLocation?, to entry: PriceEntry) -> CLLocationDistance? {
        guard
            let userLocation,
            let latitude = entry.storeCoordinateLat,
            let longitude = entry.storeCoordinateLon
        else {
            return nil
        }

        return userLocation.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    private func trendDirection(for entries: [PriceEntry], mode: CompareDisplayMode) -> TrendDirection {
        let sortedEntries = entries.sorted { $0.capturedAt > $1.capturedAt }
        guard sortedEntries.count >= 2 else {
            return .unavailable
        }

        let latest = sortedEntries[0]
        let previous = sortedEntries[1]
        let latestPrice = displayPrice(for: latest, mode: mode)
        let previousPrice = displayPrice(for: previous, mode: mode)

        guard previousPrice != 0 else {
            return .unavailable
        }

        let deltaRatio = (latestPrice - previousPrice) / previousPrice
        let deltaPercent = NSDecimalNumber(decimal: deltaRatio).doubleValue

        if abs(deltaPercent) <= 0.02 {
            return .flat
        }

        let wholePercent = Int((abs(deltaPercent) * 100).rounded())
        if deltaPercent > 0 {
            return .up(wholePercent)
        }
        return .down(wholePercent)
    }

    private func compareRows(lhs: StoreComparisonRow, rhs: StoreComparisonRow) -> Bool {
        let lhsRank = stalenessRank(lhs.stalenessBucket)
        let rhsRank = stalenessRank(rhs.stalenessBucket)

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.displayPrice != rhs.displayPrice {
            return lhs.displayPrice < rhs.displayPrice
        }
        if lhs.capturedAt != rhs.capturedAt {
            return lhs.capturedAt > rhs.capturedAt
        }
        return lhs.displayStoreName.localizedCaseInsensitiveCompare(rhs.displayStoreName) == .orderedAscending
    }

    private func stalenessRank(_ bucket: StalenessBucket) -> Int {
        switch bucket {
        case .fresh:
            return 0
        case .aging:
            return 1
        case .stale:
            return 2
        case .veryStale:
            return 3
        }
    }
}
