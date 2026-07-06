import Foundation

/// Infers how often the household actually buys each item from reviewed receipt
/// history, and predicts when it will next run out. Pure and deterministic, in the
/// `PriceInsightEngine` style: models in, value types out, `now` injected.
///
/// Consumption is evidenced by *receipts* (purchases), never by `PriceEntry` — a
/// shelf-price scan is an observation and says nothing about what the household
/// consumes. Only reviewed receipts and confident lines participate, so unconfirmed
/// OCR noise can't invent a habit. Grouping uses the exact `itemNameNormalized` key
/// (not `ItemKeyNormalizer.matches`): the rollup rule would merge "Almond Milk" and
/// "2% Milk", which run on independent clocks. See Docs/HouseholdAutopilotDesign.md.
enum ConsumptionCadenceEngine {

    // MARK: - Tuning

    /// Minimum distinct purchase events before any cadence is inferred. Below this
    /// the engine stays silent — a guess here reads as nagging, not competence.
    static let minPurchaseEvents = 3

    /// Events needed for `high` confidence (alongside the tighter spread gate).
    static let highConfidenceMinEvents = 5

    /// Regularity gates: interval spread (median absolute deviation) as a fraction
    /// of the median interval. Wider than this and the purchases aren't a habit.
    static let highConfidenceMaxSpreadRatio = 0.35
    static let mediumConfidenceMaxSpreadRatio = 0.6

    /// Days past the predicted run-out before "due soon" hardens into "probably out".
    static let overdueGraceDays = 2

    /// How close (in days) the predicted run-out must be to count as "due soon".
    static let dueSoonLeadDays = 3

    /// An item overdue by more than this many median intervals has probably been
    /// discontinued by the household (brand switch, season) — stop suggesting it.
    static let lapsedMissedIntervals = 3.0

    /// A stock-up (or smaller-than-usual buy) scales the predicted interval by
    /// last-quantity ÷ usual-quantity, clamped so one odd receipt can't push the
    /// prediction months out or down to zero.
    static let quantityScaleRange = 0.5...3.0

    // MARK: - Types

    enum CadenceConfidence: Int, Comparable, Sendable {
        case medium
        case high

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct ItemCadence: Equatable, Sendable {
        /// Exact normalized item key (`ReceiptLineItem.itemNameNormalized`).
        let itemKey: String
        /// Raw name from the most recent purchase, for display.
        let displayName: String
        /// Distinct purchase events (same key + same calendar day collapse to one).
        let purchaseEventCount: Int
        let medianIntervalDays: Double
        /// Median absolute deviation of the intervals — the regularity measure.
        let intervalSpreadDays: Double
        /// Start of the most recent purchase day.
        let lastPurchasedAt: Date
        let predictedRunOutDate: Date
        let confidence: CadenceConfidence
    }

    enum RestockUrgency: Equatable, Sendable {
        case probablyOut(daysOverdue: Int)
        case dueSoon(daysRemaining: Int)
        case stocked
    }

    struct RestockSuggestion: Equatable, Sendable {
        let cadence: ItemCadence
        let urgency: RestockUrgency
    }

    // MARK: - Cadence inference

    /// Infers a cadence for every item with enough regular purchase history.
    /// Items below the event minimum or above the spread gates yield nothing —
    /// silence, never a low-quality guess. Results are sorted by item key for
    /// stable output.
    static func computeCadences(
        receipts: [ReceiptCapture],
        now: Date = .now
    ) -> [ItemCadence] {
        let calendar = Calendar.current

        struct Event {
            let day: Date
            var quantity: Double
            var displayName: String
        }

        // itemKey → purchase day → collapsed event.
        var eventsByKey: [String: [Date: Event]] = [:]
        for receipt in receipts where receipt.reviewState == .reviewed {
            // The date the household actually bought, not the date it was scanned.
            let purchasedAt = receipt.purchaseDate ?? receipt.capturedAt
            let day = calendar.startOfDay(for: purchasedAt)
            for line in receipt.lineItems where !line.needsReview {
                guard let key = line.itemNameNormalized, !key.isEmpty else {
                    continue
                }
                let quantity = line.quantityValue.flatMap { value -> Double? in
                    let doubleValue = NSDecimalNumber(decimal: value).doubleValue
                    return doubleValue > 0 ? doubleValue : nil
                } ?? 1
                var event = eventsByKey[key]?[day]
                    ?? Event(day: day, quantity: 0, displayName: line.itemNameRaw ?? key)
                event.quantity += quantity
                if let rawName = line.itemNameRaw {
                    event.displayName = rawName
                }
                eventsByKey[key, default: [:]][day] = event
            }
        }

        var cadences: [ItemCadence] = []
        for (key, byDay) in eventsByKey {
            let events = byDay.values.sorted { $0.day < $1.day }
            guard events.count >= minPurchaseEvents else {
                continue
            }

            let intervals = zip(events.dropFirst(), events).map { later, earlier in
                Double(calendar.dateComponents([.day], from: earlier.day, to: later.day).day ?? 0)
            }
            guard let medianInterval = PriceInsightEngine.median(of: intervals.sorted()),
                  medianInterval > 0 else {
                continue
            }
            let spread = PriceInsightEngine.median(
                of: intervals.map { abs($0 - medianInterval) }.sorted()
            ) ?? 0
            let spreadRatio = spread / medianInterval

            let confidence: CadenceConfidence
            if events.count >= highConfidenceMinEvents, spreadRatio <= highConfidenceMaxSpreadRatio {
                confidence = .high
            } else if spreadRatio <= mediumConfidenceMaxSpreadRatio {
                confidence = .medium
            } else {
                continue
            }

            guard let lastEvent = events.last else {
                continue
            }
            let usualQuantity = PriceInsightEngine.median(of: events.map(\.quantity).sorted()) ?? 1
            let quantityScale: Double
            if usualQuantity > 0 {
                quantityScale = min(
                    max(lastEvent.quantity / usualQuantity, quantityScaleRange.lowerBound),
                    quantityScaleRange.upperBound
                )
            } else {
                quantityScale = 1
            }
            let predictedIntervalDays = medianInterval * quantityScale
            let runOutDate = calendar.date(
                byAdding: .day,
                value: Int(predictedIntervalDays.rounded()),
                to: lastEvent.day
            ) ?? lastEvent.day

            cadences.append(ItemCadence(
                itemKey: key,
                displayName: lastEvent.displayName,
                purchaseEventCount: events.count,
                medianIntervalDays: medianInterval,
                intervalSpreadDays: spread,
                lastPurchasedAt: lastEvent.day,
                predictedRunOutDate: runOutDate,
                confidence: confidence
            ))
        }
        return cadences.sorted {
            $0.itemKey.localizedCaseInsensitiveCompare($1.itemKey) == .orderedAscending
        }
    }

    // MARK: - Urgency

    /// Classifies how urgently an item needs restocking. Day math is calendar-day
    /// based so "due tomorrow" reads the same in the morning and at night.
    static func urgency(for cadence: ItemCadence, now: Date = .now) -> RestockUrgency {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let runOutDay = calendar.startOfDay(for: cadence.predictedRunOutDate)
        let daysUntil = calendar.dateComponents([.day], from: today, to: runOutDay).day ?? 0

        if daysUntil < -overdueGraceDays {
            return .probablyOut(daysOverdue: -daysUntil)
        }
        if daysUntil <= dueSoonLeadDays {
            return .dueSoon(daysRemaining: max(daysUntil, 0))
        }
        return .stocked
    }

    // MARK: - Suggestions

    /// The items worth suggesting for restock right now, most urgent first.
    ///
    /// Applies the user's `RestockRule` decisions: dismissed keys are suppressed
    /// entirely, and a confirmed rule's `overrideIntervalDays` replaces the inferred
    /// interval (a user-stated interval is durable truth, so the override also lifts
    /// confidence to `high`). Items overdue by more than `lapsedMissedIntervals`
    /// median intervals are treated as discontinued and suppressed.
    static func restockSuggestions(
        cadences: [ItemCadence],
        rules: [RestockRule],
        now: Date = .now
    ) -> [RestockSuggestion] {
        let calendar = Calendar.current
        let dismissedKeys = Set(rules.filter { $0.status == .dismissed }.map(\.itemKey))
        let overridesByKey: [String: Double] = rules.reduce(into: [:]) { result, rule in
            guard rule.status == .confirmed, let interval = rule.overrideIntervalDays else {
                return
            }
            result[rule.itemKey] = interval
        }

        var suggestions: [RestockSuggestion] = []
        for cadence in cadences {
            guard !dismissedKeys.contains(cadence.itemKey) else {
                continue
            }
            let effective = overridesByKey[cadence.itemKey].map {
                applying(overrideIntervalDays: $0, to: cadence, calendar: calendar)
            } ?? cadence

            let urgency = urgency(for: effective, now: now)
            switch urgency {
            case .stocked:
                continue
            case .probablyOut(let daysOverdue):
                guard Double(daysOverdue) <= lapsedMissedIntervals * effective.medianIntervalDays else {
                    continue
                }
            case .dueSoon:
                break
            }
            suggestions.append(RestockSuggestion(cadence: effective, urgency: urgency))
        }
        return suggestions.sorted { lhs, rhs in
            if lhs.cadence.predictedRunOutDate != rhs.cadence.predictedRunOutDate {
                return lhs.cadence.predictedRunOutDate < rhs.cadence.predictedRunOutDate
            }
            return lhs.cadence.itemKey.localizedCaseInsensitiveCompare(rhs.cadence.itemKey) == .orderedAscending
        }
    }

    // MARK: - Private helpers

    /// A copy of the cadence with the user's confirmed interval in place of the
    /// inferred one. The override is user-stated truth, so confidence becomes `high`.
    private static func applying(
        overrideIntervalDays: Double,
        to cadence: ItemCadence,
        calendar: Calendar
    ) -> ItemCadence {
        let runOutDate = calendar.date(
            byAdding: .day,
            value: Int(overrideIntervalDays.rounded()),
            to: cadence.lastPurchasedAt
        ) ?? cadence.lastPurchasedAt
        return ItemCadence(
            itemKey: cadence.itemKey,
            displayName: cadence.displayName,
            purchaseEventCount: cadence.purchaseEventCount,
            medianIntervalDays: overrideIntervalDays,
            intervalSpreadDays: cadence.intervalSpreadDays,
            lastPurchasedAt: cadence.lastPurchasedAt,
            predictedRunOutDate: runOutDate,
            confidence: .high
        )
    }
}
