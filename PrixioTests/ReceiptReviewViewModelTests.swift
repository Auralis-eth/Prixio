import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct ReceiptReviewViewModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self, PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeViewModel(
        context: ModelContext,
        lines: [ReceiptLineItem],
        total: Decimal? = Decimal(string: "11.47")
    ) -> ReceiptReviewViewModel {
        let receipt = ReceiptCapture(
            capturedAt: .now,
            storeChainNameSnapshot: "Sobeys",
            total: total,
            lineItems: lines
        )
        context.insert(receipt)
        return ReceiptReviewViewModel(capture: receipt, context: context)
    }

    @Test
    func lineItemsAreSortedByCreationDate() throws {
        let context = try makeContext()
        let early = ReceiptLineItem(
            createdAt: Date(timeIntervalSince1970: 100),
            lineText: "MILK",
            itemNameRaw: "Milk",
            priceValue: Decimal(string: "4.99")
        )
        let late = ReceiptLineItem(
            createdAt: Date(timeIntervalSince1970: 300),
            lineText: "EGGS",
            itemNameRaw: "Eggs",
            priceValue: Decimal(string: "3.49")
        )
        let middle = ReceiptLineItem(
            createdAt: Date(timeIntervalSince1970: 200),
            lineText: "BREAD",
            itemNameRaw: "Bread",
            priceValue: Decimal(string: "2.99")
        )
        let viewModel = makeViewModel(context: context, lines: [late, early, middle])

        #expect(viewModel.lineItems.map(\.lineText) == ["MILK", "BREAD", "EGGS"])
    }

    @Test
    func canPromoteRequiresNameAndPrice() throws {
        let context = try makeContext()
        let good = ReceiptLineItem(lineText: "MILK", itemNameRaw: "Milk", priceValue: Decimal(string: "4.99"))
        let noPrice = ReceiptLineItem(lineText: "X", itemNameRaw: "Mystery", priceValue: nil)
        let viewModel = makeViewModel(context: context, lines: [good, noPrice])

        #expect(viewModel.canPromote(good))
        #expect(!viewModel.canPromote(noPrice))
        #expect(viewModel.promotableCount == 1)
    }

    @Test
    func canPromoteRejectsWhitespaceNameNonPositivePriceAndAlreadyPromotedLine() throws {
        let context = try makeContext()
        let whitespaceName = ReceiptLineItem(
            lineText: "UNKNOWN 1.99",
            itemNameRaw: "   ",
            priceValue: Decimal(string: "1.99")
        )
        let zeroPrice = ReceiptLineItem(
            lineText: "COUPON 0.00",
            itemNameRaw: "Coupon",
            priceValue: Decimal(0)
        )
        let negativePrice = ReceiptLineItem(
            lineText: "DISCOUNT -1.00",
            itemNameRaw: "Discount",
            priceValue: Decimal(string: "-1.00")
        )
        let alreadyPromoted = ReceiptLineItem(
            lineText: "MILK 4.99",
            itemNameRaw: "Milk",
            priceValue: Decimal(string: "4.99"),
            promotedPriceEntryId: UUID()
        )
        let viewModel = makeViewModel(
            context: context,
            lines: [whitespaceName, zeroPrice, negativePrice, alreadyPromoted]
        )

        #expect(!viewModel.canPromote(whitespaceName))
        #expect(!viewModel.canPromote(zeroPrice))
        #expect(!viewModel.canPromote(negativePrice))
        #expect(!viewModel.canPromote(alreadyPromoted))
        #expect(viewModel.promotableCount == 0)
    }

    @Test
    func promoteMarksLinePromotedAndReducesPromotableCount() throws {
        let context = try makeContext()
        let line = ReceiptLineItem(lineText: "MILK", itemNameRaw: "Milk", priceValue: Decimal(string: "4.99"))
        let viewModel = makeViewModel(context: context, lines: [line])

        viewModel.promote(line)

        #expect(viewModel.isPromoted(line))
        #expect(!viewModel.canPromote(line))
        #expect(viewModel.promotableCount == 0)
        #expect(try context.fetch(FetchDescriptor<PriceEntry>()).count == 1)
    }

    @Test
    func promoteDoesNothingForInvalidLine() throws {
        let context = try makeContext()
        let line = ReceiptLineItem(lineText: "VOID", itemNameRaw: "", priceValue: nil)
        let viewModel = makeViewModel(context: context, lines: [line])

        viewModel.promote(line)

        // An invalid line is a silent no-op: nothing is promoted, no PriceEntry is written, and the
        // `canPromote` guard returns before the do/catch so no error is surfaced to the user (invalid
        // lines are ignored by design, not reported as failures).
        #expect(line.promotedPriceEntryId == nil)
        #expect(!viewModel.isPromoted(line))
        #expect(viewModel.promotionError == nil)
        #expect(try context.fetch(FetchDescriptor<PriceEntry>()).isEmpty)
    }

    @Test
    func markReviewedUpdatesCaptureState() throws {
        let context = try makeContext()
        let viewModel = makeViewModel(context: context, lines: [], total: Decimal(string: "11.47"))

        #expect(viewModel.markReviewed())

        #expect(viewModel.capture.reviewState == .reviewed)
        #expect(viewModel.reviewBlockedMessage == nil)
    }

    @Test
    func markReviewedIsRefusedWhenTotalIsMissing() throws {
        // A receipt whose total extraction failed (and the user didn't fill one in) must not be marked
        // reviewed — otherwise it would silently count as $0 toward spending.
        let context = try makeContext()
        let viewModel = makeViewModel(context: context, lines: [], total: nil)

        #expect(viewModel.markReviewed() == false)

        #expect(viewModel.capture.reviewState == .pendingReview)
        #expect(viewModel.reviewBlockedMessage != nil)
        #expect(viewModel.hasUsableTotal == false)
    }

    @Test
    func markReviewedIsRefusedWhenTotalIsZero() throws {
        let context = try makeContext()
        let viewModel = makeViewModel(context: context, lines: [], total: Decimal(0))

        #expect(viewModel.markReviewed() == false)
        #expect(viewModel.capture.reviewState == .pendingReview)
    }

    @Test
    func discardDeletesCaptureAndLineItems() throws {
        let context = try makeContext()
        let line = ReceiptLineItem(lineText: "MILK", itemNameRaw: "Milk", priceValue: Decimal(string: "4.99"))
        let viewModel = makeViewModel(context: context, lines: [line])
        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).count == 1)

        viewModel.discard()

        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReceiptLineItem>()).isEmpty)
    }

    private struct SaveFailure: Error {}

    @Test
    func markReviewedRollsBackStateAndSurfacesErrorWhenSaveFails() throws {
        // A SwiftData save failure must not leave the receipt looking reviewed: the state is rolled
        // back, Done is refused (false), and the failure is surfaced rather than swallowed.
        let context = try makeContext()
        let viewModel = makeViewModel(context: context, lines: [], total: Decimal(string: "11.47"))
        viewModel.saveHandler = { _ in throw SaveFailure() }

        #expect(viewModel.markReviewed() == false)
        #expect(viewModel.capture.reviewState == .pendingReview)
        #expect(viewModel.saveError != nil)
    }

    @Test
    func saveDraftReportsFailureWhenSaveFails() throws {
        let context = try makeContext()
        let viewModel = makeViewModel(context: context, lines: [], total: Decimal(string: "11.47"))
        viewModel.saveHandler = { _ in throw SaveFailure() }

        #expect(viewModel.save() == false)
        #expect(viewModel.saveError != nil)
    }

    @Test
    func discardReportsFailureWhenSaveFails() throws {
        let context = try makeContext()
        let viewModel = makeViewModel(context: context, lines: [], total: Decimal(string: "11.47"))
        viewModel.saveHandler = { _ in throw SaveFailure() }

        #expect(viewModel.discard() == false)
        #expect(viewModel.saveError != nil)
    }

    @Test
    func discardFailureRollsBackSoCaptureSurvives() throws {
        // `discard()` deletes the capture before saving. If the save fails, the delete is pending in the
        // live context — without a rollback the capture would be lost even though the UI reports failure.
        // The rollback must restore it (and its lines) so the user can retry from the still-present sheet.
        let context = try makeContext()
        let line = ReceiptLineItem(lineText: "MILK", itemNameRaw: "Milk", priceValue: Decimal(string: "4.99"))
        let viewModel = makeViewModel(context: context, lines: [line])
        try context.save() // persist a baseline so rollback has a saved state to restore to
        viewModel.saveHandler = { _ in throw SaveFailure() }

        #expect(viewModel.discard() == false)
        #expect(viewModel.saveError != nil)
        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ReceiptLineItem>()).count == 1)
    }

    @Test
    func markReviewedSucceedsAndPersistsWithValidTotal() throws {
        let context = try makeContext()
        let viewModel = makeViewModel(context: context, lines: [], total: Decimal(string: "11.47"))

        #expect(viewModel.markReviewed())
        #expect(viewModel.capture.reviewState == .reviewed)
        #expect(viewModel.saveError == nil)
        // The reviewed state is actually on disk.
        let stored = try #require(try context.fetch(FetchDescriptor<ReceiptCapture>()).first)
        #expect(stored.reviewState == .reviewed)
    }

    // MARK: - Totals-issue recompute on edit (regression: stale, uncleanable flags)

    private func makeReviewable(
        context: ModelContext,
        subtotal: Decimal? = nil,
        total: Decimal? = nil,
        extractionIssuesRaw: String? = nil,
        lines: [ReceiptLineItem] = []
    ) -> ReceiptReviewViewModel {
        let receipt = ReceiptCapture(
            capturedAt: .now,
            storeChainNameSnapshot: "Sobeys",
            subtotal: subtotal,
            total: total,
            extractionIssuesRaw: extractionIssuesRaw,
            lineItems: lines
        )
        context.insert(receipt)
        return ReceiptReviewViewModel(capture: receipt, context: context)
    }

    @Test
    func recomputeReviewIssues_clearsStaleTotalsMismatch_whenUserFixesTheTotal() throws {
        // A receipt extracted with a misread total carries `.totalsDoNotAddUp`. Once the user corrects
        // the total so it reconciles against the subtotal, re-reconciling must clear the flag — the
        // previous behavior left it stuck forever because the validator only ran at extraction time.
        let context = try makeContext()
        let viewModel = makeReviewable(
            context: context,
            subtotal: Decimal(string: "10.00"),
            total: Decimal(string: "400.00"),
            extractionIssuesRaw: ReceiptReviewIssue.totalsDoNotAddUp.rawValue
        )
        #expect(viewModel.hasUnresolvedTotalsMismatch)

        viewModel.capture.total = Decimal(string: "10.00")
        viewModel.recomputeReviewIssues()

        #expect(!viewModel.capture.reviewIssues.contains(.totalsDoNotAddUp))
        #expect(!viewModel.hasUnresolvedTotalsMismatch)
    }

    @Test
    func recomputeReviewIssues_flagsMismatch_whenUserBreaksAGoodTotal() throws {
        // The recompute must work in both directions: editing a previously-good total into garbage
        // re-raises the warning instead of silently passing.
        let context = try makeContext()
        let viewModel = makeReviewable(
            context: context,
            subtotal: Decimal(string: "10.00"),
            total: Decimal(string: "10.00")
        )
        #expect(!viewModel.hasUnresolvedTotalsMismatch)

        viewModel.capture.total = Decimal(string: "999.00")
        viewModel.recomputeReviewIssues()

        #expect(viewModel.capture.reviewIssues.contains(.totalsDoNotAddUp))
    }

    @Test
    func recomputeReviewIssues_clearsMissingTotal_whenUserEntersOne() throws {
        let context = try makeContext()
        let viewModel = makeReviewable(
            context: context,
            total: nil,
            extractionIssuesRaw: ReceiptReviewIssue.missingTotal.rawValue
        )
        #expect(viewModel.capture.reviewIssues.contains(.missingTotal))

        viewModel.capture.total = Decimal(string: "12.00")
        viewModel.recomputeReviewIssues()

        #expect(!viewModel.capture.reviewIssues.contains(.missingTotal))
    }

    @Test
    func recomputeReviewIssues_preservesIssuesItCannotRederive() throws {
        // Low-confidence/blur/handwritten/pagesTruncated flags can't be recomputed from edited amounts,
        // so re-reconciling totals must leave them intact while only touching the totals-derived ones.
        let context = try makeContext()
        let viewModel = makeReviewable(
            context: context,
            total: nil,
            extractionIssuesRaw: [
                ReceiptReviewIssue.lowConfidenceLines.rawValue,
                ReceiptReviewIssue.blurOrGlare.rawValue,
                ReceiptReviewIssue.missingTotal.rawValue
            ].joined(separator: ",")
        )

        viewModel.capture.total = Decimal(string: "12.00")
        viewModel.recomputeReviewIssues()

        let issues = Set(viewModel.capture.reviewIssues)
        #expect(issues.contains(.lowConfidenceLines))
        #expect(issues.contains(.blurOrGlare))
        #expect(!issues.contains(.missingTotal))
    }

    @Test
    func markReviewedIsRefusedWhileTotalsMismatchUnresolved() throws {
        // The Done gate must consult the totals-mismatch flag, not just `total > 0`: an order-of-
        // magnitude misread total ($400 on a $10 basket) would otherwise flow straight into spending.
        let context = try makeContext()
        let viewModel = makeReviewable(
            context: context,
            subtotal: Decimal(string: "10.00"),
            total: Decimal(string: "400.00"),
            extractionIssuesRaw: ReceiptReviewIssue.totalsDoNotAddUp.rawValue
        )

        #expect(viewModel.markReviewed() == false)
        #expect(viewModel.capture.reviewState == .pendingReview)
        #expect(viewModel.reviewBlockedMessage != nil)
    }

    @Test
    func markReviewedSucceeds_afterMismatchResolvedViaRecompute() throws {
        let context = try makeContext()
        let viewModel = makeReviewable(
            context: context,
            subtotal: Decimal(string: "10.00"),
            total: Decimal(string: "400.00"),
            extractionIssuesRaw: ReceiptReviewIssue.totalsDoNotAddUp.rawValue
        )

        viewModel.capture.total = Decimal(string: "10.00")
        viewModel.recomputeReviewIssues()

        #expect(viewModel.markReviewed())
        #expect(viewModel.capture.reviewState == .reviewed)
    }

    @Test
    func markReviewedRecomputes_soFixingAMisreadLinePriceUnsticksTheReceipt() throws {
        // Regression for the un-finishable-receipt dead-end. With no printed subtotal, the totals check
        // reconciles against the LINE-ITEM sum. A line misread an order of magnitude high ($400 for a
        // $38 item) flags `.totalsDoNotAddUp`. The per-line price editor does NOT route through
        // `onAmountEdited`, so before the fix, correcting the line left the flag stale and Done stayed
        // blocked forever. `markReviewed()` must now recompute from current state — without any explicit
        // recompute call or header edit — and succeed once the line reconciles.
        let context = try makeContext()
        let line = ReceiptLineItem(lineText: "MILK 400.00", itemNameRaw: "Milk", priceValue: Decimal(400))
        let viewModel = makeReviewable(
            context: context,
            subtotal: nil,
            total: Decimal(40),
            extractionIssuesRaw: ReceiptReviewIssue.totalsDoNotAddUp.rawValue,
            lines: [line]
        )
        #expect(viewModel.markReviewed() == false)
        #expect(viewModel.capture.reviewState == .pendingReview)

        // Simulate the user fixing only the line price (no header field touched, no recompute call).
        line.priceValue = Decimal(38)

        #expect(viewModel.markReviewed())
        #expect(viewModel.capture.reviewState == .reviewed)
        #expect(!viewModel.capture.reviewIssues.contains(.totalsDoNotAddUp))
    }

    @Test
    func markReviewedRecomputes_andRefusesWhenALineEditBreaksReconciliation() throws {
        // The internal recompute must also catch a NEW mismatch introduced after extraction: a clean
        // receipt whose line price is edited into an order-of-magnitude error must be re-flagged and
        // refused rather than flowing into spending.
        let context = try makeContext()
        let line = ReceiptLineItem(lineText: "MILK 40.00", itemNameRaw: "Milk", priceValue: Decimal(40))
        let viewModel = makeReviewable(
            context: context,
            subtotal: nil,
            total: Decimal(40),
            lines: [line]
        )
        #expect(viewModel.markReviewed())

        // Reopen-style edit that breaks the reconciliation.
        viewModel.capture.reviewState = .pendingReview
        line.priceValue = Decimal(400)

        #expect(viewModel.markReviewed() == false)
        #expect(viewModel.capture.reviewState == .pendingReview)
        #expect(viewModel.capture.reviewIssues.contains(.totalsDoNotAddUp))
    }
}

/// Regression coverage for the receipt-line price field: the editable string must round-trip back
/// through the parser, including for values ≥ 1000 where a grouping separator previously corrupted
/// `Decimal(string:)` and silently wiped the price.
struct CurrencyFormatterEditableRoundTripTests {
    @Test(arguments: ["0.50", "4.99", "12.00", "999.99", "1000.00", "1234.56", "1000000.00"])
    func editableStringRoundTripsThroughParser(_ raw: String) throws {
        let value = try #require(Decimal(string: raw))
        let editable = CurrencyFormatter.shared.editableString(value)
        let parsed = try #require(CurrencyFormatter.shared.price(from: editable))
        #expect(parsed == value)
    }

    @Test
    func parserAcceptsCommaDecimalAndRejectsEmpty() {
        #expect(CurrencyFormatter.shared.price(from: "12,50") == Decimal(string: "12.50"))
        #expect(CurrencyFormatter.shared.price(from: "   ") == nil)
        #expect(CurrencyFormatter.shared.price(from: "") == nil)
    }
}
