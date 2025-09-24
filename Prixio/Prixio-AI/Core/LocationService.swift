import Foundation
import CoreLocation
import UserNotifications
import SwiftData

actor LocationService: AppService {

    // MARK: - Notifications & Persistence Keys
    static let stateDidChangeNotification = Notification.Name("LocationService.stateDidChange")
    private static let hasShownUsageNotificationKey = "LocationService.hasShownUsageNotification"
    private static let allowTrackingDefaultsKey = "UserPreferences.allowLocationTracking"

    // MARK: - User Preference Gate
    // Controls whether the service should actively use location when authorized
    private var allowLocationTracking: Bool = false

    // MARK: - Runtime State Flags
    private(set) var isActivelyUpdating: Bool = false

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
        let isActivelyUpdating: Bool
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

        // Seed user preference from persisted defaults if available
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.allowTrackingDefaultsKey) != nil {
            allowLocationTracking = defaults.bool(forKey: Self.allowTrackingDefaultsKey)
        }

        // Start updates if authorized AND user has opted in
        if isAuthorizedForUse && allowLocationTracking {
            locationManager.startUpdatingLocation()
            isActivelyUpdating = true
            postStateDidChange()
            Task { await notifyLocationUsageOnceIfNeeded() }
        }

        state = .ready
    }

    func shutdown() throws {
        locationManager.stopUpdatingLocation()
        isActivelyUpdating = false
        postStateDidChange()
        state = .shutdown
    }

    func healthCheck() -> Bool {
        state.isReady && isAuthorizedForUse
    }

    // MARK: - Public API

    /// Enable or disable location tracking usage by the app (user-facing preference)
    func setAllowLocationTracking(_ allow: Bool) {
        allowLocationTracking = allow
        // Persist preference for next launch
        UserDefaults.standard.set(allow, forKey: Self.allowTrackingDefaultsKey)
        refreshAuthorizationStateAndMaybeStart()
    }

    /// Returns whether the app is allowed to use location features (user preference)
    func getAllowLocationTracking() -> Bool { allowLocationTracking }

    /// Convenience to request precise (full) accuracy when a feature truly needs it
    func requestPreciseLocationIfNeeded() {
        requestTemporaryFullAccuracyIfNeeded(purposeKey: Self.precisePurposeKey)
    }

    /// Call this when a feature truly requires precise location.
    func requestTemporaryFullAccuracyIfNeeded(purposeKey: String) {
        guard locationManager.accuracyAuthorization == .reducedAccuracy else { return }
        locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey) { [weak delegateBridge] error in
            // We can't capture self directly from here (escaping on non-actor thread). Use delegateBridge to bounce.
            delegateBridge?.notifyAuthorizationChanged()
        }
    }

    func startUpdatingLocationIfAuthorized() {
        guard isAuthorizedForUse, allowLocationTracking else { return }
        locationManager.startUpdatingLocation()
        isActivelyUpdating = true
        postStateDidChange()
        Task { await notifyLocationUsageOnceIfNeeded() }
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
        isActivelyUpdating = false
        postStateDidChange()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            currentLocation: currentLocation,
            authorizationStatus: authorizationStatus,
            accuracyAuthorization: accuracyAuthorization,
            isAuthorizedForUse: isAuthorizedForUse,
            hasPreciseAccuracy: hasPreciseAccuracy,
            isActivelyUpdating: isActivelyUpdating
        )
    }

    /// Detects a nearby store using the StoreDetectionService and the current location.
    /// - Parameter modelContext: SwiftData model context used to query known stores.
    /// - Returns: The best candidate and all candidates considered.
    func detectNearbyStore(using modelContext: ModelContext) async -> StoreDetectionService.Result {
        guard let loc = currentLocation else {
            return StoreDetectionService.Result(best: nil, candidates: [])
        }
        let detectionService = StoreDetectionService(modelContext: modelContext)
        return await detectionService.detectStore(near: loc)
    }

    /// Detects a nearby store using the StoreDetectionService with Wi‑Fi SSID support.
    /// - Parameters:
    ///   - modelContext: SwiftData model context used to query known stores.
    ///   - ssidMapping: Optional mapping from SSID strings to store name hints.
    /// - Returns: The best candidate and all candidates considered.
    func detectNearbyStore(using modelContext: ModelContext, ssidMapping: [String: String]) async -> StoreDetectionService.Result {
        guard let loc = currentLocation else {
            return StoreDetectionService.Result(best: nil, candidates: [])
        }
        let detectionService = StoreDetectionService(
            modelContext: modelContext,
            ssidProvider: { await CurrentSSIDProvider.shared.currentSSID() },
            ssidToStoreName: ssidMapping
        )
        return await detectionService.detectStore(near: loc)
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
        if isAuthorizedForUse && allowLocationTracking {
            locationManager.startUpdatingLocation()
            isActivelyUpdating = true
            postStateDidChange()
            Task { await notifyLocationUsageOnceIfNeeded() }
        } else {
            locationManager.stopUpdatingLocation()
            isActivelyUpdating = false
            postStateDidChange()
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

    // MARK: - Notifications & Transparency

    private func postStateDidChange() {
        NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: nil)
    }

    /// Sends a one-time local notification to transparently inform the user that location is in use.
    private func notifyLocationUsageOnceIfNeeded() async {
        guard isActivelyUpdating else { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.hasShownUsageNotificationKey) { return }

        // Request notification permission if needed and schedule a lightweight notification
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }

            let content = UNMutableNotificationContent()
            content.title = "Location in Use"
            content.body = "We use your location to show nearby results. You can change this anytime in Settings."

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "location-usage-once", content: content, trigger: trigger)
            try await center.add(request)

            defaults.set(true, forKey: Self.hasShownUsageNotificationKey)
        } catch {
            // Silently ignore; notifications are best-effort for transparency
        }
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

extension Notification.Name {
    static let locationServiceStateDidChange = LocationService.stateDidChangeNotification
}
