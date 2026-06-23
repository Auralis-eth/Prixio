//
//  InferStoreContextToolTests.swift
//  PrixioTests
//
//  Covers the deterministic ranking/fallback logic of InferStoreContextTool.
//  All cases stay on the offline branches: a non-empty candidate pool (or an empty
//  pool with location == nil, which makes fetchNearbyStores return [] without a
//  network call) and storeNameHint == nil (a non-nil hint would hit MKLocalSearch).
//  The MapKit-backed fetch/search paths are exercised by manual / device QA.
//

import CoreLocation
import Testing
@testable import Prixio

@MainActor
struct InferStoreContextToolTests {
    private func candidate(
        id: String,
        chain: String?,
        location: String,
        distance: CLLocationDistance? = 300
    ) -> StoreCandidate {
        StoreCandidate(
            id: id,
            chainName: chain,
            locationName: location,
            address: "\(location) Address",
            coordinate: CLLocationCoordinate2D(latitude: 51.04, longitude: -114.07),
            distanceMeters: distance,
            mapKitPlaceId: "pid-\(id)"
        )
    }

    private func tool(
        pool: [StoreCandidate],
        lastStore: StoreCandidate? = nil
    ) -> InferStoreContextTool {
        InferStoreContextTool(
            service: StoreDetectionService(),
            location: nil,                 // nil location keeps fetchNearbyStores offline
            nearbyCandidates: pool,
            lastStoreCandidate: lastStore
        )
    }

    @Test(.tags(.product))
    func chainMatchFromTextIsRankedFirst() async throws {
        let pool = [
            candidate(id: "1", chain: "Walmart", location: "Walmart Beltline"),
            candidate(id: "2", chain: "Sobeys", location: "Sobeys Mission")
        ]
        let suggestions = try await tool(pool: pool).call(
            arguments: .init(storeNameHint: nil, relevantText: "Sobeys Weekly Flyer\n$1.99 /lb")
        )

        #expect(suggestions.count == 2)
        #expect(suggestions.first?.chainName == "Sobeys")
        #expect(suggestions.first?.locationName == "Sobeys Mission")
    }

    @Test(.tags(.product))
    func poolOrderIsPreservedWhenNoChainMatches() async throws {
        let pool = [
            candidate(id: "1", chain: nil, location: "Corner Grocery"),
            candidate(id: "2", chain: nil, location: "Market Fresh")
        ]
        let suggestions = try await tool(pool: pool).call(
            arguments: .init(storeNameHint: nil, relevantText: "Organic Apples\n$2.49 /lb")
        )

        #expect(suggestions.map(\.locationName) == ["Corner Grocery", "Market Fresh"])
    }

    @Test(.tags(.product))
    func fallsBackToLastStoreWhenPoolIsEmpty() async throws {
        // Empty pool + nil location → fetchNearbyStores returns [] offline, so the pool stays
        // empty and the lastStoreCandidate fallback is exercised.
        let last = candidate(id: "last", chain: "Co-op", location: "Calgary Co-op Oakridge")
        let suggestions = try await tool(pool: [], lastStore: last).call(
            arguments: .init(storeNameHint: nil, relevantText: "Bananas\n$0.79 /lb")
        )

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.locationName == "Calgary Co-op Oakridge")
    }

    @Test(.tags(.product))
    func limitsSuggestionsToFive() async throws {
        let pool = (1...7).map { candidate(id: "\($0)", chain: nil, location: "Store \($0)") }
        let suggestions = try await tool(pool: pool).call(
            arguments: .init(storeNameHint: nil, relevantText: "Milk\n$4.99")
        )

        #expect(suggestions.count == 5)
    }

    @Test(.tags(.product))
    func mapsCandidateFieldsIntoSuggestion() async throws {
        let pool = [candidate(id: "1", chain: "Safeway", location: "Safeway 17th Ave", distance: 412)]
        let suggestions = try await tool(pool: pool).call(
            arguments: .init(storeNameHint: nil, relevantText: "Bread\n$3.49")
        )

        let suggestion = try #require(suggestions.first)
        #expect(suggestion.chainName == "Safeway")
        #expect(suggestion.locationName == "Safeway 17th Ave")
        #expect(suggestion.distanceMeters == 412)
        #expect(suggestion.mapKitPlaceId == "pid-1")
    }

    // Characterization of the documented fidelity gap (Docs/OutstandingWork.md §6):
    // unlike ScanViewModel.matchStoreCandidate, this tool does NOT apply the >1500 m
    // distance rejection or receipt suppression. These tests lock in the current behavior
    // so a future parity fix is a deliberate, visible change.
    @Test(.tags(.product))
    func doesNotRejectDistantCandidates() async throws {
        let pool = [candidate(id: "1", chain: nil, location: "Faraway Grocer", distance: 50_000)]
        let suggestions = try await tool(pool: pool).call(
            arguments: .init(storeNameHint: nil, relevantText: "Eggs\n$5.49")
        )

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.locationName == "Faraway Grocer")
    }

    @Test(.tags(.product))
    func doesNotSuppressReceiptText() async throws {
        let pool = [candidate(id: "1", chain: "Walmart", location: "Walmart Beltline")]
        let suggestions = try await tool(pool: pool).call(
            arguments: .init(storeNameHint: nil, relevantText: "Subtotal 12.99\nTax 0.65\nTotal 13.64")
        )

        #expect(suggestions.count == 1)
    }
}
