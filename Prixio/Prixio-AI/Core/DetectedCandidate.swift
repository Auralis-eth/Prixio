import Foundation
import CoreLocation

/// Unified candidate representation from different detection modalities
struct DetectedCandidate: Sendable, Hashable, Identifiable {
    let id: UUID
    let storeID: UUID?
    let name: String
    let location: CLLocation
    let source: Source
    var score: Double

    enum Source: String, Sendable, Codable, CaseIterable {
        case gps
        case wifi
        case places
    }

    init(
        id: UUID = UUID(),
        storeID: UUID? = nil,
        name: String,
        location: CLLocation,
        source: Source,
        score: Double = 0
    ) {
        self.id = id
        self.storeID = storeID
        self.name = name
        self.location = location
        self.source = source
        self.score = score
    }
}
