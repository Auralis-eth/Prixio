import Foundation
import SwiftData
import Testing
@testable import Prixio

/// Tests for `FlyerPriceRecordRepository`: saving reviewed
/// flyer deals into the dedicated market-price store, idempotently.
@MainActor
@Suite(.serialized)
struct FlyerPriceRecordRepositoryTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: FlyerPriceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func deal(
        _ bannerID: FlyerBannerID = .safeway,
        name: String = "Large Eggs",
        price: String = "3.49",
        regular: String? = "4.99"
    ) -> FlyerDeal {
        let candidate = FlyerPriceCandidate(
            productName: name,
            normalizedItemKey: ItemKeyNormalizer.normalize(name),
            brand: "Lucerne",
            price: Decimal(string: price)!,
            regularPrice: regular.flatMap { Decimal(string: $0) },
            priceKind: regular == nil ? .regular : .sale,
            packageSize: "12 ct",
            unitPrice: nil,
            saleStartDate: Date(timeIntervalSince1970: 1_782_000_000),
            saleEndDate: Date(timeIntervalSince1970: 1_782_600_000),
            memberOnly: false,
            sourceText: "Lucerne \(name)",
            confidence: 0.9
        )
        return FlyerDeal(
            banner: FlyerBannerCatalog.banner(for: bannerID)!,
            candidate: candidate,
            sourceURL: URL(string: "https://www.safeway.ca/flyer"),
            fetchedAt: Date(timeIntervalSince1970: 1_782_700_000)
        )
    }

    @Test("Saving a deal persists it with full provenance")
    func savePersistsProvenance() throws {
        let context = try makeContext()
        let repository = FlyerPriceRecordRepository(context: context)

        try repository.save(deal(), matchedItemKey: "egg", storeContext: "AB/Calgary/T2P1J9")

        let all = try repository.fetchAll()
        #expect(all.count == 1)
        let record = all[0]
        #expect(record.productName == "Large Eggs")
        #expect(record.brand == "Lucerne")
        #expect(record.priceValue == Decimal(string: "3.49"))
        #expect(record.regularPriceValue == Decimal(string: "4.99"))
        #expect(record.priceKindRaw == PriceKind.sale.rawValue)
        #expect(record.packageSize == "12 ct")
        #expect(record.saleEndDate != nil)
        #expect(record.bannerName == "Safeway")
        #expect(record.sourceURL?.absoluteString == "https://www.safeway.ca/flyer")
        #expect(record.fetchedAt != nil)
        #expect(record.storeContext == "AB/Calgary/T2P1J9")
        #expect(record.matchedItemKey == "egg")
    }

    @Test("Saving the same deal twice is idempotent (updates in place)")
    func saveIsIdempotent() throws {
        let context = try makeContext()
        let repository = FlyerPriceRecordRepository(context: context)

        try repository.save(deal(), matchedItemKey: "egg", storeContext: nil)
        try repository.save(deal(), matchedItemKey: "eggs", storeContext: nil)

        let all = try repository.fetchAll()
        #expect(all.count == 1)
        // The matched key was updated on the second save.
        #expect(all[0].matchedItemKey == "eggs")
    }

    @Test("Different banner / price / item produce distinct records")
    func distinctDealsProduceDistinctRecords() throws {
        let context = try makeContext()
        let repository = FlyerPriceRecordRepository(context: context)

        try repository.save(deal(.safeway, name: "Large Eggs", price: "3.49"), matchedItemKey: "egg", storeContext: nil)
        try repository.save(deal(.sobeys, name: "Large Eggs", price: "3.49"), matchedItemKey: "egg", storeContext: nil) // other banner
        try repository.save(deal(.safeway, name: "Large Eggs", price: "2.99"), matchedItemKey: "egg", storeContext: nil) // other price

        #expect(try repository.fetchAll().count == 3)
    }

    @Test("savedDealKeys reflects what has been saved")
    func savedDealKeysReflectsStore() throws {
        let context = try makeContext()
        let repository = FlyerPriceRecordRepository(context: context)
        try repository.save(deal(), matchedItemKey: nil, storeContext: nil)

        let keys = try repository.savedDealKeys()
        let expected = FlyerPriceRecord.dealKey(
            bannerID: FlyerBannerID.safeway.rawValue,
            normalizedItemKey: ItemKeyNormalizer.normalize("Large Eggs"),
            price: Decimal(string: "3.49")!
        )
        #expect(keys.contains(expected))
    }

    @Test("Deleting a saved record removes it")
    func deleteRemovesRecord() throws {
        let context = try makeContext()
        let repository = FlyerPriceRecordRepository(context: context)
        let record = try repository.save(deal(), matchedItemKey: nil, storeContext: nil)

        try repository.delete(record)
        #expect(try repository.fetchAll().isEmpty)
    }
}

/// Expiry rules for saved flyer prices: a record is hidden from Compare and estimates
/// once its sale window passes, and deleted by the launch sweep only after the grace
/// period, so the saved-prices manager can still show recently-expired deals.
@MainActor
@Suite(.serialized)
struct FlyerPriceRecordExpiryTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: FlyerPriceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func record(
        saleEnd: Date? = nil,
        fetchedAt: Date? = nil,
        savedAt: Date
    ) -> FlyerPriceRecord {
        FlyerPriceRecord(
            savedAt: savedAt,
            dealKey: UUID().uuidString,
            bannerID: "safeway",
            bannerName: "Safeway",
            fetchedAt: fetchedAt,
            productName: "Large Eggs",
            normalizedItemKey: "egg",
            priceValue: Decimal(string: "3.49")!,
            priceKindRaw: "sale",
            saleEndDate: saleEnd,
            confidence: 0.9,
            sourceText: "Large Eggs"
        )
    }

    @Test("The sale-end date is inclusive: active on the end date, expired the day after")
    func saleEndDateIsInclusive() {
        let record = record(saleEnd: base, savedAt: base.addingTimeInterval(-3 * day))
        #expect(!record.isExpired(asOf: base.addingTimeInterval(12 * 3_600)))
        #expect(record.isExpired(asOf: base.addingTimeInterval(day)))
    }

    @Test("Without a sale-end date, the record expires after the fallback shelf life from fetch")
    func fallbackShelfLifeFromFetchDate() {
        let record = record(fetchedAt: base, savedAt: base)
        #expect(!record.isExpired(asOf: base.addingTimeInterval(13 * day)))
        #expect(record.isExpired(asOf: base.addingTimeInterval(14 * day)))
    }

    @Test("Without a fetch date, the shelf life falls back to the save date")
    func fallbackShelfLifeFromSaveDate() {
        let record = record(savedAt: base)
        #expect(!record.isExpired(asOf: base.addingTimeInterval(13 * day)))
        #expect(record.isExpired(asOf: base.addingTimeInterval(15 * day)))
    }

    @Test("The launch sweep deletes only records expired past the grace period")
    func sweepDeletesOnlyLongExpired() throws {
        let context = try makeContext()
        let repository = FlyerPriceRecordRepository(context: context)
        let now = base

        // Expired 40 days ago — past the 30-day grace period, should be deleted.
        let longExpired = record(saleEnd: now.addingTimeInterval(-41 * day), savedAt: now.addingTimeInterval(-45 * day))
        // Expired 5 days ago — within grace, kept for the saved-prices manager.
        let recentlyExpired = record(saleEnd: now.addingTimeInterval(-6 * day), savedAt: now.addingTimeInterval(-10 * day))
        // Still active.
        let active = record(saleEnd: now.addingTimeInterval(3 * day), savedAt: now)
        [longExpired, recentlyExpired, active].forEach(context.insert)
        try context.save()

        let deleted = try repository.deleteLongExpired(asOf: now)

        #expect(deleted == 1)
        let remaining = try repository.fetchAll()
        #expect(remaining.count == 2)
        #expect(!remaining.contains { $0.id == longExpired.id })
    }

    @Test("The sweep is a no-op when nothing is long-expired")
    func sweepNoOpWhenNothingLongExpired() throws {
        let context = try makeContext()
        let repository = FlyerPriceRecordRepository(context: context)
        context.insert(record(saleEnd: base.addingTimeInterval(3 * day), savedAt: base))
        try context.save()

        #expect(try repository.deleteLongExpired(asOf: base) == 0)
        #expect(try repository.fetchAll().count == 1)
    }
}
