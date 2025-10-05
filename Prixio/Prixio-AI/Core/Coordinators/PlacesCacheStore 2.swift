import Foundation
import OSLog

// DTOs for persistence, decoupled from GooglePlaces SDK types
private struct PersistedCoordinate: Codable { let lat: Double; let lon: Double }
private struct PersistedPlaceDetails: Codable {
    let placeID: String
    let name: String
    let address: String?
    let coordinate: PersistedCoordinate?
    let phoneNumber: String?
}

private struct PersistedEntry: Codable {
    let details: PersistedPlaceDetails
    let addedAt: Date
}

private struct PersistedSnapshot: Codable {
    let version: Int
    let details: [String: PersistedEntry]
    let durableIDs: [String]
}

// Public-facing snapshot that matches GooglePlacesService expectations
struct PlacesCacheSnapshot: Sendable {
    let details: [String: (details: GooglePlaceDetailsCompat, addedAt: Date)]
    let durableIDs: Set<String>
}

// A compatibility struct so this store does not depend on GooglePlacesService internals
struct GooglePlaceDetailsCompat: Sendable {
    let placeID: String
    let name: String
    let address: String?
    let coordinate: (latitude: Double, longitude: Double)?
    let phoneNumber: String?
}

final class PlacesCacheStoreV2 {
    static let shared = PlacesCacheStoreV2()
    private init() {}

    private let logger = Logger(subsystem: "com.prixio.app", category: "places-cache")
    private let fileName = "places-cache.json"
    private let currentVersion = 1

    // MARK: - Public API

    func load() async throws -> PlacesCacheSnapshot {
        let url = try cacheFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PlacesCacheSnapshot(details: [:], durableIDs: [])
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(PersistedSnapshot.self, from: data)

        // Migration hook by version if needed
        _ = persisted.version

        var mappedDetails: [String: (details: GooglePlaceDetailsCompat, addedAt: Date)] = [:]
        for (key, entry) in persisted.details {
            let coordTuple: (latitude: Double, longitude: Double)? = entry.details.coordinate.map { ($0.lat, $0.lon) }
            let compat = GooglePlaceDetailsCompat(
                placeID: entry.details.placeID,
                name: entry.details.name,
                address: entry.details.address,
                coordinate: coordTuple,
                phoneNumber: entry.details.phoneNumber
            )
            mappedDetails[key] = (compat, entry.addedAt)
        }

        return PlacesCacheSnapshot(details: mappedDetails, durableIDs: Set(persisted.durableIDs))
    }

    // Matches the usage from GooglePlacesService: `try await PlacesCacheStore.shared.saveSnapshot(from: cache)`
    func saveSnapshot(from cache: PlacesCache) async throws -> Bool {
        // Ask the actor for its snapshot
        let snap = await cache.snapshot()
        return try saveSnapshot(details: snap.details, durableIDs: snap.durableIDs)
    }

    // MARK: - Internal persistence

    private func saveSnapshot(details: [String: (details: GooglePlaceDetails, addedAt: Date)], durableIDs: Set<String>) throws -> Bool {
        let persistedDetails: [String: PersistedEntry] = details.reduce(into: [:]) { acc, pair in
            let (key, value) = pair
            let coord = value.details.coordinate.map { PersistedCoordinate(lat: $0.lat, lon: $0.lon) }
            let persistedDetails = PersistedPlaceDetails(
                placeID: value.details.placeID,
                name: value.details.name,
                address: value.details.address,
                coordinate: coord,
                phoneNumber: value.details.phoneNumber
            )
            acc[key] = PersistedEntry(details: persistedDetails, addedAt: value.addedAt)
        }

        let snapshot = PersistedSnapshot(version: currentVersion, details: persistedDetails, durableIDs: Array(durableIDs))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let url = try cacheFileURL()
        try ensureDirectoryExists(url.deletingLastPathComponent())

        // Atomic write
        let tmpURL = url.appendingPathExtension("tmp")
        try data.write(to: tmpURL, options: .atomic)
        // Replace any existing file
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmpURL, to: url)
        logger.info("Places cache persisted to disk at \(url.path, privacy: .private)")
        return true
    }

    // MARK: - Helpers

    private func cacheFileURL() throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return dir.appendingPathComponent(fileName)
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
