import Foundation
import SwiftData
import Testing
@testable import Prixio

/// Tests for `FlyerPriceRecordRepository` (flyer-processing step 8): saving reviewed
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
