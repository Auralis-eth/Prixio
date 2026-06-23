import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct ReceiptModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test
    func persistsReceiptWithLineItemsAndTypedEnums() throws {
        let context = try makeContext()
        let receipt = ReceiptCapture(
            capturedAt: .now,
            total: Decimal(string: "23.45"),
            source: .importedPDF,
            lineItems: [
                ReceiptLineItem(lineText: "ORGANIC MILK 4.99", priceValue: Decimal(string: "4.99")),
                ReceiptLineItem(lineText: "BANANAS 1.20", needsReview: true)
            ]
        )
        context.insert(receipt)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ReceiptCapture>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.source == .importedPDF)
        #expect(fetched.first?.reviewState == .pendingReview)
        #expect(fetched.first?.lineItems.count == 2)

        let lines = try context.fetch(FetchDescriptor<ReceiptLineItem>())
        #expect(lines.count == 2)
    }

    @Test
    func deletingReceiptCascadesToLineItems() throws {
        let context = try makeContext()
        let receipt = ReceiptCapture(
            capturedAt: .now,
            lineItems: [ReceiptLineItem(lineText: "ITEM 1.00")]
        )
        context.insert(receipt)
        try context.save()

        context.delete(receipt)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReceiptLineItem>()).isEmpty)
    }

    @Test
    func lineItemRecordsLoosePromotionLink() throws {
        let context = try makeContext()
        let promotedId = UUID()
        let line = ReceiptLineItem(
            lineText: "ORGANIC MILK 4.99",
            priceValue: Decimal(string: "4.99"),
            promotedPriceEntryId: promotedId
        )
        let receipt = ReceiptCapture(capturedAt: .now, reviewState: .reviewed, lineItems: [line])
        context.insert(receipt)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ReceiptLineItem>())
        #expect(fetched.first?.promotedPriceEntryId == promotedId)
        #expect(fetched.first?.receipt?.reviewState == .reviewed)
    }
}
