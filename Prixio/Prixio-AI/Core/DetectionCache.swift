import Foundation
import CoreLocation

/// Simple in-memory cache for detection candidates
actor DetectionCache {
    private struct Entry { let date: Date; let candidates: [DetectedCandidate] }
    private var storage: [String: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 180) { // default 3 minutes
        self.ttl = ttl
    }

    func key(for location: CLLocation) -> String {
        // Very coarse geohash-like key: ~100m precision via rounding
        let lat = (location.coordinate.latitude * 1000).rounded() / 1000
        let lon = (location.coordinate.longitude * 1000).rounded() / 1000
        return "\(lat),\(lon)"
    }

    func get(forKey key: String) -> [DetectedCandidate]? {
        guard let entry = storage[key] else { return nil }
        if Date().timeIntervalSince(entry.date) <= ttl { return entry.candidates }
        storage[key] = nil
        return nil
    }

    func set(_ candidates: [DetectedCandidate], forKey key: String) {
        storage[key] = Entry(date: Date(), candidates: candidates)
    }

    func clear() { storage.removeAll() }
}
