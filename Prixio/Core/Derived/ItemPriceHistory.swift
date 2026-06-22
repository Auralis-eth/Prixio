import Foundation

/// A single observed price for an item, used both for summary stats and for charting the price
/// timeline. Price/unit reflect whichever comparison mode produced it (per-unit or per-package).
struct PricePoint: Equatable, Sendable {
    let entryID: UUID
    let date: Date
    let price: Decimal
    let unitType: UnitType
    let storeName: String?
    let usedNormalizedPricing: Bool
}

/// A history-relative read on the most recent price for an item. Thresholds mirror
/// `PriceMemoryInsight` so the labels stay consistent with the scan-review flow.
enum PriceAnomaly: Equatable, Sendable {
    /// Not enough history to make any claim.
    case insufficientData
    /// Latest price is well below usual (≥ 2× the tolerance band) — a strong deal.
    case likelySale
    /// Latest price is below usual but not dramatically so.
    case belowUsual
    /// Latest price is within the usual band.
    case nearUsual
    /// Latest price is above usual but not dramatically so.
    case aboveUsual
    /// Latest price is well above usual (≥ 2× the tolerance band) — a possible outlier or error.
    case unusuallyHigh

    var displayLabel: String {
        switch self {
        case .insufficientData:
            return "Not enough history"
        case .likelySale:
            return "Likely sale"
        case .belowUsual:
            return "Below usual"
        case .nearUsual:
            return "Near usual"
        case .aboveUsual:
            return "Above usual"
        case .unusuallyHigh:
            return "Unusually high"
        }
    }

    var systemImage: String {
        switch self {
        case .insufficientData:
            return "questionmark.circle"
        case .likelySale:
            return "tag.fill"
        case .belowUsual:
            return "arrow.down.circle"
        case .nearUsual:
            return "equal.circle"
        case .aboveUsual:
            return "arrow.up.circle"
        case .unusuallyHigh:
            return "exclamationmark.triangle.fill"
        }
    }

    /// Whether this anomaly is worth calling out prominently (a real deal or a real outlier).
    var isNoteworthy: Bool {
        switch self {
        case .likelySale, .unusuallyHigh:
            return true
        case .insufficientData, .belowUsual, .nearUsual, .aboveUsual:
            return false
        }
    }
}

/// Which stores an item-history summary is scoped to. `allStores` pools every observation;
/// `chain`/`location` narrow it so the user can see "is this price normal *at this chain*?"
/// separately from the blended all-stores picture.
enum PriceHistoryScope: Equatable, Hashable, Sendable, Identifiable {
    case allStores
    case chain(name: String)
    case location(name: String)

    var id: String {
        switch self {
        case .allStores:
            return "all"
        case .chain(let name):
            return "chain:\(name.lowercased())"
        case .location(let name):
            return "location:\(name.lowercased())"
        }
    }

    var displayName: String {
        switch self {
        case .allStores:
            return "All stores"
        case .chain(let name), .location(let name):
            return name
        }
    }
}

/// Full item-level price history summary: where today's price sits relative to the user's own
/// past prices, plus a chronological timeline for charting.
struct ItemPriceHistory: Equatable, Sendable {
    let itemKey: String
    let displayName: String
    /// The store scope this summary was computed for.
    let scope: PriceHistoryScope
    let observationCount: Int
    let latest: PricePoint
    let lowest: PricePoint
    let highest: PricePoint
    let median: Decimal
    let usualLow: Decimal
    let usualHigh: Decimal
    /// `false` when there are fewer than `PriceInsightEngine.priceMemoryMinObservations` entries,
    /// in which case the usual band collapses to the median and should not be drawn.
    let hasUsualBand: Bool
    /// Freshness of the most recent observation.
    let freshness: StalenessBucket
    let anomaly: PriceAnomaly
    /// Observations sorted oldest-first.
    let timeline: [PricePoint]
}
