import CoreLocation
import Testing
@testable import Prixio

// Covers the nearby-store cache freshness logic: a fetch stays usable only while it is recent AND the
// user hasn't walked far from where it was taken. The distance check is what keeps the scanner's store
// indicator from staying pinned to the first store as the user moves between nearby ones.
@MainActor
struct ScanSessionStoreTests {
    private func candidate(_ id: String) -> StoreCandidate {
        StoreCandidate(
            id: id,
            chainName: "Walmart",
            locationName: "Walmart Beltline",
            address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 51.04, longitude: -114.07),
            distanceMeters: 120,
            mapKitPlaceId: "pid-\(id)"
        )
    }

    @Test
    func returnsNilBeforeAnyFetch() {
        let store = ScanSessionStore()
        #expect(store.cachedCandidatesIfFresh(near: CLLocation(latitude: 51.04, longitude: -114.07)) == nil)
    }

    @Test
    func returnsCacheWhenFreshAndNearTheFetchLocation() {
        let store = ScanSessionStore()
        let location = CLLocation(latitude: 51.04, longitude: -114.07)
        store.updateCandidates([candidate("a")], near: location)

        // Roughly 100m north — well inside the 250m invalidation radius.
        let nearby = CLLocation(latitude: 51.0409, longitude: -114.07)
        let cached = store.cachedCandidatesIfFresh(near: nearby)
        #expect(cached?.map(\.id) == ["a"])
    }

    @Test
    func returnsNilWhenUserHasMovedBeyondTheInvalidationDistance() {
        let store = ScanSessionStore()
        let location = CLLocation(latitude: 51.04, longitude: -114.07)
        store.updateCandidates([candidate("a")], near: location)

        // Roughly 1.1km north — past the 250m radius, so the time-fresh cache is still rejected.
        let faraway = CLLocation(latitude: 51.05, longitude: -114.07)
        #expect(store.cachedCandidatesIfFresh(near: faraway) == nil)
    }

    @Test
    func ignoresDistanceWhenQueryLocationIsUnknown() {
        let store = ScanSessionStore()
        store.updateCandidates([candidate("a")], near: CLLocation(latitude: 51.04, longitude: -114.07))

        // A nil query location can't be compared, so freshness falls back to the time window alone.
        let cached = store.cachedCandidatesIfFresh(near: nil)
        #expect(cached?.map(\.id) == ["a"])
    }

    @Test
    func ignoresDistanceWhenFetchHadNoLocation() {
        let store = ScanSessionStore()
        store.updateCandidates([candidate("a")], near: nil)

        // No origin recorded for the fetch, so the distance gate can't apply and time freshness wins.
        let cached = store.cachedCandidatesIfFresh(near: CLLocation(latitude: 51.05, longitude: -114.07))
        #expect(cached?.map(\.id) == ["a"])
    }
}
