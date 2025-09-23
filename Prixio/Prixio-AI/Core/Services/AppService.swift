import Foundation

/// Base protocol for all application services
protocol AppService {

    /// Unique service identifier
    var identifier: String { get }

    /// Service dependencies (identifiers of services this service depends on)
    var dependencies: [String] { get }

    /// Current service state
    var state: ServiceState { get }

    /// Initialize the service
    func initialize() throws

    /// Shutdown the service gracefully
    func shutdown() throws

    /// Perform health check
    func healthCheck() -> Bool
}
