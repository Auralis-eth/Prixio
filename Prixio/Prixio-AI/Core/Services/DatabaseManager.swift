import Foundation
import SwiftData
import OSLog

/// Deprecated: DatabaseManager is not used in the Core MVP.
/// We rely on SwiftData's ModelContainer configured in `PrixioApp` and inject `modelContext` into views.
/// Keep this file around temporarily to avoid breaking references during transition; no registration occurs.

@available(*, deprecated, message: "Use SwiftData ModelContainer and ModelContext directly; DatabaseManager is not part of the MVP.")
/// Thread-safe database manager using SwiftData
final class DatabaseManager: BaseService {

    private let signposter = OSSignposter(subsystem: "com.prixio.app", category: "database")
    private let logger = Logger(subsystem: "com.prixio.app", category: "database")

//    private var modelContainer: ModelContainer?

    override var dependencies: [String] { [] }

    override init(identifier: String = "DatabaseManager") {
        super.init(identifier: identifier)
    }

    override func performInitialization() throws {
        let interval = signposter.beginInterval("SwiftData Init")
        defer { signposter.endInterval("SwiftData Init", interval) }

        Logging.shared.info("DatabaseManager deprecated; no-op initialization")
        logger.log("DatabaseManager is deprecated; use ModelContainer in PrixioApp")
    }

    override func performShutdown() throws {
        let interval = signposter.beginInterval("SwiftData Shutdown")
        defer { signposter.endInterval("SwiftData Shutdown", interval) }

        Logging.shared.info("DatabaseManager deprecated; no-op shutdown")
    }

    override func performHealthCheck() -> Bool {
        signposter.emitEvent("SwiftData HealthCheck (Deprecated DatabaseManager)")
        return true
    }
}

