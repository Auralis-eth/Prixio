import Foundation

/// CloudKit sync status
enum SyncStatus: String, Sendable, CaseIterable, Codable {
    case pending = "pending"         // Waiting to sync
    case syncing = "syncing"         // Currently syncing
    case synced = "synced"           // Successfully synced
    case failed = "failed"           // Sync failed
    case conflict = "conflict"       // Sync conflict detected
}
