import Foundation
import SwiftData

@Model
final class User: Sendable {

    @Attribute(.unique)
    var id: UUID

    /// User's display name
    var displayName: String

    /// User's email (encrypted)
    @Attribute(.unique, .allowsCloudEncryption)
    var email: String?

    /// User preferences
    @Attribute(.transformable(by: UserPreferencesTransformer.self))
    var preferences: UserPreferences?

    // MARK: - CloudKit Sync Properties

    @Attribute(.ephemeral)
    var cloudKitRecordID: String?

    @Attribute(.ephemeral)
    var syncStatus: SyncStatus = SyncStatus.pending

    @Attribute(.ephemeral)
    var lastSyncAttempt: Date?

    @Attribute(.ephemeral)
    var syncError: String?

    // MARK: - Metadata

    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool = false

    init(
        id: UUID = UUID(),
        displayName: String,
        email: String? = nil,
        preferences: UserPreferences? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.preferences = preferences
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
