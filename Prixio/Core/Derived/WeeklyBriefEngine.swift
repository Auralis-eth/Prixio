import Foundation

/// One week's household picture: receipt spend against the usual week, prices that
/// ran above their usual band, what's probably running low, and any buy-ahead
/// windows. Entirely deterministic — `facts` are UI-ready sentences the card and
/// the weekly notification render verbatim, and the only material an
/// `InsightExplainer` narration may draw on.
struct HouseholdBrief: Equatable, Sendable {
    enum SpendComparison: Equatable, Sendable {
        case nearUsual(usualWeekly: Decimal)
        case aboveUsual(usualWeekly: Decimal)
        case belowUsual(usualWeekly: Decimal)
        case insufficientData
    }

    /// A price captured this week that classified above the item's usual band.
    /// Phrased as a price observation, not a purchase — captures include shelf
    /// scans, which evidence a price, not a buy.
    struct UnusualPrice: Equatable, Sendable {
        let itemKey: String
        let displayName: String
        let capturedPrice: Decimal
        let usualLow: Decimal
        let usualHigh: Decimal
    }

    let weekStart: Date
    let receiptSpendThisWeek: Decimal
    let receiptCountThisWeek: Int
    let spendComparison: SpendComparison
    let unusualPrices: [UnusualPrice]
    let restockSuggestions: [ConsumptionCadenceEngine.RestockSuggestion]
    let buyAheadAdvisories: [BuyAheadAdvisory]

    /// UI-ready sentences, in display order. Every figure comes from the fields
    /// above, so downstream prose can be validated against them.
    let facts: [String]

    var isEmpty: Bool { facts.isEmpty }

    /// Identity for "did anything change" checks (mirrors `InsightEvidence`).
    var fingerprint: String { facts.joined(separator: "|") }
}

/// Composes the weekly brief from the existing engines. Pure and deterministic, in
/// the `PriceInsightEngine` style: models in, value type out, `now` injected.
enum WeeklyBriefEngine {
    /// How many prior weeks feed the "usual week" spend baseline.
    static let trailingWeeksWindow = 8
    /// Prior weeks with receipts needed before any spend comparison is claimed.
    static let minComparisonWeeks = 3
    /// Spend swings more than item prices week to week, so the "near usual" band is
    /// wider than the price band (±20% vs ±10%).
    static let spendBandTolerance = Decimal(string: "0.20")!
    static let maxUnusualPrices = 3
    static let maxRestockLines = 3

    static func compose(
        entries: [PriceEntry],
        receipts: [ReceiptCapture],
        flyerRecords: [FlyerPriceRecord],
        restockRules: [RestockRule],
        listItemKeys: [String],
        now: Date = .now
    ) -> HouseholdBrief {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)

        // MARK: Spend this week vs the usual week

        let reviewed = receipts.filter { $0.reviewState == .reviewed }
        func purchasedAt(_ receipt: ReceiptCapture) -> Date {
            receipt.purchaseDate ?? receipt.capturedAt
        }

        let thisWeek = reviewed.filter { purchasedAt($0) >= weekStart && purchasedAt($0) <= now }
        let spend = thisWeek.compactMap(\.total).reduce(Decimal(0), +)

        var priorWeekTotals: [Date: Decimal] = [:]
        for receipt in reviewed {
            let date = purchasedAt(receipt)
            guard date < weekStart,
                  let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
                  let weeksBack = calendar.dateComponents([.weekOfYear], from: start, to: weekStart).weekOfYear,
                  (1...trailingWeeksWindow).contains(weeksBack) else {
                continue
            }
            priorWeekTotals[start, default: 0] += receipt.total ?? 0
        }
        // Only weeks that actually have receipts vote — a week the user simply
        // didn't scan is missing data, not a $0 week.
        let priorWeeks = priorWeekTotals.values.filter { $0 > 0 }

        let comparison: HouseholdBrief.SpendComparison
        if priorWeeks.count >= minComparisonWeeks,
           let usual = PriceInsightEngine.median(of: priorWeeks.sorted()), usual > 0, spend > 0 {
            let low = usual * (Decimal(1) - spendBandTolerance)
            let high = usual * (Decimal(1) + spendBandTolerance)
            if spend > high {
                comparison = .aboveUsual(usualWeekly: usual)
            } else if spend < low {
                comparison = .belowUsual(usualWeekly: usual)
            } else {
                comparison = .nearUsual(usualWeekly: usual)
            }
        } else {
            comparison = .insufficientData
        }

        // MARK: Prices that ran above their usual band this week

        // Latest capture first, so the per-key pick below is the most recent
        // anomalous price regardless of input order — callers pass unsorted
        // fetch/@Query results, and the card and the notification must compose
        // the same brief from the same data.
        let thisWeekEntries = entries
            .filter { $0.capturedAt >= weekStart && $0.capturedAt <= now }
            .sorted { $0.capturedAt > $1.capturedAt }

        var unusual: [HouseholdBrief.UnusualPrice] = []
        var seenKeys = Set<String>()
        for entry in thisWeekEntries {
            let key = entry.itemNameNormalized
            guard !key.isEmpty, !seenKeys.contains(key) else {
                continue
            }
            guard let history = PriceInsightEngine.computeItemHistory(
                itemKey: key,
                displayName: entry.itemNameRaw,
                useNormalizedPricing: false,
                allEntries: entries,
                now: now
            ), history.hasUsualBand else {
                continue
            }
            let anomaly = PriceInsightEngine.classifyAnomaly(
                latest: entry.priceValue,
                median: history.median
            )
            guard anomaly == .aboveUsual || anomaly == .unusuallyHigh else {
                continue
            }
            seenKeys.insert(key)
            unusual.append(HouseholdBrief.UnusualPrice(
                itemKey: key,
                displayName: entry.itemNameRaw,
                capturedPrice: entry.priceValue,
                usualLow: history.usualLow,
                usualHigh: history.usualHigh
            ))
        }
        let worstFirst = unusual
            .sorted { ($0.capturedPrice - $0.usualHigh) > ($1.capturedPrice - $1.usualHigh) }
            .prefix(maxUnusualPrices)

        // MARK: Restock and buy-ahead (items already on the list are the list's job)

        func coveredByList(_ itemKey: String) -> Bool {
            listItemKeys.contains { ItemKeyNormalizer.matchesEitherDirection($0, itemKey) }
        }

        let cadences = ConsumptionCadenceEngine.computeCadences(receipts: receipts, now: now)
        let restock = Array(
            ConsumptionCadenceEngine.restockSuggestions(cadences: cadences, rules: restockRules, now: now)
                .filter { !coveredByList($0.cadence.itemKey) }
                .prefix(maxRestockLines)
        )
        let buyAhead = BuyAheadAdvisor.compute(
            cadences: cadences,
            records: flyerRecords,
            entries: entries,
            rules: restockRules,
            now: now
        )
        .filter { !coveredByList($0.itemKey) }

        // MARK: Facts

        let display = CurrencyFormatter.shared.display(_:)
        var facts: [String] = []
        if !thisWeek.isEmpty, spend > 0 {
            let receiptsText = "\(thisWeek.count) receipt\(thisWeek.count == 1 ? "" : "s")"
            facts.append("Receipt spending this week: \(display(spend)) across \(receiptsText).")
            switch comparison {
            case .nearUsual(let usual):
                facts.append("That's near your usual week of about \(display(usual)).")
            case .aboveUsual(let usual):
                facts.append("That's above your usual week of about \(display(usual)).")
            case .belowUsual(let usual):
                facts.append("That's below your usual week of about \(display(usual)).")
            case .insufficientData:
                break
            }
        }
        for price in worstFirst {
            facts.append("\(price.displayName) was \(display(price.capturedPrice)) this week, above its usual \(display(price.usualLow)) to \(display(price.usualHigh)).")
        }
        if !restock.isEmpty {
            let names = restock.map(\.cadence.displayName).formatted(.list(type: .and))
            facts.append("You're probably low on \(names).")
        }
        for advisory in buyAhead {
            facts.append(advisory.message + ".")
        }

        return HouseholdBrief(
            weekStart: weekStart,
            receiptSpendThisWeek: spend,
            receiptCountThisWeek: thisWeek.count,
            spendComparison: comparison,
            unusualPrices: Array(worstFirst),
            restockSuggestions: restock,
            buyAheadAdvisories: buyAhead,
            facts: facts
        )
    }
}
