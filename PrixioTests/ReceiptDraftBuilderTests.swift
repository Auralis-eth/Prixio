import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct ReceiptDraftBuilderTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func sampleResult() -> LLMReceiptResult {
        LLMReceiptResult(
            storeName: "Costco",
            purchaseDate: "2026-01-15",
            subtotal: Decimal(string: "10.00"),
            tax: Decimal(string: "1.30"),
            discountTotal: nil,
            depositTotal: nil,
            total: Decimal(string: "11.30"),
            lineItems: [
                LLMReceiptLine(rawText: "ORG MILK 4.99", itemName: "Organic Milk", price: Decimal(string: "4.99"), quantity: 1, unit: .each, lowConfidence: false),
                LLMReceiptLine(rawText: "?? 5.01", itemName: nil, price: nil, quantity: nil, unit: nil, lowConfidence: true)
            ],
            issues: []
        )
    }

    @Test
    func applyPopulatesHeaderTotalsAndLines() throws {
        let context = try makeContext()
        let capture = ReceiptCapture(capturedAt: .now)
        context.insert(capture)

        ReceiptDraftBuilder.apply(sampleResult(), to: capture, context: context)
        try context.save()

        #expect(capture.storeChainNameSnapshot == "Costco")
        #expect(capture.purchaseDate != nil)
        #expect(capture.total == Decimal(string: "11.30"))
        #expect(capture.lineItems.count == 2)

        let milk = capture.lineItems.first { $0.itemNameRaw == "Organic Milk" }
        #expect(milk?.needsReview == false)
        let unreadable = capture.lineItems.first { $0.itemNameRaw == nil }
        #expect(unreadable?.needsReview == true)
    }

    @Test
    func applyIsIdempotentOnReextraction() throws {
        let context = try makeContext()
        let capture = ReceiptCapture(capturedAt: .now)
        context.insert(capture)

        ReceiptDraftBuilder.apply(sampleResult(), to: capture, context: context)
        ReceiptDraftBuilder.apply(sampleResult(), to: capture, context: context)
        try context.save()

        #expect(capture.lineItems.count == 2)
        #expect(try context.fetch(FetchDescriptor<ReceiptLineItem>()).count == 2)
    }

    @Test
    func usesModelReportedConfidenceWhenPresentAndFallsBackOtherwise() throws {
        let context = try makeContext()
        let capture = ReceiptCapture(capturedAt: .now)
        context.insert(capture)

        let result = LLMReceiptResult(
            storeName: "Costco",
            purchaseDate: nil,
            subtotal: nil,
            tax: nil,
            discountTotal: nil,
            depositTotal: nil,
            total: nil,
            lineItems: [
                // Explicit model confidence is carried through verbatim.
                LLMReceiptLine(rawText: "BREAD 3.00", itemName: "Bread", price: Decimal(string: "3.00"), quantity: 1, unit: .each, confidence: 0.72, lowConfidence: false),
                // No confidence reported -> fall back to the lowConfidence-derived value.
                LLMReceiptLine(rawText: "EGGS 5.00", itemName: "Eggs", price: Decimal(string: "5.00"), quantity: 1, unit: .each, lowConfidence: false)
            ],
            issues: []
        )

        ReceiptDraftBuilder.apply(result, to: capture, context: context)
        try context.save()

        let bread = capture.lineItems.first { $0.itemNameRaw == "Bread" }
        let eggs = capture.lineItems.first { $0.itemNameRaw == "Eggs" }
        #expect(bread?.confidence == 0.72)
        #expect(eggs?.confidence == 0.9)
    }

    @Test
    func parseDateHandlesISOAndRejectsGarbage() {
        #expect(ReceiptDraftBuilder.parseDate("2026-01-15") != nil)
        #expect(ReceiptDraftBuilder.parseDate("not-a-date") == nil)
        #expect(ReceiptDraftBuilder.parseDate(nil) == nil)
    }

    @Test
    func applyDropsNegativeHeaderAmountsToNil() throws {
        // `@Guide(.minimum(0))` is only a model hint; a negative total/discount/deposit would corrupt
        // totals reconciliation and the spending sums, so extraction must drop negatives to nil — the
        // same guard the manual-edit path already applies.
        let context = try makeContext()
        let capture = ReceiptCapture(capturedAt: .now)
        context.insert(capture)

        let result = LLMReceiptResult(
            storeName: "Costco",
            purchaseDate: nil,
            subtotal: Decimal(string: "-10.00"),
            tax: Decimal(string: "-1.00"),
            discountTotal: Decimal(string: "-2.00"),
            depositTotal: Decimal(string: "-0.50"),
            total: Decimal(string: "-11.30"),
            lineItems: [],
            issues: []
        )

        ReceiptDraftBuilder.apply(result, to: capture, context: context)

        #expect(capture.subtotal == nil)
        #expect(capture.tax == nil)
        #expect(capture.discountTotal == nil)
        #expect(capture.depositTotal == nil)
        #expect(capture.total == nil)
    }

    @Test
    func applySuggestsCategoryOnlyOnUntouchedPendingReceipts() throws {
        let context = try makeContext()

        // An untouched pending receipt takes the model's suggestion.
        var result = sampleResult()
        result.spendingCategory = .other
        let pending = ReceiptCapture(capturedAt: .now)
        context.insert(pending)
        ReceiptDraftBuilder.apply(result, to: pending, context: context)
        #expect(pending.category == .other)

        // A user's re-categorization is never overridden by re-extraction.
        let recategorized = ReceiptCapture(capturedAt: .now)
        recategorized.category = .subscriptions
        context.insert(recategorized)
        ReceiptDraftBuilder.apply(result, to: recategorized, context: context)
        #expect(recategorized.category == .subscriptions)

        // A reviewed receipt keeps its category even if it's still the default.
        let reviewed = ReceiptCapture(capturedAt: .now)
        reviewed.reviewState = .reviewed
        context.insert(reviewed)
        ReceiptDraftBuilder.apply(result, to: reviewed, context: context)
        #expect(reviewed.category == .groceries)

        // No suggestion leaves the default untouched.
        let noSuggestion = ReceiptCapture(capturedAt: .now)
        context.insert(noSuggestion)
        ReceiptDraftBuilder.apply(sampleResult(), to: noSuggestion, context: context)
        #expect(noSuggestion.category == .groceries)
    }

    @Test
    func applyKeepsZeroAndPositiveHeaderAmounts() throws {
        let context = try makeContext()
        let capture = ReceiptCapture(capturedAt: .now)
        context.insert(capture)

        let result = LLMReceiptResult(
            storeName: "Costco",
            purchaseDate: nil,
            subtotal: Decimal(string: "10.00"),
            tax: Decimal(0),
            discountTotal: Decimal(0),
            depositTotal: Decimal(0),
            total: Decimal(string: "10.00"),
            lineItems: [],
            issues: []
        )

        ReceiptDraftBuilder.apply(result, to: capture, context: context)

        #expect(capture.subtotal == Decimal(string: "10.00"))
        #expect(capture.tax == Decimal(0))
        #expect(capture.total == Decimal(string: "10.00"))
    }
}
