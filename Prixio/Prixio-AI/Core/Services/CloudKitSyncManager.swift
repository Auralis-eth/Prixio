import Foundation
import CloudKit
import OSLog

@available(*, deprecated, message: "Use SwiftData's CloudKit-backed ModelContainer; this custom manager is no longer used.")
/// CloudKit synchronization manager
class CloudKitSyncManager: BaseService, SyncableService, NetworkDependent {

    private(set) var lastSyncTime: Date?
    private(set) var isSyncing: Bool = false
    let requiresNetwork: Bool = true

    private let container = CKContainer.default()
    private var database: CKDatabase { container.privateCloudDatabase }

    private let signposter = OSSignposter(subsystem: "com.prixio.app", category: "cloudsync")
    private let logger = Logger(subsystem: "com.prixio.app", category: "cloudsync")

    override var dependencies: [String] { [] }

    override init(identifier: String = "CloudKitSyncManager") {
        super.init(identifier: identifier)
    }

    override func performInitialization() throws {
        Logging.shared.info("Initializing CloudKit sync")
        logger.log("CloudKit container: \(self.container.containerIdentifier ?? "default", privacy: .public)")
        // Initialize CloudKit container and subscriptions
    }

    override func performShutdown() throws {
        Logging.shared.info("Shutting down CloudKit sync")
        isSyncing = false
    }

    func syncIfNeeded() throws {
        // Implement sync logic
        Logging.shared.info("Checking if sync is needed")
    }

    func forceSync() throws {
        isSyncing = true
        defer { isSyncing = false }

        Logging.shared.info("Performing forced sync")
        lastSyncTime = Date()
    }

    func handleNetworkChange(_ isConnected: Bool) {
        Logging.shared.info("Network status changed: \(isConnected)")
    }

    // MARK: - Minimal PriceEntry Sync (Save & Read)

    /// Save a single PriceEntry to CloudKit (minimal MVP path)
    /// Updates the entry's syncStatus and syncError fields accordingly.
    func savePriceEntry(_ entry: PriceEntry) async {
        let signpostID = signposter.makeSignpostID()
        let interval = signposter.beginInterval("Save PriceEntry", id: signpostID)
        defer { signposter.endInterval("Save PriceEntry", interval) }

        logger.log("Deprecated savePriceEntry called - no operation")
        return
    }

    /// Fetch a single PriceEntry CKRecord by UUID (read path MVP)
    /// Returns the CKRecord if found; caller can map back to local model as needed.
    func fetchPriceEntryRecord(id: UUID) async throws -> CKRecord? {
        let signpostID = signposter.makeSignpostID()
        let interval = signposter.beginInterval("Fetch PriceEntry", id: signpostID)
        defer { signposter.endInterval("Fetch PriceEntry", interval) }

        logger.log("Deprecated fetchPriceEntryRecord called - returning nil")
        return nil
    }

    // MARK: - Mapping

    private func makeCKRecord(from entry: PriceEntry) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: entry.id.uuidString)
        let record = CKRecord(recordType: "PriceEntry", recordID: recordID)

        // Minimal field set for MVP sync
        // Store price as Double for simplicity; consider precision handling later
        let priceNumber = NSDecimalNumber(decimal: entry.price)
        record["price"] = priceNumber.doubleValue as CKRecordValue
        record["captureDate"] = entry.captureDate as CKRecordValue
        if let notes = entry.notes { record["notes"] = notes as CKRecordValue }
        record["createdAt"] = entry.createdAt as CKRecordValue
        record["updatedAt"] = entry.updatedAt as CKRecordValue
        if let storeID = entry.store?.id { record["storeID"] = storeID.uuidString as CKRecordValue }
        if let productID = entry.product?.id { record["productID"] = productID.uuidString as CKRecordValue }

        return record
    }
}
