//
//  StoreLocation.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation
import SwiftData


@Model
final class StoreLocation {
    var id: UUID
    var chainId: UUID?
    var displayName: String
    var address: String?
    var city: String?
    var region: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var mapKitPlaceId: String?

    init(
        id: UUID = UUID(),
        chainId: UUID? = nil,
        displayName: String,
        address: String? = nil,
        city: String? = nil,
        region: String? = nil,
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        mapKitPlaceId: String? = nil
    ) {
        self.id = id
        self.chainId = chainId
        self.displayName = displayName
        self.address = address
        self.city = city
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.mapKitPlaceId = mapKitPlaceId
    }
}
