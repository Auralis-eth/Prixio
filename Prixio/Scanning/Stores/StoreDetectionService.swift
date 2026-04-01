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
    private let maxNearbyQueryCount = 8
    private let interRequestDelayNanoseconds: UInt64 = 250_000_000
    private let throttleRetryNanoseconds: UInt64 = 600_000_000
    private let maxThrottleRetryCount = 1

    func fetchNearbyStores(location: CLLocation?) async -> [StoreCandidate] {
        guard let location else {
            return []
        }

        let baseQueries = ["grocery", "supermarket", "farmers market", "bakery"]
        let chainQueries = StoreCatalog.commonChains.map(\.name).filter { $0 != "Unknown" }
        let queries = deduplicatedQueries(from: baseQueries + chainQueries)
            .prefix(maxNearbyQueryCount)

        var collected: [StoreCandidate] = []
        for (index, query) in queries.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: interRequestDelayNanoseconds)
            }
            collected.append(contentsOf: await search(query: query, near: location))
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

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5_000,
                longitudinalMeters: 5_000
            )
        }

        return await search(request: request, near: location)
    }
    
    private func search(request: MKLocalSearch.Request, near location: CLLocation?) async -> [StoreCandidate] {
        await search(request: request, near: location, retryCount: 0)
    }

    private func search(
        request: MKLocalSearch.Request,
        near location: CLLocation?,
        retryCount: Int
    ) async -> [StoreCandidate] {
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.map { item in
                let mapItemLocation = item.location
                return StoreCandidate(
                    id: item.identifier?.rawValue
                        ?? (item.name ?? "Unknown Store").mapItemIdentifier(coordinate: mapItemLocation.coordinate),
                    chainName: StoreCatalog.inferredChain(from: item.name ?? ""),
                    locationName: item.name ?? "Unknown Store",
                    address: item.address?.shortAddress,
                    coordinate: mapItemLocation.coordinate,
                    distanceMeters: location.flatMap { origin in
                        mapItemLocation.distance(from: origin)
                    },
                    mapKitPlaceId: (item.name ?? "Unknown Store").mapItemIdentifier(coordinate: mapItemLocation.coordinate)
                )
            }
        } catch let error as MKError {
            switch error.code {
            case .unknown:
                return []
            case .serverFailure:
                return []
            case .loadingThrottled:
                guard retryCount < maxThrottleRetryCount else {
                    return []
                }
                try? await Task.sleep(nanoseconds: throttleRetryNanoseconds)
                return await search(request: request, near: location, retryCount: retryCount + 1)
            case .placemarkNotFound:
                return []
            case .directionsNotFound:
                return []
            case .decodingFailed:
                return []
            @unknown default:
                return []
            }
        } catch {
            return []
        }
    }

    private func deduplicatedQueries(from queries: [String]) -> [String] {
        var seen = Set<String>()
        return queries.compactMap { query in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else {
                return nil
            }
            return trimmed
        }
    }
}
