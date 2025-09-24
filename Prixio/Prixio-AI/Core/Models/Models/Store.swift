import Foundation
import SwiftData

@Model
final class Store: Sendable {

    // MARK: - Core Properties

    @Attribute(.unique)
    var id: UUID

    /// Store name
    var name: String

    /// Store chain (if applicable)
    var chain: String?

    /// Store address
    var address: String

    /// City
    var city: String

    /// State/Province
    var state: String

    /// ZIP/Postal code
    var zipCode: String

    /// Country
    var country: String

    /// Store phone number
    var phoneNumber: String?

    /// Store website
    var website: String?

    // MARK: - Location Properties

    /// Latitude coordinate
    var latitude: Double

    /// Longitude coordinate  
    var longitude: Double

    /// Location accuracy in meters
    var locationAccuracy: Double?

    // MARK: - Relationships
    var priceEntries: [PriceEntry] = []

    /// Store images
    @Relationship(deleteRule: .cascade, inverse: \StoreImage.store)
    var images: [StoreImage] = []

    // MARK: - Metadata

    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool = false

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        chain: String? = nil,
        address: String,
        city: String,
        state: String,
        zipCode: String,
        country: String,
        phoneNumber: String? = nil,
        website: String? = nil,
        latitude: Double,
        longitude: Double,
        locationAccuracy: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.chain = chain
        self.address = address
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.country = country
        self.phoneNumber = phoneNumber
        self.website = website
        self.latitude = latitude
        self.longitude = longitude
        self.locationAccuracy = locationAccuracy
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
