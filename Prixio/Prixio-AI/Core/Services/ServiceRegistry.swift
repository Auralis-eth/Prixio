import Foundation

/// Thread-safe service registry with dependency management
class ServiceRegistry {

    // MARK: - Properties

    private var services: [String: any AppService] = [:]
    private var serviceStates: [String: ServiceState] = [:]
    private var initializationOrder: [String] = []

    // MARK: - Service Registration

    /// Register a service with type-safe key
    func registerService(_ service: AppService, for key: ServiceKey) {
        services[key.rawValue] = service
        serviceStates[key.rawValue] = service.state

        Logging.shared.info("Registered service: \(key.rawValue)")
    }

    /// Get service by type-safe key
    func getService(for key: ServiceKey) -> AppService? {
        services[key.rawValue]
    }

    /// Require service (throws if not found)
    func requireService(for key: ServiceKey) throws -> AppService {
        guard let service = services[key.rawValue] else {
            throw PrixioError.dependencyResolutionFailed(key.rawValue)
        }
        return service
    }

    // MARK: - Service Lifecycle Management

    /// Initialize all services in dependency order
    func initializeAllServices() throws {
        Logging.shared.info("Starting service initialization")

        // Calculate initialization order based on dependencies
        initializationOrder = calculateInitializationOrder()

        // Initialize services in order
        for serviceKey in initializationOrder {
            guard let service = services[serviceKey] else { continue }

            try service.initialize()
            serviceStates[serviceKey] = service.state
        }

        Logging.shared.info("All services initialized successfully")
    }

    /// Shutdown all services in reverse order
    func shutdownAllServices() {
        Logging.shared.info("Starting service shutdown")

        // Shutdown in reverse order
        for serviceKey in initializationOrder.reversed() {
            guard let service = services[serviceKey] else { continue }

            do {
                try service.shutdown()
                serviceStates[serviceKey] = service.state
            } catch {
                Logging.shared.error("Failed to shutdown service: \(serviceKey)", error: error)
            }
        }

        Logging.shared.info("All services shutdown")
    }

    /// Perform health check on all services
    func performHealthCheck() -> [String: Bool] {
        var results: [String: Bool] = [:]

        for (key, service) in services {
            results[key] = service.healthCheck()
            serviceStates[key] = service.state
        }

        return results
    }

    /// Get current state of all services
    func getAllServiceStates() -> [String: ServiceState] {
        // Refresh states from services
        for (key, service) in services {
            serviceStates[key] = service.state
        }

        return serviceStates
    }

    // MARK: - Private Methods

    private func calculateInitializationOrder() -> [String] {
        var order: [String] = []
        var visited: Set<String> = []
        var visiting: Set<String> = []

        func visit(_ serviceKey: String) throws {
            if visiting.contains(serviceKey) {
                Logging.shared.error("Circular dependency detected for service: \(serviceKey)")
                throw PrixioError.dependencyResolutionFailed("Circular dependency: \(serviceKey)")
            }

            if visited.contains(serviceKey) {
                return
            }

            visiting.insert(serviceKey)

            // Visit dependencies first
            if let service = services[serviceKey] {
                for dependency in service.dependencies {
                    if services[dependency] != nil {
                        try visit(dependency)
                    } else {
                        Logging.shared.warning("Dependency not found: \(dependency) for service: \(serviceKey)")
                    }
                }
            }

            visiting.remove(serviceKey)
            visited.insert(serviceKey)
            order.append(serviceKey)
        }

        // Visit all services
        for serviceKey in services.keys {
            if !visited.contains(serviceKey) {
                do {
                    try visit(serviceKey)
                } catch {
                    // Continue with other services if there's a circular dependency
                    Logging.shared.error("Error calculating order for \(serviceKey)", error: error)
                }
            }
        }

        return order
    }
}
