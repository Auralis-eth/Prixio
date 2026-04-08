import Foundation

enum StalenessBucket: String, Codable, CaseIterable, Sendable {
    case fresh
    case aging
    case stale
    case veryStale

    var isStale: Bool {
        switch self {
        case .fresh, .aging:
            return false
        case .stale, .veryStale:
            return true
        }
    }
}
