import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var locationAccuracy: CLLocationAccuracy = kCLLocationAccuracyReduced

    // MARK: - Capture Context (for PriceEntry metadata)
    struct DetectionContext {
        var source: DetectionSource
        var confidence: Float
        var wasAutoSelected: Bool
        var captureLatitude: Double?
        var captureLongitude: Double?
        var captureHorizontalAccuracy: Double?
        var captureAltitude: Double?
        var captureFloorLevel: Int?
        var placeProvider: String?
        var placeProviderPlaceId: String?
    }

    private var lastDetectionContext: DetectionContext?

    func detectStores() {
        // existing code to detect candidate stores
        let sortedCandidates = /* sorting logic */
        detectedStores = sortedCandidates

        if let bestCandidate = sortedCandidates.first, bestCandidate.confidence > 0.9 {
            currentStore = bestCandidate.store
            // Record detection context for later PriceEntry metadata
            lastDetectionContext = DetectionContext(
                source: bestCandidate.source,
                confidence: bestCandidate.confidence,
                wasAutoSelected: true,
                captureLatitude: self.currentLocation?.coordinate.latitude,
                captureLongitude: self.currentLocation?.coordinate.longitude,
                captureHorizontalAccuracy: self.locationAccuracy,
                captureAltitude: nil,
                captureFloorLevel: nil,
                placeProvider: nil,
                placeProviderPlaceId: nil
            )
            logger.info("Auto-selected store: \(bestCandidate.store.name) (confidence: \(bestCandidate.confidence))")
        }
    }

    func selectStore(_ store: Store) async {
        logger.info("Manually selected store: \(store.name)")
        currentStore = store

        // Record manual selection context for PriceEntry metadata
        lastDetectionContext = DetectionContext(
            source: .manual,
            confidence: 1.0,
            wasAutoSelected: false,
            captureLatitude: currentLocation?.coordinate.latitude,
            captureLongitude: currentLocation?.coordinate.longitude,
            captureHorizontalAccuracy: locationAccuracy,
            captureAltitude: nil,
            captureFloorLevel: nil,
            placeProvider: nil,
            placeProviderPlaceId: nil
        )

        // Learn WiFi fingerprint opportunistically (best-effort)
        Task {
            let scanner = WiFiScanner()
            let db = WiFiFingerprintDatabase()
            do {
                try await scanner.initialize()
                try await db.initialize()
                let signals = try await scanner.scanAvailableNetworks()
                await db.learnFingerprint(for: store, signals: signals)
                try? await db.shutdown()
                try? await scanner.shutdown()
                logger.info("WiFi fingerprint learned for store: \(store.name)")
            } catch {
                logger.debug("WiFi fingerprint learning skipped/failed: \(error.localizedDescription)")
            }
        }

        // Record visit for geofencing
        await geofenceManager?.recordStoreVisit(store)
    }

    /// Build a tuple of metadata values to populate a PriceEntry with detection context
    func currentPriceEntryMetadata() -> (
        captureLatitude: Double?,
        captureLongitude: Double?,
        captureHorizontalAccuracy: Double?,
        captureAltitude: Double?,
        captureFloorLevel: Int?,
        storeDetectionSource: StoreDetectionSource,
        storeDetectionConfidence: Float,
        placeProvider: String?,
        placeProviderPlaceId: String?,
        wasAutoSelected: Bool
    ) {
        let ctx = lastDetectionContext
        // Map DetectionSource to PriceEntry.StoreDetectionSource
        let mappedSource: StoreDetectionSource = {
            switch ctx?.source {
            case .gps: return .gps
            case .wifiFingerprint: return .wifiFingerprint
            case .placesAPI: return .placesAPI
            case .userHistory: return .userHistory
            case .manual: return .manual
            case .combined(_): return .combined
            case .none: return .manual
            }
        }()

        return (
            captureLatitude: ctx?.captureLatitude ?? currentLocation?.coordinate.latitude,
            captureLongitude: ctx?.captureLongitude ?? currentLocation?.coordinate.longitude,
            captureHorizontalAccuracy: ctx?.captureHorizontalAccuracy ?? locationAccuracy,
            captureAltitude: ctx?.captureAltitude,
            captureFloorLevel: ctx?.captureFloorLevel,
            storeDetectionSource: mappedSource,
            storeDetectionConfidence: ctx?.confidence ?? 1.0,
            placeProvider: ctx?.placeProvider,
            placeProviderPlaceId: ctx?.placeProviderPlaceId,
            wasAutoSelected: ctx?.wasAutoSelected ?? false
        )
    }
}
