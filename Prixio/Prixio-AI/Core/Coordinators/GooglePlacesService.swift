import Foundation
import OSLog
import GooglePlaces
import Network
import CoreLocation

public enum PlacesError: Error, Sendable {
    case invalidAPIKey
    case quotaExceeded
    case rateLimited
    case networkUnavailable
    case offlineDataExpired
    case serviceUnavailable
    case unknown(String)
}

public struct PlaceSuggestion: Sendable {
    public let placeID: String
    public let primaryText: String
    public let secondaryText: String?

    public init(placeID: String, primaryText: String, secondaryText: String? = nil) {
        self.placeID = placeID
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }
}

public struct GooglePlaceDetails: Sendable {
    public let placeID: String
    public let name: String
    public let address: String?
    public let coordinate: (lat: Double, lon: Double)?
    public let phoneNumber: String?
    public let websiteURL: String?
    public let city: String?
    public let state: String?
    public let zipCode: String?
    public let country: String?

    public init(
        placeID: String,
        name: String,
        address: String? = nil,
        coordinate: (lat: Double, lon: Double)? = nil,
        phoneNumber: String? = nil,
        websiteURL: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zipCode: String? = nil,
        country: String? = nil
    ) {
        self.placeID = placeID
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.phoneNumber = phoneNumber
        self.websiteURL = websiteURL
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.country = country
    }
}

actor Debouncer {
    private let interval: TimeInterval
    private var lastScheduledTask: Task<Void, Never>?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public func schedule(_ block: @escaping () async -> Void) {
        lastScheduledTask?.cancel()

        lastScheduledTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { return }
            await block()
        }
    }
}

public struct SessionToken: Sendable {
    public let id: String
    public let createdAt: Date

    public init(id: String = UUID().uuidString, createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
}

actor PlacesCache {
    private var detailsStorage: [String: (details: GooglePlaceDetails, addedAt: Date)] = [:]
    private var durablePlaceIDs: Set<String> = []
    private let maxAgeInterval: TimeInterval

    public init(maxAgeDays: Int = 30) {
        maxAgeInterval = TimeInterval(maxAgeDays) * 24 * 60 * 60
    }

    public func setDetails(_ details: GooglePlaceDetails, date: Date = Date()) {
        detailsStorage[details.placeID] = (details, date)
        durablePlaceIDs.insert(details.placeID)
    }

    public func getDetails(for placeID: String) -> GooglePlaceDetails? {
        purgeExpired()
        if let entry = detailsStorage[placeID] {
            return entry.details
        }
        return nil
    }

    public func purgeExpired() {
        let now = Date()
        for (placeID, (_, addedAt)) in detailsStorage {
            if now.timeIntervalSince(addedAt) > maxAgeInterval {
                detailsStorage.removeValue(forKey: placeID)
                // Keep placeID in durablePlaceIDs but drop details when expired
            }
        }
    }

    public func storeDurablePlaceID(_ placeID: String) {
        durablePlaceIDs.insert(placeID)
    }

    public func snapshot() -> (details: [String: (details: GooglePlaceDetails, addedAt: Date)], durableIDs: Set<String>) {
        purgeExpired()
        return (detailsStorage, durablePlaceIDs)
    }
}

public enum StorePlaceType: String, Sendable, CaseIterable {
    case groceryOrSupermarket = "grocery_or_supermarket"
    case supermarket = "supermarket"
    case convenienceStore = "convenience_store"
}

actor NearbySearchCache {
    private struct Entry: Sendable {
        let key: String
        let details: [GooglePlaceDetails]
        let addedAt: Date
    }

    private var storage: [String: Entry] = [:]
    private let ttl: TimeInterval

    init(ttlSeconds: TimeInterval = 600) {
        self.ttl = ttlSeconds
    }

    func get(for key: String) -> [GooglePlaceDetails]? {
        purgeExpired()
        return storage[key]?.details
    }

    func set(_ details: [GooglePlaceDetails], for key: String) {
        storage[key] = Entry(key: key, details: details, addedAt: Date())
    }

    private func purgeExpired() {
        let now = Date()
        storage = storage.filter { now.timeIntervalSince($0.value.addedAt) <= ttl }
    }
}

final class GooglePlacesService: BaseService, MemoryManaged {
    private let signposter = OSSignposter(subsystem: "com.prixio.app", category: "places")
    private let logger = Logger(subsystem: "com.prixio.app", category: "places")

    private var apiKey: String?
    private var currentToken: SessionToken?
    private let debouncer = Debouncer(interval: 0.25)

    // Throttle properties for requests
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 0.15

    private let cache = PlacesCache()

    // Network reachability via NWPathMonitor
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.prixio.app.places.reachability")
    private var isNetworkReachable: Bool = true

    // Google Places session token
    private var gmsSessionToken: GMSAutocompleteSessionToken?

    // Simple request budgets per 60s window
    private var autocompleteBudget = RateBudget(maxRequests: 30, windowSeconds: 60)
    private var detailsBudget = RateBudget(maxRequests: 60, windowSeconds: 60)
    private var nearbyBudget = RateBudget(maxRequests: 30, windowSeconds: 60)
    private let nearbyCache = NearbySearchCache()

    // Cooldown/backoff state
    private var cooldownUntil: Date?

    override init(identifier: String = "GooglePlacesService") {
        super.init(identifier: identifier)
    }

    override func performInitialization() throws {
        // Configure API key from code (Secrets.swift)
        let key = Secrets.googlePlacesAPIKey
        guard !key.isEmpty else {
            logger.error("GooglePlacesService API key not provided in code")
            throw PrixioError.serviceInitializationFailed("GooglePlacesService", underlying: PlacesError.invalidAPIKey)
        }
        apiKey = key
        GMSPlacesClient.provideAPIKey(key)
        logger.info("GooglePlacesService SDK configured via code API key")

        // Start reachability monitoring
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let reachable = (path.status == .satisfied)
            self?.isNetworkReachable = reachable
            self?.logger.info("Reachability changed: \(reachable, privacy: .public)")
        }
        pathMonitor.start(queue: pathMonitorQueue)

        // Load persisted cache (async)
        Task {
            if let snapshot = try? await PlacesCacheStore.shared.load() {
                for (_, entry) in snapshot.details {
                    let coordTuple: (lat: Double, lon: Double)? = {
                        if let coord = entry.details.coordinate {
                            return (lat: coord.latitude, lon: coord.longitude)
                        } else {
                            return nil
                        }
                    }()

                    let mapped = GooglePlaceDetails(
                        placeID: entry.details.placeID,
                        name: entry.details.name,
                        address: entry.details.address,
                        coordinate: coordTuple,
                        phoneNumber: entry.details.phoneNumber,
                        websiteURL: nil,
                        city: nil,
                        state: nil,
                        zipCode: nil,
                        country: nil
                    )

                    await cache.setDetails(mapped, date: entry.addedAt)
                }
                for id in snapshot.durableIDs {
                    await cache.storeDurablePlaceID(id)
                }
            }
        }
    }

    override func performShutdown() throws {
        pathMonitor.cancel()
    }

    override func performHealthCheck() -> Bool {
        return apiKey != nil
    }

    // MARK: - MemoryManaged

    var memoryUsage: Int { 64 * 1024 }
    func freeMemoryResources() { /* No-op for now */ }
    func optimizeMemoryUsage() { /* No-op for now */ }

    // MARK: - Public API

    public func beginAutocompleteSession() {
        currentToken = SessionToken()
        gmsSessionToken = GMSAutocompleteSessionToken()
        if let token = currentToken {
            signposter.emitEvent("Autocomplete Session Started")
            logger.info("Autocomplete session started with token \(token.id, privacy: .public)")
        }
    }

    public func cancelAutocompleteSession() {
        if let token = currentToken {
            signposter.emitEvent("Autocomplete Session Cancelled")
            logger.info("Autocomplete session cancelled with token \(token.id, privacy: .public)")
        }
        currentToken = nil
        gmsSessionToken = nil
    }

    public func autocomplete(query: String) async throws -> [PlaceSuggestion] {
        guard let _ = apiKey else {
            logger.error("Autocomplete called without valid API key")
            throw PlacesError.invalidAPIKey
        }

        if currentToken == nil || gmsSessionToken == nil {
            beginAutocompleteSession()
        }

        try enforceCooldownIfNeeded()

        if !isNetworkReachable {
            logger.warning("Autocomplete fallback: network unreachable, using cache")
            return await cachedSuggestions(matching: query)
        }

        // Budget check
        try autocompleteBudget.consumeOrThrow()

        // Throttle requests to avoid spamming the service
        if let last = lastRequestTime {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minRequestInterval {
                let delay = minRequestInterval - elapsed
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        lastRequestTime = Date()

        // Debounce a touch
        try await Task.sleep(nanoseconds: UInt64(0.15 * 1_000_000_000))

        let token = gmsSessionToken

        do {
            let predictions: [GMSAutocompletePrediction] = try await withCheckedThrowingContinuation { cont in
                GMSPlacesClient.shared().findAutocompletePredictions(fromQuery: query, filter: nil, sessionToken: token) { results, error in
                    if let error { return cont.resume(throwing: self.mapError(error)) }
                    cont.resume(returning: results ?? [])
                }
            }

            let mapped = predictions.map { pred in
                PlaceSuggestion(
                    placeID: pred.placeID,
                    primaryText: pred.attributedPrimaryText.string,
                    secondaryText: pred.attributedSecondaryText?.string
                )
            }
            return mapped
        } catch {
            let mapped = mapError(error)
            if let pe = mapped as? PlacesError {
                switch pe {
                case .rateLimited:
                    setCooldown(for: 30) // short backoff
                case .quotaExceeded:
                    setCooldown(for: 300) // longer backoff for quota exhaustion
                default:
                    break
                }
            }
            logger.error("Autocomplete failed, falling back to cache: \(String(describing: error), privacy: .public)")
            return await cachedSuggestions(matching: query)
        }
    }

    public func didSelectPlace(with placeID: String) {
        cancelAutocompleteSession()
        logger.info("Place selected with placeID \(placeID, privacy: .public)")
    }

    public func fetchPlaceDetails(placeID: String) async throws -> GooglePlaceDetails {
        if let cached = await cache.getDetails(for: placeID) {
            logger.info("Returning cached place details for placeID \(placeID, privacy: .public)")
            return cached
        }

        guard let _ = apiKey else {
            logger.error("fetchPlaceDetails called without valid API key")
            throw PlacesError.invalidAPIKey
        }

        try enforceCooldownIfNeeded()

        if !isNetworkReachable {
            logger.warning("fetchPlaceDetails fallback: network unreachable")
            throw PrixioError.networkError(.noConnection, context: "places.fetchPlaceDetails")
        }

        // Budget check
        try detailsBudget.consumeOrThrow()

        let signpostID = signposter.makeSignpostID()
        let interval = signposter.beginInterval("FetchPlaceDetails", id: signpostID)
        defer { signposter.endInterval("FetchPlaceDetails", interval) }

        let fields: GMSPlaceField = [.name, .formattedAddress, .coordinate, .phoneNumber, .placeID, .addressComponents, .website]
        let token = gmsSessionToken

        do {
            let place: GMSPlace = try await withCheckedThrowingContinuation { cont in
                GMSPlacesClient.shared().fetchPlace(fromPlaceID: placeID, placeFields: fields, sessionToken: token) { place, error in
                    if let error { return cont.resume(throwing: self.mapError(error)) }
                    guard let place else { return cont.resume(throwing: PlacesError.unknown("No place returned")) }
                    cont.resume(returning: place)
                }
            }

            // Extract address components
            var city: String?
            var state: String?
            var zip: String?
            var country: String?
            if let components = place.addressComponents {
                for comp in components {
                    let types = comp.types
                    if types.contains("locality") {
                        city = comp.name
                    } else if types.contains("administrative_area_level_1") {
                        state = comp.shortName
                    } else if types.contains("postal_code") {
                        zip = comp.name
                    } else if types.contains("country") {
                        country = comp.shortName ?? comp.name
                    }
                }
            }

            let details = GooglePlaceDetails(
                placeID: place.placeID ?? placeID,
                name: place.name ?? "",
                address: place.formattedAddress,
                coordinate: (lat: place.coordinate.latitude, lon: place.coordinate.longitude),
                phoneNumber: place.phoneNumber,
                websiteURL: place.website?.absoluteString,
                city: city,
                state: state,
                zipCode: zip,
                country: country
            )

            await cache.setDetails(details)
            // Persist snapshot to disk (best-effort)
            do {
                _ = try await PlacesCacheStore.shared.saveSnapshot(from: cache)
            } catch {
                logger.warning("Failed to persist places cache: \(String(describing: error), privacy: .public)")
            }

            return details
        } catch {
            let mapped = mapError(error)
            if let pe = mapped as? PlacesError {
                switch pe {
                case .rateLimited:
                    setCooldown(for: 30)
                case .quotaExceeded:
                    setCooldown(for: 300)
                default:
                    break
                }
            }
            throw mapped
        }
    }

    // Infers a store chain name from details.name and website host
    private func inferChainName(from details: GooglePlaceDetails) -> String? {
        let lowerName = details.name.lowercased()
        var host: String? = nil
        if let urlStr = details.websiteURL, let comps = URLComponents(string: urlStr) {
            host = comps.host?.lowercased()
        }

        // Map of chain -> identifiers (keywords and/or host substrings)
        let chains: [String: [String]] = [
            "Walmart": ["walmart", "walmart.com"],
            "Target": ["target", "target.com"],
            "Costco": ["costco", "costco.com"],
            "Safeway": ["safeway", "safeway.com"],
            "Kroger": ["kroger", "kroger.com"],
            "Whole Foods": ["whole foods", "wholefoods", "wholefoodsmarket.com"],
            "Trader Joe's": ["trader joe", "traderjoes", "traderjoes.com"],
            "ALDI": ["aldi", "aldi.us", "aldi.com"],
            "Lidl": ["lidl", "lidl.com"],
            "Sam's Club": ["sam's club", "sams club", "samsclub", "samsclub.com"],
            "Albertsons": ["albertsons", "albertsons.com"],
            "Publix": ["publix", "publix.com"],
            "H‑E‑B": ["heb", "h‑e‑b", "heb.com"],
            "Meijer": ["meijer", "meijer.com"],
            "Fred Meyer": ["fred meyer", "fredmeyer", "fredmeyer.com"]
        ]

        for (chain, identifiers) in chains {
            for id in identifiers {
                let idLower = id.lowercased()
                if lowerName.contains(idLower) { return chain }
                if let h = host, h.contains(idLower) { return chain }
            }
        }
        return nil
    }

    // MARK: - Nearby Store Search (Google Places Web Service)

    /// Searches for nearby grocery/supermarket stores using Google Places Web Service.
    /// - Parameters:
    ///   - center: Center coordinate to search around.
    ///   - radiusMeters: Search radius in meters (max 50,000 for Nearby Search).
    ///   - types: Store place types to filter. If empty, falls back to keyword "grocery store".
    ///   - limit: Maximum number of results to return after ranking.
    /// - Returns: An array of Store model instances (not persisted), ranked by distance ascending.
    public func searchNearbyStores(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        types: [StorePlaceType] = [.groceryOrSupermarket, .supermarket],
        limit: Int = 20
    ) async throws -> [Store] {
        guard let apiKey else {
            logger.error("Nearby search called without valid API key")
            throw PlacesError.invalidAPIKey
        }

        try enforceCooldownIfNeeded()

        if !isNetworkReachable {
            logger.warning("Nearby search fallback: network unreachable")
            throw PrixioError.networkError(.noConnection, context: "places.nearby")
        }

        // Budget check
        try nearbyBudget.consumeOrThrow()

        // Cache key: geohash-like rounding + types + radius
        let key = nearbyCacheKey(center: center, radius: radiusMeters, types: types)
        if let cached = await nearbyCache.get(for: key) {
            logger.info("Returning cached nearby results: count=\(cached.count, privacy: .public)")
            let stores = cached.compactMap { self.mapDetailsToStore($0) }
            return Array(stores.prefix(limit))
        }

        // Perform one or more Nearby Search requests (one per type if provided)
        var uniqueByPlaceID: [String: GooglePlaceDetails] = [:]

        if types.isEmpty {
            let results = try await nearbySearchRequest(center: center, radiusMeters: radiusMeters, type: nil, keyword: "grocery store", apiKey: apiKey)
            for details in results { uniqueByPlaceID[details.placeID] = details }
        } else {
            for t in types {
                let results = try await nearbySearchRequest(center: center, radiusMeters: radiusMeters, type: t.rawValue, keyword: nil, apiKey: apiKey)
                for details in results { uniqueByPlaceID[details.placeID] = details }
            }
        }

        // Rank by distance from center
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var detailsList = Array(uniqueByPlaceID.values)
        detailsList.sort { lhs, rhs in
            let ld = lhs.coordinate.map { CLLocation(latitude: $0.lat, longitude: $0.lon) }.map { $0.distance(from: centerLoc) } ?? .greatestFiniteMagnitude
            let rd = rhs.coordinate.map { CLLocation(latitude: $0.lat, longitude: $0.lon) }.map { $0.distance(from: centerLoc) } ?? .greatestFiniteMagnitude
            return ld < rd
        }

        // Cache before mapping to Store to keep cache lightweight
        await nearbyCache.set(detailsList, for: key)

        let stores = detailsList.compactMap { self.mapDetailsToStore($0) }
        return Array(stores.prefix(limit))
    }

    // Builds a stable cache key for nearby searches
    private func nearbyCacheKey(center: CLLocationCoordinate2D, radius: CLLocationDistance, types: [StorePlaceType]) -> String {
        func round(_ value: Double, places: Int) -> Double {
            let p = pow(10.0, Double(places))
            return (value * p).rounded() / p
        }
        let lat = round(center.latitude, places: 4)
        let lon = round(center.longitude, places: 4)
        let r = Int(radius)
        let typeKey = types.map { $0.rawValue }.sorted().joined(separator: ",")
        return "lat=\(lat)|lon=\(lon)|r=\(r)|t=\(typeKey)"
    }

    // Executes a Nearby Search request and returns GooglePlaceDetails for each result (fetching details for mapping)
    private func nearbySearchRequest(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        type: String?,
        keyword: String?,
        apiKey: String
    ) async throws -> [GooglePlaceDetails] {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "location", value: "\(center.latitude),\(center.longitude)"),
            URLQueryItem(name: "radius", value: String(Int(radiusMeters))),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let type { queryItems.append(URLQueryItem(name: "type", value: type)) }
        if let keyword { queryItems.append(URLQueryItem(name: "keyword", value: keyword)) }
        components.queryItems = queryItems

        let url = components.url!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PlacesError.serviceUnavailable
        }

        let decoded = try JSONDecoder().decode(NearbySearchResponse.self, from: data)
        if let status = decoded.status, status != "OK" && status != "ZERO_RESULTS" {
            if status == "OVER_QUERY_LIMIT" { setCooldown(for: 300); throw PlacesError.quotaExceeded }
            if status == "REQUEST_DENIED" || status == "INVALID_REQUEST" { throw PlacesError.serviceUnavailable }
        }

        let placeIDs = decoded.results?.compactMap { $0.place_id } ?? []
        var details: [GooglePlaceDetails] = []
        for pid in placeIDs {
            do {
                let d = try await fetchPlaceDetails(placeID: pid)
                details.append(d)
            } catch {
                // Best-effort: skip individual failures
                continue
            }
        }
        return details
    }

    // Maps a GooglePlaceDetails to a Store model instance (not inserted/persisted)
    private func mapDetailsToStore(_ details: GooglePlaceDetails) -> Store? {
        guard let coord = details.coordinate else { return nil }
        // Require minimal address pieces for Store
        guard let address = details.address,
              let city = details.city,
              let state = details.state,
              let zip = details.zipCode,
              let country = details.country else {
            return nil
        }

        let store = Store(
            name: details.name,
            chain: inferChainName(from: details),
            address: address,
            city: city,
            state: state,
            zipCode: zip,
            country: country,
            phoneNumber: details.phoneNumber,
            website: details.websiteURL,
            latitude: coord.lat,
            longitude: coord.lon,
            locationAccuracy: nil
        )
        return store
    }

    public func storeDurablePlaceID(_ placeID: String) {
        Task {
            await cache.storeDurablePlaceID(placeID)
        }
        logger.info("Stored durable placeID \(placeID, privacy: .public)")
    }

    public func purgeExpiredCache() {
        Task {
            await cache.purgeExpired()
            logger.info("Purged expired place details from cache")
        }
    }

    public func setNetworkReachable(_ reachable: Bool) {
        isNetworkReachable = reachable
        logger.info("Network reachability set to \(reachable, privacy: .public)")
    }

    // MARK: - Error Mapping Helper

    private func enforceCooldownIfNeeded() throws {
        if let until = cooldownUntil, Date() < until {
            throw PlacesError.rateLimited
        }
    }

    private func setCooldown(for seconds: TimeInterval) {
        cooldownUntil = Date().addingTimeInterval(seconds)
    }

    private func mapError(_ error: Error) -> Error {
        if let prixioError = error as? PrixioError { return prixioError }
        if let placesError = error as? PlacesError { return placesError }

        let nsError = error as NSError

        // Google Places specific mapping
        if nsError.domain == kGMSPlacesErrorDomain, let code = GMSPlacesErrorCode(rawValue: nsError.code) {
            switch code {
            case .rateLimitExceeded:
                return PlacesError.rateLimited
            case .keyInvalid, .keyExpired:
                return PlacesError.invalidAPIKey
            case .networkError:
                return PrixioError.networkError(.noConnection, context: "places.network")
            case .serverError, .internalError:
                return PlacesError.serviceUnavailable
            default:
                break
            }
            // Heuristic: detect quota exceeded in error message when SDK doesn't expose a separate code
            let lowerDesc = nsError.localizedDescription.lowercased()
            if lowerDesc.contains("over_query_limit") || lowerDesc.contains("quota") {
                return PlacesError.quotaExceeded
            }
        }

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return PrixioError.networkError(.noConnection, context: "places.network")
            case NSURLErrorTimedOut:
                return PrixioError.networkError(.timeout, context: "places.network")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return PrixioError.networkError(.noConnection, context: "places.network")
            default:
                break
            }
        }

        return PlacesError.unknown(nsError.localizedDescription)
    }

    private func cachedSuggestions(matching query: String) async -> [PlaceSuggestion] {
        let snap = await cache.snapshot()
        let values = snap.details.values.map { $0.details }
        let filtered = values.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.address?.localizedCaseInsensitiveContains(query) ?? false) }
        return filtered.map { PlaceSuggestion(placeID: $0.placeID, primaryText: $0.name, secondaryText: $0.address) }
    }
}

fileprivate struct RateBudget {
    private let maxRequests: Int
    private let windowSeconds: TimeInterval
    private var windowStart: Date = Date()
    private var count: Int = 0

    init(maxRequests: Int, windowSeconds: TimeInterval) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }

    mutating func consumeOrThrow() throws {
        let now = Date()
        if now.timeIntervalSince(windowStart) > windowSeconds {
            windowStart = now
            count = 0
        }
        if count >= maxRequests {
            throw PlacesError.rateLimited
        }
        count += 1
    }
}

// MARK: - Nearby Search Response Models
private struct NearbySearchResponse: Decodable {
    let results: [NearbySearchPlace]?
    let status: String?
}

private struct NearbySearchPlace: Decodable {
    let place_id: String?
    let name: String?
    let geometry: NearbyGeometry?
    let vicinity: String?
}

private struct NearbyGeometry: Decodable {
    let location: NearbyLocation?
}

private struct NearbyLocation: Decodable {
    let lat: Double?
    let lng: Double?
}
