import Foundation

/// Protocol for services that can sync data
protocol SyncableService: AppService {
    var lastSyncTime: Date? { get }
    var isSyncing: Bool { get }

    func syncIfNeeded() throws
    func forceSync() throws
}
