import Foundation

/// A persistent JSON store for caching Places snapshots.
public final class PlacesCacheStore {
    /// Shared singleton instance.
    public static let shared = PlacesCacheStore()

    private init() {}

    private let fileName = "places_cache.json"
    private let directoryName = "PlacesCache"

    private var fileURL: URL? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent(directoryName, isDirectory: true)
            return dir.appendingPathComponent(fileName)
        } catch {
            return nil
        }
    }

    /// Loads the cached Places snapshot from disk.
    ///
    /// - Returns: A tuple containing the details dictionary and durableIDs set.
    /// - Throws: Any error encountered during reading or decoding.
    public func load() async throws -> (details: [String: (details: PlaceDetails, addedAt: Date)], durableIDs: Set<String>) {
        return try await Task.detached(priority: .utility) {
            guard let url = self.fileURL, FileManager.default.fileExists(atPath: url.path) else {
                return (details: [:], durableIDs: [])
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let persisted = try decoder.decode(PersistedSnapshot.self, from: data)

            var detailsDict: [String: (details: PlaceDetails, addedAt: Date)] = [:]
            for pd in persisted.details {
                let coordinate: Coordinate?
                if let lat = pd.lat, let lon = pd.lon {
                    coordinate = Coordinate(latitude: lat, longitude: lon)
                } else {
                    coordinate = nil
                }
                let placeDetails = PlaceDetails(
                    placeID: pd.placeID,
                    name: pd.name,
                    address: pd.address,
                    coordinate: coordinate,
                    phoneNumber: pd.phoneNumber
                )
                detailsDict[pd.placeID] = (details: placeDetails, addedAt: pd.addedAt)
            }

            let durableIDsSet = Set(persisted.durableIDs)

            return (details: detailsDict, durableIDs: durableIDsSet)
        }.value
    }

    /// Saves the current Places snapshot from the provided cache to disk.
    ///
    /// - Parameter cache: The PlacesCache actor instance to snapshot.
    /// - Returns: `true` if save succeeded.
    /// - Throws: Any error encountered during encoding or writing.
    func saveSnapshot(from cache: PlacesCache) async throws -> Bool {
        let snapshot = await cache.snapshot()
        return try await Task.detached(priority: .utility) {
            guard let url = self.fileURL else {
                throw NSError(domain: "PlacesCacheStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to get file URL for saving"])
            }

            let directoryURL = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let persistedDetails: [PersistedDetails] = snapshot.details.map { key, value in
                let lat = value.details.coordinate?.lat
                let lon = value.details.coordinate?.lon
                return PersistedDetails(
                    placeID: key,
                    name: value.details.name,
                    address: value.details.address,
                    lat: lat,
                    lon: lon,
                    phoneNumber: value.details.phoneNumber,
                    addedAt: value.addedAt
                )
            }

            let persistedSnapshot = PersistedSnapshot(
                details: persistedDetails,
                durableIDs: Array(snapshot.durableIDs)
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(persistedSnapshot)
            try data.write(to: url, options: .atomic)

            return true
        }.value
    }

    // MARK: - Persisted Codable structs

    struct PersistedDetails: Codable {
        let placeID: String
        let name: String
        let address: String?
        let lat: Double?
        let lon: Double?
        let phoneNumber: String?
        let addedAt: Date
    }

    struct PersistedSnapshot: Codable {
        let details: [PersistedDetails]
        let durableIDs: [String]
    }
}

// Supporting types for PlaceDetails and Coordinate assumed to be defined elsewhere in the project, example minimal definitions:

public struct Coordinate: Codable {
    public let latitude: Double
    public let longitude: Double
}

public struct PlaceDetails: Codable {
    public let placeID: String
    public let name: String
    public let address: String?
    public let coordinate: Coordinate?
    public let phoneNumber: String?
}

// Mock of PlacesCache actor protocol method for snapshot (for context, not part of this file):
// actor PlacesCache {
//     func snapshot() -> (details: [String: (details: PlaceDetails, addedAt: Date)], durableIDs: Set<String>)
// }
