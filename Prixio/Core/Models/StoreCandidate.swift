//
//  StoreCandidate.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation

struct StoreCandidate: Identifiable {
    let id: UUID
    let chainName: String?
    let locationName: String
    let address: String?
    let coordinate: CLLocationCoordinate2D?
    let distanceMeters: CLLocationDistance?
    let mapKitPlaceId: String?
}
