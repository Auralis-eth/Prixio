import Foundation
import SwiftUI
import Combine
import OSLog

/// Main app coordinator managing services and app state
final class AppCoordinator: ObservableObject {

    private let signposter = OSSignposter(subsystem: "com.prixio.app", category: "app")
    private let logger = Logger(subsystem: "com.prixio.app", category: "app")

    // MARK: - Properties

    @Published private(set) var appState: AppState = .initializing
    private let serviceRegistry = ServiceRegistry()

    // MARK: - Initialization

    init() {
        setupServices()
    }

    // MARK: - App Lifecycle

    func initializeApp() {
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval("App Init", id: signpostID)
        defer { signposter.endInterval("App Init", intervalState) }

        appState = .initializing

        do {
            // Initialize all services
            try serviceRegistry.initializeAllServices()

            // Verify all services are healthy
            let healthResults = serviceRegistry.performHealthCheck()
            let allHealthy = healthResults.values.allSatisfy { $0 }

            if allHealthy {
                appState = .ready
                Logging.shared.info("App initialization completed successfully")
            } else {
                let failedServices = healthResults.filter { !$0.value }.keys.joined(separator: ", ")
                appState = .failed(PrixioError.serviceInitializationFailed("Health check failed", underlying: nil))
                Logging.shared.error("App initialization failed - unhealthy services: \(failedServices)")
            }

        } catch {
            appState = .failed(error)
            Logging.shared.error("App initialization failed", error: error)
        }
    }

    func shutdownApp() {
        Logging.shared.info("Shutting down app")
        serviceRegistry.shutdownAllServices()
        appState = .terminated
    }

    // MARK: - Service Access

    func getService(for key: ServiceKey) -> AppService? {
        serviceRegistry.getService(for: key)
    }

    func requireService(for key: ServiceKey) throws -> AppService {
        try serviceRegistry.requireService(for: key)
    }

    func registerService(_ service: AppService, for key: ServiceKey) {
        serviceRegistry.registerService(service, for: key)
    }

    // MARK: - Lifecycle Events

    func appDidEnterBackground() {
        Logging.shared.info("App entered background")
        // Handle background transition
    }

    func appWillEnterForeground() {
        Logging.shared.info("App will enter foreground")
        // Handle foreground transition
    }

    func didReceiveMemoryWarning() {
        Logging.shared.warning("Received memory warning")

        // Free memory from services
        let services = serviceRegistry.getAllServiceStates()
        for (serviceKey, _) in services {
            if let service = serviceRegistry.getService(for: ServiceKey(serviceKey)) as? MemoryManaged {
                service.freeMemoryResources()
            }
        }
    }

    // MARK: - Private Methods

    private func setupServices() {
        // Register core services
        let cloudKitManager = CloudKitSyncManager()
        serviceRegistry.registerService(cloudKitManager, for: .cloudSync)

        let intelligenceService = AppleIntelligenceService()
        serviceRegistry.registerService(intelligenceService, for: .intelligence)

        let errorHandler = ErrorHandlingService()
        serviceRegistry.registerService(errorHandler, for: .errorHandling)

        // Location service (actor-based)
        let locationService = LocationService()
        serviceRegistry.registerService(locationService, for: .location)

        let placesService = GooglePlacesService()
        serviceRegistry.registerService(placesService, for: .places)

        signposter.emitEvent("Services Registered")
        logger.log("Core services registered")

        Logging.shared.info("Services registered successfully")
    }
}

// MARK: - App State

enum AppState: Sendable, Equatable {
    case initializing
    case ready
    case failed(Error)
    case terminated

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing): return true
        case (.ready, .ready): return true
        case (.failed, .failed): return true
        case (.terminated, .terminated): return true
        default: return false
        }
    }

    var hasError: Bool {
        if case .failed = self { return true }
        return false
    }
}
