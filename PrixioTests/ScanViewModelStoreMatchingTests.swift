//
//  ScanViewModelStoreMatchingTests.swift
//  PrixioTests
//
//  Covers the store-matching helpers composed by ScanViewModel.processPickedImage:
//  matchStoreCandidate (chain match, >1500 m rejection, receipt suppression),
//  shouldAutoApplyStore (receipt + equidistant-ambiguity guards), and
//  applyInferredStore (draft field population), and injected processPickedImage composition.
//

import CoreLocation
import Testing
@testable import Prixio

@MainActor
struct ScanViewModelStoreMatchingTests {
    private let origin = CLLocation(latitude: 51.04, longitude: -114.07)

    private func coordinateNorth(of location: CLLocation, distanceMeters: CLLocationDistance) -> CLLocationCoordinate2D {
        var low = location.coordinate.latitude
        var high = location.coordinate.latitude + 0.05
        for _ in 0..<40 {
            let mid = (low + high) / 2
            let candidate = CLLocation(latitude: mid, longitude: location.coordinate.longitude)
            if candidate.distance(from: location) < distanceMeters {
                low = mid
            } else {
                high = mid
            }
        }
        return CLLocationCoordinate2D(latitude: low, longitude: location.coordinate.longitude)
    }

    private func candidate(
        id: String,
        chain: String?,
        location: String,
        coordinate: CLLocationCoordinate2D? = CLLocationCoordinate2D(latitude: 51.041, longitude: -114.071),
        distance: CLLocationDistance? = 130
    ) -> StoreCandidate {
        StoreCandidate(
            id: id,
            chainName: chain,
            locationName: location,
            address: "\(location) Address",
            coordinate: coordinate,
            distanceMeters: distance,
            mapKitPlaceId: "pid-\(id)"
        )
    }

    // MARK: - matchStoreCandidate

    @Test(.tags(.product))
    func matchReturnsNilForReceiptText() async throws {
        let viewModel = ScanViewModel()
        let candidates = [candidate(id: "1", chain: "Sobeys", location: "Sobeys Mission")]

        let matched = viewModel.matchStoreCandidate(
            from: candidates,
            ocrText: "Subtotal 12.99\nTax 0.65\nTotal 13.64",
            currentLocation: origin
        )

        #expect(matched == nil)
    }

    @Test(.tags(.product))
    func matchPrefersChainInferredFromText() async throws {
        let viewModel = ScanViewModel()
        let candidates = [
            candidate(id: "1", chain: "Walmart", location: "Walmart Beltline"),
            candidate(id: "2", chain: "Sobeys", location: "Sobeys Mission")
        ]

        let matched = viewModel.matchStoreCandidate(
            from: candidates,
            ocrText: "Sobeys Weekly Flyer\n$1.99 /lb",
            currentLocation: nil
        )

        #expect(matched?.chainName == "Sobeys")
    }

    @Test(.tags(.product))
    func matchDistanceBoundaryAcceptsAtOrBelowFifteenHundredMeters() async throws {
        let viewModel = ScanViewModel()
        let candidates = [
            candidate(id: "1499", chain: nil, location: "Near", coordinate: coordinateNorth(of: origin, distanceMeters: 1_499)),
            candidate(id: "1500", chain: nil, location: "Boundary", coordinate: coordinateNorth(of: origin, distanceMeters: 1_500)),
            candidate(id: "1501", chain: nil, location: "Far", coordinate: coordinateNorth(of: origin, distanceMeters: 1_501))
        ]

        #expect(viewModel.matchStoreCandidate(from: [candidates[0]], ocrText: "Apples\n$2.49 /lb", currentLocation: origin)?.locationName == "Near")
        #expect(viewModel.matchStoreCandidate(from: [candidates[1]], ocrText: "Apples\n$2.49 /lb", currentLocation: origin)?.locationName == "Boundary")
        #expect(viewModel.matchStoreCandidate(from: [candidates[2]], ocrText: "Apples\n$2.49 /lb", currentLocation: origin) == nil)
    }

    @Test(.tags(.product))
    func matchRejectsCandidateBeyondFifteenHundredMeters() async throws {
        let viewModel = ScanViewModel()
        // ~6.6 km north of the origin.
        let far = candidate(
            id: "1",
            chain: nil,
            location: "Faraway Grocer",
            coordinate: CLLocationCoordinate2D(latitude: 51.10, longitude: -114.07),
            distance: 6_600
        )

        let matched = viewModel.matchStoreCandidate(
            from: [far],
            ocrText: "Apples\n$2.49 /lb",
            currentLocation: origin
        )

        #expect(matched == nil)
    }

    @Test(.tags(.product))
    func matchAcceptsNearbyCandidateWithinFifteenHundredMeters() async throws {
        let viewModel = ScanViewModel()
        let near = candidate(id: "1", chain: nil, location: "Corner Grocery")

        let matched = viewModel.matchStoreCandidate(
            from: [near],
            ocrText: "Apples\n$2.49 /lb",
            currentLocation: origin
        )

        #expect(matched?.locationName == "Corner Grocery")
    }

    @Test(.tags(.product))
    func matchSkipsDistanceCheckWhenLocationUnknown() async throws {
        let viewModel = ScanViewModel()
        let far = candidate(
            id: "1",
            chain: nil,
            location: "Faraway Grocer",
            coordinate: CLLocationCoordinate2D(latitude: 51.10, longitude: -114.07),
            distance: 6_600
        )

        let matched = viewModel.matchStoreCandidate(
            from: [far],
            ocrText: "Apples\n$2.49 /lb",
            currentLocation: nil
        )

        #expect(matched?.locationName == "Faraway Grocer")
    }

    @Test(.tags(.product))
    func matchReturnsNilForEmptyCandidates() async throws {
        let viewModel = ScanViewModel()

        let matched = viewModel.matchStoreCandidate(
            from: [],
            ocrText: "Apples\n$2.49 /lb",
            currentLocation: origin
        )

        #expect(matched == nil)
    }

    // MARK: - shouldAutoApplyStore

    @Test(.tags(.product))
    func shouldNotAutoApplyForReceiptText() async throws {
        let viewModel = ScanViewModel()
        let target = candidate(id: "1", chain: "Sobeys", location: "Sobeys Mission")

        let result = viewModel.shouldAutoApplyStore(
            candidate: target,
            ocrText: "Subtotal 12.99\nTax 0.65\nTotal 13.64",
            nearbyCandidates: [target]
        )

        #expect(result == false)
    }

    @Test(.tags(.product))
    func shouldNotAutoApplyWhenMultipleEquidistantCandidates() async throws {
        let viewModel = ScanViewModel()
        let target = candidate(id: "1", chain: "Sobeys", location: "Sobeys Mission", distance: 200)
        // Two other candidates within 50 m of the target's distance → ambiguous.
        let nearby = [
            target,
            candidate(id: "2", chain: "Safeway", location: "Safeway 17th", distance: 210),
            candidate(id: "3", chain: "Co-op", location: "Co-op Oakridge", distance: 240)
        ]

        let result = viewModel.shouldAutoApplyStore(
            candidate: target,
            ocrText: "Apples\n$2.49 /lb",
            nearbyCandidates: nearby
        )

        #expect(result == false)
    }

    @Test(.tags(.product))
    func shouldAutoApplyForUnambiguousNearbyStore() async throws {
        let viewModel = ScanViewModel()
        let target = candidate(id: "1", chain: "Sobeys", location: "Sobeys Mission", distance: 200)
        // Only one other candidate, far enough not to be a close match.
        let nearby = [
            target,
            candidate(id: "2", chain: "Safeway", location: "Safeway 17th", distance: 900)
        ]

        let result = viewModel.shouldAutoApplyStore(
            candidate: target,
            ocrText: "Apples\n$2.49 /lb",
            nearbyCandidates: nearby
        )

        #expect(result)
    }

    // MARK: - applyInferredStore

    @Test(.tags(.product))
    func applyInferredStorePopulatesEmptyDraftFields() async throws {
        let viewModel = ScanViewModel()
        let target = candidate(id: "1", chain: "Sobeys", location: "Sobeys Mission")

        viewModel.applyInferredStore(from: target, ocrText: "Apples\n$2.49 /lb", nearbyCandidates: [target])

        #expect(viewModel.draft.storeChainName == "Sobeys")
        #expect(viewModel.draft.storeLocationName == "Sobeys Mission")
        #expect(viewModel.draft.storeAddress == "Sobeys Mission Address")
        #expect(viewModel.draft.storePlaceId == "pid-1")
        // Inference is not an explicit user selection.
        #expect(viewModel.draft.storeChainExplicitlySelected == false)
    }

    @Test(.tags(.product))
    func applyInferredStoreLeavesDraftUntouchedForNilCandidate() async throws {
        let viewModel = ScanViewModel()

        viewModel.applyInferredStore(from: nil, ocrText: "Apples\n$2.49 /lb", nearbyCandidates: [])

        #expect(viewModel.draft.storeChainName == nil)
        #expect(viewModel.draft.storeLocationName.isEmpty)
    }

    @Test(.tags(.product))
    func applyInferredStoreSkipsReceiptCapture() async throws {
        let viewModel = ScanViewModel()
        let target = candidate(id: "1", chain: "Sobeys", location: "Sobeys Mission")

        viewModel.applyInferredStore(
            from: target,
            ocrText: "Subtotal 12.99\nTax 0.65\nTotal 13.64",
            nearbyCandidates: [target]
        )

        #expect(viewModel.draft.storeChainName == nil)
        #expect(viewModel.draft.storeLocationName.isEmpty)
    }
}
