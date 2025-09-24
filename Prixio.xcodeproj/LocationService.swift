import Foundation
import CoreLocation

actor LocationService: AppService {

    // MARK: - AppService
    let identifier: String = "LocationService"
    let dependencies: [String] = []
    private(set) var state: ServiceState = .notInitialized

    static let precisePurposeKey = "PreciseLocationFeature"

    // MARK: - Core Location
    private let locationManager = CLLocationManager()
    private let delegateBridge = DelegateBridge()

    // MARK: - Published-like state (actor-isolated)
    private(set) var currentLocation: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var accuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy

    // Derived flags
    private(set) var isAuthorizedForUse: Bool = false
    private(set) var hasPreciseAccuracy: Bool = false

    struct Snapshot: Sendable {
        let currentLocation: CLLocation?
        let authorizationStatus: CLAuthorizationStatus
        let accuracyAuthorization: CLAccuracyAuthorization
        let isAuthorizedForUse: Bool
        let hasPreciseAccuracy: Bool
    }

    // MARK: - Initialization (AppService)
    func initialize() throws {
        guard state == .notInitialized || state == .shutdown else { return }
        state = .initializing

        // Configure delegate bridge
        delegateBridge.onAuthorizationChanged = { [weak self] in
            Task { await self?.refreshAuthorizationStateAndMaybeStart() }
        }
        delegateBridge.onLocationsUpdated = { [weak self] locations in
            Task { await self?.handleLocationUpdate(locations: locations) }
        }
        delegateBridge.onError = { [weak self] error in
            Task { await self?.handleLocationError(error) }
        }

        locationManager.delegate = delegateBridge
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        // Privacy-first: request When In Use only if needed
        requestWhenInUseIfNeeded()

        // Seed initial state
        refreshAuthorizationState()

        // Start updates if authorized
        if isAuthorizedForUse {
            locationManager.startUpdatingLocation()
        }

        state = .ready
    }

    func shutdown() throws {
        locationManager.stopUpdatingLocation()
        state = .shutdown
    }

    func healthCheck() -> Bool {
        state.isReady && isAuthorizedForUse
    }

    // MARK: - Public API

    /// Call this when a feature truly requires precise location.
    func requestTemporaryFullAccuracyIfNeeded(purposeKey: String) {
        guard locationManager.accuracyAuthorization == .reducedAccuracy else { return }
        locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey) { [weak delegateBridge] error in
            // We can't capture self directly from here (escaping on non-actor thread). Use delegateBridge to bounce.
            delegateBridge?.notifyAuthorizationChanged()
        }
    }

    func startUpdatingLocationIfAuthorized() {
        guard isAuthorizedForUse else { return }
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            currentLocation: currentLocation,
            authorizationStatus: authorizationStatus,
            accuracyAuthorization: accuracyAuthorization,
            isAuthorizedForUse: isAuthorizedForUse,
            hasPreciseAccuracy: hasPreciseAccuracy
        )
    }

    // MARK: - Internal state helpers

    private func requestWhenInUseIfNeeded() {
        switch type(of: locationManager).authorizationStatus() {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    private func refreshAuthorizationState() {
        authorizationStatus = type(of: locationManager).authorizationStatus()
        accuracyAuthorization = locationManager.accuracyAuthorization

        isAuthorizedForUse = {
            switch authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                return true
            default:
                return false
            }
        }()

        hasPreciseAccuracy = (accuracyAuthorization == .fullAccuracy)
    }

    private func refreshAuthorizationStateAndMaybeStart() {
        refreshAuthorizationState()
        if isAuthorizedForUse {
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
        }
    }

    private func handleLocationUpdate(locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest
    }

    private func handleLocationError(_ error: Error) {
        // Keep service in ready state; errors can be transient
        // Consider logging via your Logging system if available
    }
}

// MARK: - Delegate Bridge

private final class DelegateBridge: NSObject, CLLocationManagerDelegate {

    // Callbacks bounce back into the LocationService actor
    var onAuthorizationChanged: (() -> Void)?
    var onLocationsUpdated: (([CLLocation]) -> Void)?
    var onError: ((Error) -> Void)?

    func notifyAuthorizationChanged() {
        onAuthorizationChanged?()
    }

    // iOS 14+ unified callback for auth changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChanged?()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        onAuthorizationChanged?()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onLocationsUpdated?(locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error)
    }
}
