import Foundation
import SwiftData

@Model
final class StoreImage: Sendable {

    @Attribute(.unique)
    var id: UUID

    @Attribute(.allowsCloudEncryption)
    var imageData: Data?

    @Attribute(.ephemeral)
    var cloudKitAssetURL: String?

    var imageType: ImageType
    var caption: String?
    var sortOrder: Int

    // MARK: - Relationships
    var store: Store?

    // MARK: - Metadata

    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool = false

    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        imageType: ImageType = ImageType.storefront,
        caption: String? = nil,
        sortOrder: Int = 0,
        store: Store? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.imageType = imageType
        self.caption = caption
        self.sortOrder = sortOrder
        self.store = store
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
