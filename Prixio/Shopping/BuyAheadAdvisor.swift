import Foundation

/// A "buy early" nudge: the household will need this item soon (per its receipt
/// cadence), a saved flyer deal has it below the usual price, and the sale ends
/// *before* the predicted run-out — waiting for the natural shopping rhythm means
/// missing the price. Advisory only, like `FlyerDealAdvisory`: never changes basket
/// totals, never auto-adds to the list.
struct BuyAheadAdvisory: Equatable, Identifiable {
    let itemKey: String
    let displayName: String
    let bannerName: String
    let price: Decimal
    let saleEndDate: Date
    let predictedRunOutDate: Date
    /// How the deal price reads against the item's captured history
    /// (`.belowUsual` or `.likelySale` — anything weaker never becomes an advisory).
    let anomaly: PriceAnomaly

    var id: String { itemKey }

    var message: String {
        let priceText = CurrencyFormatter.shared.display(price)
        let endText = saleEndDate.formatted(date: .abbreviated, time: .omitted)
        let needText = predictedRunOutDate.formatted(date: .abbreviated, time: .omitted)
        return "\(displayName) is \(priceText) at \(bannerName) until \(endText) — you'll likely need more around \(needText)"
    }
}

/// Derives buy-ahead advisories by composing the receipt cadence
/// (`ConsumptionCadenceEngine`), saved flyer prices (`FlyerPriceRecord`), and
/// captured price history (`PriceInsightEngine`). Pure and deterministic.
enum BuyAheadAdvisor {
    /// How far ahead a predicted run-out is still worth planning for.
    static let lookaheadDays = 14
    /// Cap so the section stays a nudge, not a flyer browser.
    static let maxAdvisories = 2

    /// One advisory per item at most, soonest-ending sale first. Only surfaced when
    /// every leg of the claim is grounded:
    ///
    /// - The run-out lies *beyond* the due-soon window (nearer needs are the restock
    ///   section's job) but within `lookaheadDays`.
    /// - A current flyer record matches the item and its sale ends before the run-out.
    /// - Captured history has a usual band and classifies the deal price as
    ///   `.belowUsual` or `.likelySale` — no baseline, no claim.
    /// - A dismissed `RestockRule` suppresses the item here too.
    static func compute(
        cadences: [ConsumptionCadenceEngine.ItemCadence],
        records: [FlyerPriceRecord],
        entries: [PriceEntry],
        rules: [RestockRule] = [],
        now: Date = .now
    ) -> [BuyAheadAdvisory] {
        let calendar = Calendar.current
        let activeRecords = records.filter { !$0.isExpired(asOf: now) }
        guard !activeRecords.isEmpty, !cadences.isEmpty else { return [] }
        let dismissedKeys = Set(rules.filter { $0.status == .dismissed }.map(\.itemKey))

        var advisories: [BuyAheadAdvisory] = []
        for cadence in cadences where !dismissedKeys.contains(cadence.itemKey) {
            let today = calendar.startOfDay(for: now)
            let runOutDay = calendar.startOfDay(for: cadence.predictedRunOutDate)
            let daysUntilRunOut = calendar.dateComponents([.day], from: today, to: runOutDay).day ?? 0
            guard daysUntilRunOut > ConsumptionCadenceEngine.dueSoonLeadDays,
                  daysUntilRunOut <= lookaheadDays else {
                continue
            }

            // The deal must close before the household would naturally shop — that
            // closing window is the whole reason to buy early.
            let expiringDeals = activeRecords.filter { record in
                guard let saleEnd = record.saleEndDate,
                      saleEnd < cadence.predictedRunOutDate else {
                    return false
                }
                return ItemKeyNormalizer.matches(
                    queryKey: cadence.itemKey,
                    entryKey: record.normalizedItemKey,
                    entryHeadNoun: record.enrichedHeadNoun
                )
            }
            guard let bestDeal = expiringDeals.min(by: { $0.priceValue < $1.priceValue }),
                  let saleEnd = bestDeal.saleEndDate else {
                continue
            }

            guard let history = PriceInsightEngine.computeItemHistory(
                itemKey: cadence.itemKey,
                displayName: cadence.displayName,
                useNormalizedPricing: false,
                allEntries: entries,
                now: now
            ), history.hasUsualBand else {
                continue
            }
            let anomaly = PriceInsightEngine.classifyAnomaly(
                latest: bestDeal.priceValue,
                median: history.median
            )
            guard anomaly == .belowUsual || anomaly == .likelySale else {
                continue
            }

            advisories.append(BuyAheadAdvisory(
                itemKey: cadence.itemKey,
                displayName: cadence.displayName,
                bannerName: bestDeal.bannerName,
                price: bestDeal.priceValue,
                saleEndDate: saleEnd,
                predictedRunOutDate: cadence.predictedRunOutDate,
                anomaly: anomaly
            ))
        }

        return Array(
            advisories
                .sorted { lhs, rhs in
                    if lhs.saleEndDate != rhs.saleEndDate {
                        return lhs.saleEndDate < rhs.saleEndDate
                    }
                    return lhs.itemKey.localizedCaseInsensitiveCompare(rhs.itemKey) == .orderedAscending
                }
                .prefix(maxAdvisories)
        )
    }
}
