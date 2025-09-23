import Foundation

/// Base service implementation
class BaseService: AppService {

    let identifier: String
    private(set) var state: ServiceState = .notInitialized

    /// Override in subclasses to specify dependencies
    var dependencies: [String] { [] }

    init(identifier: String) {
        self.identifier = identifier
    }

    func initialize() throws {
        guard state == .notInitialized else {
            Logging.shared.warning("Service \(identifier) already initialized")
            return
        }

        state = .initializing

        do {
            Logging.shared.info("Initializing service: \(identifier)")
            try performInitialization()
            state = .ready
            Logging.shared.info("Service \(identifier) initialized successfully")
        } catch {
            state = .error(error.localizedDescription)
            Logging.shared.error("Service \(identifier) initialization failed", error: error)
            throw error
        }
    }

    func shutdown() throws {
        guard state.isReady else { return }

        Logging.shared.info("Shutting down service: \(identifier)")

        do {
            try performShutdown()
            state = .shutdown
            Logging.shared.info("Service \(identifier) shutdown successfully")
        } catch {
            state = .error(error.localizedDescription)
            Logging.shared.error("Service \(identifier) shutdown failed", error: error)
            throw error
        }
    }

    func healthCheck() -> Bool {
        performHealthCheck()
    }

    // MARK: - Override Points

    /// Override in subclasses to implement initialization logic
    func performInitialization() throws {
        // Default implementation does nothing
    }

    /// Override in subclasses to implement shutdown logic
    func performShutdown() throws {
        // Default implementation does nothing
    }

    /// Override in subclasses to implement health check logic
    func performHealthCheck() -> Bool {
        state.isReady
    }
}
