import Foundation
import SwiftData

@Model
final class ProductImage: Sendable {

    @Attribute(.unique)
    var id: UUID

    /// Image data or URL reference
    @Attribute(.allowsCloudEncryption)
    var imageData: Data?

    /// CloudKit asset reference
    @Attribute(.ephemeral)
    var cloudKitAssetURL: String?

    /// Image type/purpose
    var imageType: ImageType

    /// Image caption/description
    var caption: String?

    /// Display order
    var sortOrder: Int

    // MARK: - Relationships
    var product: Product?

    /// Price entries derived from this image via OCR
    @Relationship(inverse: \PriceEntry.sourceImage)
    var priceEntries: [PriceEntry] = []

    // MARK: - Metadata

    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool = false

    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        imageType: ImageType = .product,
        caption: String? = nil,
        sortOrder: Int = 0,
        product: Product? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.imageType = imageType
        self.caption = caption
        self.sortOrder = sortOrder
        self.product = product
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

