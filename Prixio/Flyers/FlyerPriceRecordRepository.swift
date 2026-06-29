import Foundation
import SwiftData

/// Persists user-reviewed flyer deals into the dedicated `FlyerPriceRecord` store
/// (step 8). Saves are idempotent on `dealKey`, so re-saving the same deal updates
/// the existing record rather than duplicating it. Mirrors `ShoppingListRepository`'s
/// commit/rollback discipline.
@MainActor
struct FlyerPriceRecordRepository {
    let context: ModelContext

    /// Persistence hook, overridable in tests to exercise the save-failure path.
    var persist: (ModelContext) throws -> Void = { try $0.save() }

    private func commit() throws {
        do {
            try persist(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func fetchAll() throws -> [FlyerPriceRecord] {
        try context.fetch(
            FetchDescriptor<FlyerPriceRecord>(
                sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
            )
        )
    }

    /// The set of `dealKey`s already saved, for marking review rows as saved.
    func savedDealKeys() throws -> Set<String> {
        Set(try fetchAll().map(\.dealKey))
    }

    /// Saves a matched deal. Idempotent on `dealKey`: an existing record for the same
    /// banner+item+price is updated in place. Returns the persisted record.
    @discardableResult
    func save(_ deal: FlyerDeal, matchedItemKey: String?, storeContext: String?) throws -> FlyerPriceRecord {
        let candidate = deal.candidate
        let key = FlyerPriceRecord.dealKey(
            bannerID: deal.banner.id.rawValue,
            normalizedItemKey: candidate.normalizedItemKey,
            price: candidate.price
        )

        let descriptor = FetchDescriptor<FlyerPriceRecord>(
            predicate: #Predicate<FlyerPriceRecord> { $0.dealKey == key }
        )

        let record: FlyerPriceRecord
        if let existing = try context.fetch(descriptor).first {
            record = existing
            record.savedAt = .now
            record.matchedItemKey = matchedItemKey
        } else {
            record = FlyerPriceRecord(
                dealKey: key,
                bannerID: deal.banner.id.rawValue,
                bannerName: deal.banner.name,
                productName: candidate.productName,
                normalizedItemKey: candidate.normalizedItemKey,
                priceValue: candidate.price,
                priceKindRaw: candidate.priceKind.rawValue,
                confidence: candidate.confidence,
                sourceText: candidate.sourceText,
                matchedItemKey: matchedItemKey
            )
            // Provenance + optional fields (set after init to keep the call readable).
            record.brand = candidate.brand
            record.regularPriceValue = candidate.regularPrice
            record.packageSize = candidate.packageSize
            record.saleStartDate = candidate.saleStartDate
            record.saleEndDate = candidate.saleEndDate
            record.memberOnly = candidate.memberOnly
            record.storeContext = storeContext
            record.sourceURL = deal.sourceURL
            record.fetchedAt = deal.fetchedAt
            context.insert(record)
        }

        try commit()
        return record
    }

    func delete(_ record: FlyerPriceRecord) throws {
        context.delete(record)
        try commit()
    }
}
