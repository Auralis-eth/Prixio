//
//  StoreDetectionService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation
import MapKit

@MainActor
final class StoreDetectionService {
    func fetchNearbyStores(location: CLLocation?) async -> [StoreCandidate] {
        guard let location else {
            return []
        }

        var collected: [StoreCandidate] = []
        let queries = ["grocery", "supermarket"] + StoreCatalog.commonChains.map(\.name).filter { $0 != "Unknown" }

        for query in queries {
            var request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 1_000,
                longitudinalMeters: 1_000
            )

            let response = try? await MKLocalSearch(request: request).start()
            let items = response?.mapItems ?? []
            collected.append(contentsOf: items.map { item in
                let placemarkLocation = item.placemark.location
                return StoreCandidate(
                    id: UUID(),
                    chainName: StoreCatalog.inferredChain(from: item.name ?? ""),
                    locationName: item.name ?? "Unknown Store",
                    address: item.placemark.title,
                    coordinate: placemarkLocation?.coordinate,
                    distanceMeters: placemarkLocation?.distance(from: location),
                    mapKitPlaceId: (item.name ?? "Unknown Store").mapItemIdentifier(coordinate:placemarkLocation?.coordinate)
                )
            })
        }

        let deduplicated = Dictionary(
            collected.map { candidate in
                ("\(candidate.locationName)|\(candidate.address ?? "")", candidate)
            },
            uniquingKeysWith: { current, _ in current }
        )

        return Array(deduplicated.values).sorted { lhs, rhs in
            let lhsRank = lhs.chainName == nil ? 1 : 0
            let rhsRank = rhs.chainName == nil ? 1 : 0

            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            return (lhs.distanceMeters ?? .greatestFiniteMagnitude) < (rhs.distanceMeters ?? .greatestFiniteMagnitude)
        }
    }

    func search(query: String, near location: CLLocation?) async -> [StoreCandidate] {
        guard !query.isEmpty else {
            return []
        }

        var request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5_000,
                longitudinalMeters: 5_000
            )
        }

        let response = try? await MKLocalSearch(request: request).start()
        return (response?.mapItems ?? []).map { item in
            let placemarkLocation = item.placemark.location
            return StoreCandidate(
                id: UUID(),
                chainName: StoreCatalog.inferredChain(from: item.name ?? ""),
                locationName: item.name ?? "Unknown Store",
                address: item.placemark.title,
                coordinate: placemarkLocation?.coordinate,
                distanceMeters: location.flatMap { origin in
                    placemarkLocation?.distance(from: origin)
                },
                mapKitPlaceId: (item.name ?? "Unknown Store").mapItemIdentifier(coordinate: placemarkLocation?.coordinate )
            )
        }
    }
}
