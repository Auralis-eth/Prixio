import Foundation
import CoreLocation
import SwiftData
import MapKit

/// Orchestrates multi-modal store detection with scoring, ranking, caching, and fallbacks
final class StoreDetectionService {

    // Dependencies
    private let cache: DetectionCache
    private let modelContext: ModelContext?
    private let ssidProvider: () async -> String?
    private let ssidToStoreName: [String: String]

    init(
        cache: DetectionCache = DetectionCache(),
        modelContext: ModelContext? = nil,
        ssidProvider: @escaping () async -> String? = { nil },
        ssidToStoreName: [String: String] = [:]
    ) {
        self.cache = cache
        self.modelContext = modelContext
        self.ssidProvider = ssidProvider
        self.ssidToStoreName = ssidToStoreName
    }

    struct Result: Sendable {
        let best: DetectedCandidate?
        let candidates: [DetectedCandidate]
    }

    // MARK: - Public API

    func detectStore(near location: CLLocation, preferCache: Bool = true) async -> Result {
        let cacheKey = await cache.key(for: location)
        if preferCache, let cached = await cache.get(forKey: cacheKey), let best = cached.max(by: { $0.score < $1.score }) {
            return Result(best: best, candidates: cached)
        }

        var allCandidates: [DetectedCandidate] = []

        // 1) GPS
        let gpsCandidates = await detectViaGPS(near: location)
        allCandidates.append(contentsOf: gpsCandidates)
        if let best = pickBestCandidate(from: allCandidates), best.score >= 0.6 {
            await cache.set(allCandidates, forKey: cacheKey)
            return Result(best: best, candidates: allCandidates)
        }

        // 2) WiFi
        let wifiCandidates = await detectViaWiFi(near: location)
        allCandidates.append(contentsOf: wifiCandidates)
        if let best = pickBestCandidate(from: allCandidates), best.score >= 0.6 {
            await cache.set(allCandidates, forKey: cacheKey)
            return Result(best: best, candidates: allCandidates)
        }

        // 3) Places API
        let placesCandidates = await detectViaPlacesAPI(near: location)
        allCandidates.append(contentsOf: placesCandidates)

        let best = pickBestCandidate(from: allCandidates)
        await cache.set(allCandidates, forKey: cacheKey)
        return Result(best: best, candidates: allCandidates)
    }

    // MARK: - Modalities

    private func detectViaGPS(near location: CLLocation) async -> [DetectedCandidate] {
        // If we have SwiftData stores, fetch nearby stores and score by distance
        guard let modelContext else { return [] }
        do {
            // Fetch all stores (optimize with proper predicate and distance filtering later)
            let descriptor = FetchDescriptor<Store>()
            let stores = try modelContext.fetch(descriptor)
            let candidates: [DetectedCandidate] = stores.compactMap { store in
                let storeLocation = CLLocation(latitude: store.latitude, longitude: store.longitude)
                let distance = location.distance(from: storeLocation)
                var score = distanceScore(distanceMeters: distance)
                score += sourceBonus(.gps)
                score = min(score, 1.0)
                return DetectedCandidate(storeID: store.id, name: store.name, location: storeLocation, source: .gps, score: score)
            }
            return candidates.sorted { $0.score > $1.score }.prefix(10).map { $0 }
        } catch {
            return []
        }
    }

    private func detectViaWiFi(near location: CLLocation) async -> [DetectedCandidate] {
        guard let modelContext else { return [] }
        guard let ssid = await ssidProvider(), let mappedName = ssidToStoreName[ssid] else { return [] }
        do {
            // Try to find a store by name (simple contains match)
            let descriptor = FetchDescriptor<Store>()
            let stores = try modelContext.fetch(descriptor)
            let matches = stores.filter { $0.name.localizedCaseInsensitiveContains(mappedName) }
            let candidates: [DetectedCandidate] = matches.map { store in
                let storeLocation = CLLocation(latitude: store.latitude, longitude: store.longitude)
                let distance = location.distance(from: storeLocation)
                var score = distanceScore(distanceMeters: distance)
                score += sourceBonus(.wifi) // strong boost for WiFi confirmation
                return DetectedCandidate(storeID: store.id, name: store.name, location: storeLocation, source: .wifi, score: min(score, 1.0))
            }
            return candidates.sorted { $0.score > $1.score }
        } catch {
            return []
        }
    }

    private func detectViaPlacesAPI(near location: CLLocation) async -> [DetectedCandidate] {
        // Use MapKit local search for nearby grocery/retail stores
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "grocery store"
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let items = response.mapItems
            let candidates: [DetectedCandidate] = items.compactMap { item in
                guard let name = item.name, let coord = item.placemark.location?.coordinate else { return nil }
                let storeLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let distance = location.distance(from: storeLocation)
                var score = distanceScore(distanceMeters: distance)
                score += sourceBonus(.places)
                return DetectedCandidate(storeID: nil, name: name, location: storeLocation, source: .places, score: min(score, 1.0))
            }
            return candidates.sorted { $0.score > $1.score }.prefix(10).map { $0 }
        } catch {
            return []
        }
    }

    // MARK: - Scoring & Ranking

    private func distanceScore(distanceMeters: CLLocationDistance) -> Double {
        // Score 1.0 within 0m, taper to 0 by 200m (adjust as needed)
        let maxDistance: CLLocationDistance = 200
        let clamped = max(0, min(1, 1 - (distanceMeters / maxDistance)))
        return clamped
    }

    private func sourceBonus(_ source: DetectedCandidate.Source) -> Double {
        switch source {
        case .gps: return 0.05
        case .wifi: return 0.5
        case .places: return 0.25
        }
    }

    private func pickBestCandidate(from candidates: [DetectedCandidate]) -> DetectedCandidate? {
        candidates.max(by: { $0.score < $1.score })
    }
}
