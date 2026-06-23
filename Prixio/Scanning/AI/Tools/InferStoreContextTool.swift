//
//  InferStoreContextTool.swift
//  Prixio
//
//  A model-callable adapter: the AI supplies a store-name hint and the scan's
//  text, and MapKit + the local chain catalog resolve real candidates, mirroring
//  ScanViewModel.matchStoreCandidate (prefer chain match, fall back to the last
//  store). Registered on the Capture flow's session (ScanViewModel.captureTools)
//  and shared with the Compare/Planner agents. Known fidelity gap vs.
//  matchStoreCandidate tracked in Docs/OutstandingWork.md §6.
//

import CoreLocation
import FoundationModels

struct InferStoreContextTool: Tool {
    let name = "inferStoreContext"
    let description = "Suggest nearby store chains/locations for the current scan."

    let service: any StoreLookupProviding
    let location: CLLocation?
    let nearbyCandidates: [StoreCandidate]
    let lastStoreCandidate: StoreCandidate?

    @Generable
    struct Arguments {
        @Guide(description: "A store name read from the photo, if any.")
        let storeNameHint: String?
        @Guide(description: "Pricing-relevant text transcribed from the photo.")
        let relevantText: String
    }

    @Generable
    struct StoreSuggestion {
        let locationName: String
        let chainName: String?
        let distanceMeters: Double?
        let mapKitPlaceId: String?
    }

    func call(arguments: Arguments) async throws -> [StoreSuggestion] {
        let candidates = await resolveCandidates(arguments: arguments)
        return candidates.prefix(5).map { candidate in
            StoreSuggestion(
                locationName: candidate.locationName,
                chainName: candidate.chainName,
                distanceMeters: candidate.distanceMeters,
                mapKitPlaceId: candidate.mapKitPlaceId
            )
        }
    }

    @MainActor
    private func resolveCandidates(arguments: Arguments) async -> [StoreCandidate] {
        var pool = nearbyCandidates
        if pool.isEmpty {
            pool = await service.fetchNearbyStores(location: location)
        }
        if let hint = arguments.storeNameHint, !hint.isEmpty {
            let searched = await service.search(query: hint, near: location)
            if !searched.isEmpty {
                pool = searched
            }
        }

        let inferredChain = StoreCatalog.inferredChain(from: arguments.relevantText)
        if let matched = pool.first(where: { $0.chainName == inferredChain }) {
            return [matched] + pool.filter { $0.id != matched.id }
        }
        if let last = lastStoreCandidate, pool.isEmpty {
            return [last]
        }
        return pool
    }
}
