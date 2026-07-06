import Foundation

/// A "you usually buy this" suggestion for the shopping list: an item the user has
/// captured prices for on a regular rhythm that is now due again and isn't on the
/// list. Surfaced for user confirm/dismiss — never added automatically.
struct ListAdditionSuggestion: Equatable, Sendable, Identifiable {
    let itemKey: String
    let displayName: String
    /// Distinct purchase days backing the rhythm claim.
    let purchaseCount: Int
    /// Typical days between purchases (median of the day gaps).
    let medianIntervalDays: Int
    let daysSinceLastPurchase: Int

    var id: String { itemKey }
}

/// Derives conservative list-addition suggestions from saved `PriceEntry` history
/// (the AgenticArchitecture `proposeListAdditions` tool). Pure and deterministic:
/// a capture rhythm is only claimed from several distinct purchase days at a
/// plausible cadence, and an item already on the list — matched through the same
/// `ItemKeyNormalizer` rollup the rest of the app uses — is never suggested.
enum ListAdditionSuggestionEngine {
    /// Distinct purchase days required before any rhythm claim.
    static let minPurchaseDays = 3
    /// Cadence bounds: faster looks like a data artifact (several scans of one
    /// shop), slower is too irregular to call "usually".
    static let minMedianIntervalDays = 3
    static let maxMedianIntervalDays = 90
    /// Cap so the section stays a nudge, not a second list.
    static let maxSuggestions = 3

    static func proposeAdditions(
        listItemKeys: [String],
        allEntries: [PriceEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ListAdditionSuggestion] {
        let today = calendar.startOfDay(for: now)
        var ranked: [(suggestion: ListAdditionSuggestion, overdueRatio: Double)] = []

        for (key, group) in Dictionary(grouping: allEntries, by: \.itemNameNormalized) where !key.isEmpty {
            // Several captures in one shop are one purchase: count distinct days.
            let purchaseDays = Set(group.map { calendar.startOfDay(for: $0.capturedAt) }).sorted()
            guard purchaseDays.count >= minPurchaseDays, let lastDay = purchaseDays.last else {
                continue
            }

            let gaps = zip(purchaseDays.dropFirst(), purchaseDays).compactMap {
                calendar.dateComponents([.day], from: $1, to: $0).day
            }
            guard let median = medianDays(of: gaps),
                  (minMedianIntervalDays...maxMedianIntervalDays).contains(median) else {
                continue
            }

            let sinceLast = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            // Only due items are suggested — nagging about something bought
            // yesterday would erode trust in the section.
            guard sinceLast >= median else { continue }

            // Skip anything already on the list, in either rollup direction: a list
            // "milk" covers a history "Almond Milk", and a list "Daisy Sour Cream"
            // is covered by a history "sour cream".
            let onList = listItemKeys.contains { listKey in
                ItemKeyNormalizer.matches(queryKey: listKey, entryKey: key)
                    || ItemKeyNormalizer.matches(queryKey: key, entryKey: listKey)
            }
            guard !onList else { continue }

            let displayName = group.max(by: { $0.capturedAt < $1.capturedAt })?.itemNameRaw ?? key
            ranked.append((
                ListAdditionSuggestion(
                    itemKey: key,
                    displayName: displayName,
                    purchaseCount: purchaseDays.count,
                    medianIntervalDays: median,
                    daysSinceLastPurchase: sinceLast
                ),
                Double(sinceLast) / Double(median)
            ))
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.overdueRatio != rhs.overdueRatio {
                    return lhs.overdueRatio > rhs.overdueRatio
                }
                return lhs.suggestion.itemKey < rhs.suggestion.itemKey
            }
            .prefix(maxSuggestions)
            .map(\.suggestion)
    }

    /// Median of day gaps; even counts round the middle pair's mean down, keeping
    /// the "due" threshold conservative.
    private static func medianDays(of gaps: [Int]) -> Int? {
        guard !gaps.isEmpty else { return nil }
        let sorted = gaps.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
