import Foundation
import CoreLocation

extension Store {
    static func from(placesResult: PlaceResult) -> Store {
        return Store(
            name: placesResult.name,
            chain: extractChain(from: placesResult.name),
            address: placesResult.address,
            city: placesResult.city,
            state: placesResult.state,
            zipCode: placesResult.zipCode,
            latitude: placesResult.location.latitude,
            longitude: placesResult.location.longitude
        )
    }

    /// Create a Store from a provider-agnostic PlaceSearchResult
    static func from(placeResult: PlaceSearchResult) -> Store {
        return Store(
            name: placeResult.name,
            chain: extractChain(from: placeResult.name),
            address: placeResult.address ?? "",
            city: "", // Could be filled from providerData if available
            state: "",
            zipCode: "",
            latitude: placeResult.location.coordinate.latitude,
            longitude: placeResult.location.coordinate.longitude
        )
    }
}
