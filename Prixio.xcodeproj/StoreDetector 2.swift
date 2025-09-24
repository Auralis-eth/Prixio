//actor PlacesAPIDetector: AppService {
//    let identifier = "PlacesAPIDetector"
//    let dependencies: [String] = []
//    private(set) var state: ServiceState = .notInitialized
//
//    // Use the multi-provider service for cost-optimized, resilient results
//    private var placesService: MultiProviderPlacesService?
//
//    func initialize() async throws {
//        state = .initializing
//        let service = MultiProviderPlacesService()
//        try await service.initialize()
//        placesService = service
//        state = .ready
//    }
//
//    func shutdown() async throws {
//        if let service = placesService {
//            try await service.shutdown()
//        }
//        placesService = nil
//        state = .shutdown
//    }
//
//    func healthCheck() async -> Bool {
//        guard state.isReady, let service = placesService else { return false }
//        return await service.healthCheck()
//    }
//
//    func detectStores(near location: CLLocation) async throws -> [StoreCandidate] {
//        guard state.isReady, let service = placesService else { return [] }
//
//        // Use a sane default radius; prefer configuration if available
//        let radiusMeters = Int(LocationServicesConfiguration.storeDetectionRadius)
//
//        do {
//            let results = try await service.searchNearbyPlaces(
//                location: location,
//                radius: radiusMeters,
//                placeType: .grocery,
//                maxResults: LocationServicesConfiguration.maxStoreCandidates
//            )
//
//            // Map provider-agnostic results to StoreCandidate
//            let candidates: [StoreCandidate] = results.compactMap { result in
//                let store = Store.from(placeResult: result)
//                let distance = result.distance ?? location.distance(from: result.location)
//                let confidence = max(0.0, min(1.0, result.confidence))
//                return StoreCandidate(
//                    store: store,
//                    source: .placesAPI,
//                    confidence: confidence,
//                    distance: distance
//                )
//            }
//
//            return candidates
//        } catch {
//            // On failure, return empty and let other detectors contribute
//            return []
//        }
//    }
//}
//
//actor WiFiDetector: AppService {
//    let identifier = "WiFiDetector"
//    let dependencies: [String] = []
//    private(set) var state: ServiceState = .notInitialized
//
//    private var scanner: WiFiScanner?
//    private var fingerprintDB: WiFiFingerprintDatabase?
//
//    func initialize() async throws {
//        state = .initializing
//        let scanner = WiFiScanner()
//        let db = WiFiFingerprintDatabase()
//        try await scanner.initialize()
//        try await db.initialize()
//        self.scanner = scanner
//        self.fingerprintDB = db
//        state = .ready
//    }
//
//    func shutdown() async throws {
//        if let scanner = scanner { try await scanner.shutdown() }
//        if let db = fingerprintDB { try await db.shutdown() }
//        scanner = nil
//        fingerprintDB = nil
//        state = .shutdown
//    }
//
//    func healthCheck() async -> Bool {
//        guard state.isReady else { return false }
//        return true
//    }
//
//    func detectStores() async throws -> [StoreCandidate] {
//        guard state.isReady, let scanner = scanner, let fingerprintDB = fingerprintDB else {
//            return []
//        }
//
//        do {
//            let signals = try await scanner.scanAvailableNetworks()
//            let matches = await fingerprintDB.matchFingerprint(signals)
//
//            let candidates = matches.map { match in
//                StoreCandidate(
//                    store: match.store,
//                    source: .wifiFingerprint,
//                    confidence: max(0.0, min(1.0, Float(match.confidence))),
//                    distance: nil
//                )
//            }
//
//            return candidates
//        } catch {
//            // If WiFi scanning is not permitted or fails, degrade gracefully
//            return []
//        }
//    }
//}
//
//actor GPSDetector: AppService {
//    // ... other parts of the actor unchanged ...
//
//    func detectStores(near location: CLLocation) async throws -> [StoreCandidate] {
//        // Query the local store database; this may be empty initially
//        // until the app builds a local store cache.
//        let nearbyStores: [Store]
//        do {
//            nearbyStores = try await StoreDatabase.shared.findNearbyStores(location: location, radius: 500)
//        } catch {
//            return []
//        }
//
//        return nearbyStores.map { store in
//            let distance = store.distance(from: location)
//            // Simple confidence model: closer = higher confidence
//            let confidence: Float
//            switch distance {
//            case ..<50: confidence = 0.95
//            case ..<150: confidence = 0.85
//            case ..<300: confidence = 0.75
//            default: confidence = 0.6
//            }
//
//            return StoreCandidate(
//                store: store,
//                source: .gps,
//                confidence: confidence,
//                distance: distance
//            )
//        }
//    }
//}
