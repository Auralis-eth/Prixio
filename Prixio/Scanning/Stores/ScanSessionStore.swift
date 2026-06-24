//
//  ScanSessionStore.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation
import Foundation
import Combine

@MainActor
final class ScanSessionStore: ObservableObject {
    @Published private(set) var nearbyCandidates: [StoreCandidate] = []
    @Published private(set) var lastStoreCandidate: StoreCandidate?

    /// How long a nearby-store fetch stays fresh before a re-fetch is forced.
    private static let cacheLifetime: TimeInterval = 300

    /// How far the user can move from the fetch location before the cache is considered stale, even
    /// within `cacheLifetime`. Keeps the scanner store indicator tracking movement between nearby
    /// stores instead of staying pinned to the location where candidates were first fetched.
    private static let cacheInvalidationDistance: CLLocationDistance = 250

    private var cachedAt: Date?
    private var cachedLocation: CLLocation?

    func updateCandidates(_ candidates: [StoreCandidate], near location: CLLocation? = nil) {
        nearbyCandidates = candidates
        cachedAt = .now
        cachedLocation = location
        lastStoreCandidate = candidates.first
    }

    func useLastStore(_ candidate: StoreCandidate?) {
        lastStoreCandidate = candidate
    }

    /// Returns the cached candidates only when they are still fresh **and** the user hasn't moved far
    /// from where they were fetched. A purely time-based cache left the store indicator stuck on the
    /// original location's nearest store as the user walked between stores; the distance check forces a
    /// re-fetch once they've moved beyond `cacheInvalidationDistance`.
    func cachedCandidatesIfFresh(near location: CLLocation? = nil) -> [StoreCandidate]? {
        guard let cachedAt, Date.now.timeIntervalSince(cachedAt) < Self.cacheLifetime else {
            return nil
        }
        if let location, let cachedLocation,
           location.distance(from: cachedLocation) > Self.cacheInvalidationDistance {
            return nil
        }
        return nearbyCandidates
    }
}
