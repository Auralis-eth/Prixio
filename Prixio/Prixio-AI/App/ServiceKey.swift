import Foundation

/// Type-safe service keys
struct ServiceKey: Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Predefined Service Keys
extension ServiceKey {
    // Deprecated: We rely on SwiftData's ModelContainer instead of a DatabaseManager service
    // static var database: ServiceKey { ServiceKey("DatabaseManager") }
    static var cloudSync: ServiceKey { ServiceKey("CloudKitSyncManager") }
    static var intelligence: ServiceKey { ServiceKey("AppleIntelligenceService") }
    static var mlModels: ServiceKey { ServiceKey("MLModelManager") }
    static var errorHandling: ServiceKey { ServiceKey("ErrorHandlingService") }
    static var performance: ServiceKey { ServiceKey("PerformanceMonitorService") }
    static var location: ServiceKey { ServiceKey("LocationService") }
}
