import Foundation
import SwiftData

@Model
final class Product: Sendable {

    // MARK: - Core Properties

    @Attribute(.unique)
    var id: UUID

    /// Product name
    var name: String

    /// Product description
    var productDescription: String?

    /// Brand name
    var brand: String?

    /// Product category
    var category: ProductCategory

    /// Barcode/UPC if available
    @Attribute(.unique, .allowsCloudEncryption)
    var barcode: String?

    /// Product size/weight information
    var sizeInformation: String?

    /// Unit of measurement (oz, lb, kg, etc.)
    var unit: String?

    // MARK: - Relationships
    /// Recorded prices for this product
    var priceEntries: [PriceEntry] = []

    /// Product images
    @Relationship(deleteRule: .cascade, inverse: \ProductImage.product)
    var images: [ProductImage] = []

    // MARK: - Metadata

    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool = false

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        productDescription: String? = nil,
        brand: String? = nil,
        category: ProductCategory,
        barcode: String? = nil,
        sizeInformation: String? = nil,
        unit: String? = nil
    ) {
        self.id = id
        self.name = name
        self.productDescription = productDescription
        self.brand = brand
        self.category = category
        self.barcode = barcode
        self.sizeInformation = sizeInformation
        self.unit = unit
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

