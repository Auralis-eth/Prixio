import Foundation

/// Service state enumeration
enum ServiceState: Sendable, Equatable {
    case notInitialized
    case initializing
    case ready
    case error(String)
    case shutdown

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var hasError: Bool {
        if case .error = self { return true }
        return false
    }
}
