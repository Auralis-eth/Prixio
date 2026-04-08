import CoreLocation
import Foundation

enum CompareDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case perUnit
    case perPackage

    var id: String { rawValue }
}

enum ComparisonUnitFamily: String, Hashable, Sendable {
    case each
    case weight
    case volume
    case package
}

enum TrendDirection: Equatable, Sendable {
    case up(Int)
    case down(Int)
    case flat
    case unavailable
}

struct StoreComparisonRow: Identifiable, Equatable, Sendable {
    let storeChainID: UUID?
    let storeLocationID: UUID?
    let displayStoreName: String
    let storeLocationName: String?
    let bestEntryID: UUID
    let displayPrice: Decimal
    let displayUnit: String
    let capturedAt: Date
    let distanceMeters: CLLocationDistance?
    let trendDirection: TrendDirection
    let stalenessBucket: StalenessBucket

    var id: UUID {
        bestEntryID
    }
}
