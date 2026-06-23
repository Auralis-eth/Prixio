import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct ReceiptPromotionTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self, PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeReceipt(in context: ModelContext, line: ReceiptLineItem) -> ReceiptCapture {
        let receipt = ReceiptCapture(
            capturedAt: .now,
            storeChainNameSnapshot: "Loblaws",
            lineItems: [line]
        )
        context.insert(receipt)
        return receipt
    }

    @Test
    func promotingLineCreatesLinkedPriceEntry() throws {
        let context = try makeContext()
        let line = ReceiptLineItem(
            lineText: "ORG MILK 4.99",
            itemNameRaw: "Organic Milk",
            priceValue: Decimal(string: "4.99"),
            quantityValue: 1
        )
        let receipt = makeReceipt(in: context, line: line)

        let entry = try ReceiptLinePromoter(context: context).promote(line, from: receipt)

        #expect(entry?.itemNameRaw == "Organic Milk")
        #expect(entry?.priceValue == Decimal(string: "4.99"))
        #expect(entry?.unitType == .each)
        #expect(entry?.storeChainNameSnapshot == "Loblaws")
        #expect(line.promotedPriceEntryId == entry?.id)
        #expect(try context.fetch(FetchDescriptor<PriceEntry>()).count == 1)
    }

    @Test
    func failedSaveRollsBackEntryAndPromotionLink() throws {
        // If persistence fails mid-promotion, the promoter must leave no orphan PriceEntry and must not
        // falsely stamp the line as promoted, so the user can retry cleanly.
        struct PromotionSaveError: Error {}
        let context = try makeContext()
        let line = ReceiptLineItem(
            lineText: "ORG MILK 4.99",
            itemNameRaw: "Organic Milk",
            priceValue: Decimal(string: "4.99")
        )
        let receipt = makeReceipt(in: context, line: line)
        let promoter = ReceiptLinePromoter(context: context, persist: { _ in throw PromotionSaveError() })

        #expect(throws: PromotionSaveError.self) {
            try promoter.promote(line, from: receipt)
        }

        #expect(line.promotedPriceEntryId == nil)
        #expect(try context.fetch(FetchDescriptor<PriceEntry>()).isEmpty)
    }

    @Test
    func promotingLineWithoutPriceDoesNothing() throws {
        let context = try makeContext()
        let line = ReceiptLineItem(lineText: "??", itemNameRaw: "Unknown", priceValue: nil)
        let receipt = makeReceipt(in: context, line: line)

        let entry = try ReceiptLinePromoter(context: context).promote(line, from: receipt)

        #expect(entry == nil)
        #expect(line.promotedPriceEntryId == nil)
        #expect(try context.fetch(FetchDescriptor<PriceEntry>()).isEmpty)
    }
}
