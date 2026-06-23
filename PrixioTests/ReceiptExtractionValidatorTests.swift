import Foundation
import Testing
@testable import Prixio

struct ReceiptExtractionValidatorTests {
    private func line(_ price: String?, lowConfidence: Bool = false) -> LLMReceiptLine {
        LLMReceiptLine(
            rawText: "ITEM",
            itemName: "Item",
            price: price.flatMap { Decimal(string: $0) },
            quantity: 1,
            unit: .each,
            lowConfidence: lowConfidence
        )
    }

    private func result(
        subtotal: String? = nil,
        tax: String? = nil,
        discount: String? = nil,
        deposit: String? = nil,
        total: String? = nil,
        lines: [LLMReceiptLine] = [],
        issues: [LLMReceiptIssue] = []
    ) -> LLMReceiptResult {
        LLMReceiptResult(
            storeName: "Store",
            purchaseDate: nil,
            subtotal: subtotal.flatMap { Decimal(string: $0) },
            tax: tax.flatMap { Decimal(string: $0) },
            discountTotal: discount.flatMap { Decimal(string: $0) },
            depositTotal: deposit.flatMap { Decimal(string: $0) },
            total: total.flatMap { Decimal(string: $0) },
            lineItems: lines,
            issues: issues
        )
    }

    @Test
    func reconciledTotalsRaiseNoMismatch() {
        let r = result(subtotal: "10.00", tax: "1.30", total: "11.30")
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == false)
        #expect(!ReceiptExtractionValidator.issues(for: r).contains(.totalsDoNotAddUp))
    }

    @Test
    func divergentTotalsAreFlagged() {
        let r = result(subtotal: "10.00", tax: "1.30", total: "25.00")
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == true)
        #expect(ReceiptExtractionValidator.issues(for: r).contains(.totalsDoNotAddUp))
    }

    @Test
    func inBandTotalIsNotFlaggedWhenSubtotalMissing() {
        // Without an explicit printed subtotal there is no exact base — the model may fold
        // deposit/discount rows into line prices — so a total that sits within the wide gross-mismatch
        // band around the line-item sum is NOT flagged (avoids false "totals don't add up").
        let r = result(total: "7.00", lines: [line("3.00"), line("4.00")])
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == false)
        #expect(!ReceiptExtractionValidator.issues(for: r).contains(.totalsDoNotAddUp))
    }

    @Test
    func missingTotalCannotBeCheckedButIsFlagged() {
        let r = result(subtotal: "10.00", tax: "1.00")
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == nil)
        #expect(ReceiptExtractionValidator.issues(for: r).contains(.missingTotal))
    }

    @Test
    func grossOverstatedTotalIsFlaggedWhenSubtotalMissing() {
        // A misread decimal point ($40 read as $400) is an order-of-magnitude divergence from the
        // line-item sum, so it's flagged even without a printed subtotal — otherwise it would flow
        // unchallenged into spending. Line sum 40; total 400 > 40 × 2.
        let r = result(total: "400.00", lines: [line("10.00"), line("12.00"), line("18.00")])
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == true)
        #expect(ReceiptExtractionValidator.issues(for: r).contains(.totalsDoNotAddUp))
    }

    @Test
    func grossUnderstatedTotalIsFlaggedWhenSubtotalMissing() {
        // Line sum 40; total 4 < 40 × 0.5 — well below the band, so flagged.
        let r = result(total: "4.00", lines: [line("10.00"), line("12.00"), line("18.00")])
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == true)
    }

    @Test
    func depositDriftIsNotFlaggedAsGrossMismatch() {
        // A deposit/discount fold (line sum 40, total 43 incl. a deposit) stays inside the wide band
        // [20, 80], so it is NOT flagged — the band only catches order-of-magnitude errors.
        let r = result(total: "43.00", lines: [line("10.00"), line("12.00"), line("18.00")])
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == false)
        #expect(!ReceiptExtractionValidator.issues(for: r).contains(.totalsDoNotAddUp))
    }

    @Test
    func noLineSumAndNoSubtotalCannotBeChecked() {
        // No subtotal and no priced lines: nothing trustworthy to reconcile against, so don't guess.
        let r = result(total: "50.00", lines: [line(nil), line(nil)])
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == nil)
    }

    @Test
    func explicitSubtotalStillTakesPrecedenceOverLineSum() {
        // When a subtotal is present, reconciliation uses it (tight tolerance) and ignores the line
        // sum — a subtotal+tax that matches the total is clean even if line prices are folded oddly.
        let r = result(subtotal: "40.00", tax: "2.00", total: "42.00", lines: [line("5.00")])
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == false)
    }

    @Test
    func lowConfidenceLineAndModelIssuesSurface() {
        let r = result(
            subtotal: "10.00",
            tax: "0.00",
            total: "10.00",
            lines: [line("10.00", lowConfidence: true)],
            issues: [.blurOrGlare]
        )
        let issues = ReceiptExtractionValidator.issues(for: r)
        #expect(issues.contains(.lowConfidenceLines))
        #expect(issues.contains(.blurOrGlare))
        #expect(!issues.contains(.totalsDoNotAddUp))
    }

    // MARK: - Value-level reconciliation (used by the review-time recompute on edited amounts)

    @Test
    func valueLevelMismatch_usesSubtotalWithinTightTolerance() {
        // subtotal + tax - discount + deposit must match the total to the cent.
        #expect(ReceiptExtractionValidator.totalsMismatch(
            total: Decimal(string: "42.00"),
            subtotal: Decimal(string: "40.00"),
            tax: Decimal(string: "2.00"),
            discount: nil,
            deposit: nil,
            lineSum: 0
        ) == false)

        #expect(ReceiptExtractionValidator.totalsMismatch(
            total: Decimal(string: "400.00"),
            subtotal: Decimal(string: "40.00"),
            tax: Decimal(string: "2.00"),
            discount: nil,
            deposit: nil,
            lineSum: 0
        ) == true)
    }

    @Test
    func valueLevelMismatch_fallsBackToWideGrossBand_whenNoSubtotal() {
        // No subtotal: only an order-of-magnitude divergence from the line sum is flagged.
        #expect(ReceiptExtractionValidator.totalsMismatch(
            total: Decimal(string: "11.00"),
            subtotal: nil, tax: nil, discount: nil, deposit: nil,
            lineSum: Decimal(string: "10.00")!
        ) == false)

        #expect(ReceiptExtractionValidator.totalsMismatch(
            total: Decimal(string: "100.00"),
            subtotal: nil, tax: nil, discount: nil, deposit: nil,
            lineSum: Decimal(string: "10.00")!
        ) == true)
    }

    @Test
    func valueLevelMismatch_returnsNil_whenNothingToCheck() {
        #expect(ReceiptExtractionValidator.totalsMismatch(
            total: nil, subtotal: nil, tax: nil, discount: nil, deposit: nil, lineSum: 0
        ) == nil)
        #expect(ReceiptExtractionValidator.totalsMismatch(
            total: Decimal(string: "10.00"),
            subtotal: nil, tax: nil, discount: nil, deposit: nil, lineSum: 0
        ) == nil)
    }

    @Test
    func valueLevelMismatch_matchesResultLevelCheck() {
        // The result-level overload must delegate to the value-level one (same answer).
        let r = result(subtotal: "40.00", tax: "2.00", total: "42.00", lines: [line("5.00")])
        #expect(ReceiptExtractionValidator.totalsMismatch(in: r) == ReceiptExtractionValidator.totalsMismatch(
            total: Decimal(string: "42.00"),
            subtotal: Decimal(string: "40.00"),
            tax: Decimal(string: "2.00"),
            discount: nil,
            deposit: nil,
            lineSum: Decimal(string: "5.00")!
        ))
    }
}
