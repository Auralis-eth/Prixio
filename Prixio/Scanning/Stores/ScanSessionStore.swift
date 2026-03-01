//
//  ScanSessionStore.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation
import Combine

@MainActor
final class ScanSessionStore: ObservableObject {
    @Published private(set) var nearbyCandidates: [StoreCandidate] = []
    @Published private(set) var lastStoreCandidate: StoreCandidate?

    private var cachedAt: Date?

    func updateCandidates(_ candidates: [StoreCandidate]) {
        nearbyCandidates = candidates
        cachedAt = .now
        lastStoreCandidate = candidates.first
    }

    func useLastStore(_ candidate: StoreCandidate?) {
        lastStoreCandidate = candidate
    }

    func cachedCandidatesIfFresh() -> [StoreCandidate]? {
        guard let cachedAt, Date.now.timeIntervalSince(cachedAt) < 300 else {
            return nil
        }
        return nearbyCandidates
    }
}
