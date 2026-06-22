//
//  ReceiptExtractionValidator.swift
//  Prixio
//
//  Deterministic, app-side defense-in-depth for receipt extraction. Re-reads the
//  model's OWN structured output to reconcile totals and surface review signals. It
//  never re-examines the photo — it catches internal inconsistencies (e.g. the parts
//  do not sum to the printed total) and forwards the model's self-reported issues.
//

import Foundation

/// Unified review signals for a receipt extraction: the model's own issues plus deterministic
/// cross-checks. Persisted on `ReceiptCapture.extractionIssuesRaw`.
enum ReceiptReviewIssue: String, Codable, CaseIterable, Sendable {
    case totalsDoNotAddUp
    case missingTotal
    case lowConfidenceLines
    case partiallyObscured
    case blurOrGlare
    case handwritten
    case notAReceipt
    case multipleReceipts
    /// A multi-page PDF was truncated to the composite page cap at import time.
    case pagesTruncated
}

enum ReceiptExtractionValidator {
    /// Allowed divergence between the computed and printed total before flagging a mismatch.
    static let totalsTolerance = Decimal(2) / Decimal(100)

    /// When no printed subtotal is available to reconcile against, the printed total is sanity-checked
    /// against the sum of line items using this deliberately wide band: the total must sit between half
    /// and double the line-item sum. The band is wide on purpose so deposit/discount folding and
    /// unpriced lines don't fire it — only an order-of-magnitude divergence (a misread decimal point,
    /// e.g. $40 read as $400) falls outside it.
    static let grossMismatchLowerFactor = Decimal(1) / Decimal(2)
    static let grossMismatchUpperFactor = Decimal(2)

    static func issues(for result: LLMReceiptResult) -> [ReceiptReviewIssue] {
        var issues = result.issues.compactMap(mapModelIssue)

        if result.lineItems.contains(where: \.lowConfidence) {
            issues.append(.lowConfidenceLines)
        }
        if result.total == nil {
            issues.append(.missingTotal)
        }
        if totalsMismatch(in: result) == true {
            issues.append(.totalsDoNotAddUp)
        }

        return Array(Set(issues))
    }

    /// Returns whether a total computed from the receipt's parts diverges from the printed total
    /// beyond `totalsTolerance`. Returns `nil` when there is not enough information to check.
    static func totalsMismatch(in result: LLMReceiptResult) -> Bool? {
        let lineSum = result.lineItems.reduce(Decimal(0)) { $0 + ($1.price ?? 0) }
        return totalsMismatch(
            total: result.total,
            subtotal: result.subtotal,
            tax: result.tax,
            discount: result.discountTotal,
            deposit: result.depositTotal,
            lineSum: lineSum
        )
    }

    /// Value-level totals reconciliation shared by the extraction-time check (`totalsMismatch(in:)`)
    /// and the review-time recompute that runs after the user edits a header amount, so a stale
    /// `totalsDoNotAddUp` flag can actually be cleared (and a newly broken total re-flagged). Returns
    /// `nil` when there is not enough information to check.
    static func totalsMismatch(
        total: Decimal?,
        subtotal: Decimal?,
        tax: Decimal?,
        discount: Decimal?,
        deposit: Decimal?,
        lineSum: Decimal
    ) -> Bool? {
        guard let total else {
            return nil
        }

        // Preferred: reconcile against an explicit printed subtotal within a tight tolerance. A precise
        // line-sum reconciliation isn't reliable here — the model may or may not fold deposit/discount
        // rows into individual line prices — so the subtotal is the trustworthy base when present.
        if let subtotal {
            let computed = subtotal
                + (tax ?? 0)
                - (discount ?? 0)
                + (deposit ?? 0)
            return abs(computed - total) > totalsTolerance
        }

        // Fallback (no subtotal): a tight check would false-fire, but a gross order-of-magnitude
        // divergence from the line-item sum is almost certainly an extraction error rather than
        // deposit/discount drift, so flag only when the total falls outside the wide gross-mismatch
        // band. With no usable line sum either, there's nothing trustworthy to check, so don't flag.
        guard lineSum > 0 else {
            return nil
        }
        return total < lineSum * grossMismatchLowerFactor || total > lineSum * grossMismatchUpperFactor
    }

    nonisolated private static func mapModelIssue(_ issue: LLMReceiptIssue) -> ReceiptReviewIssue? {
        switch issue {
        case .totalsDoNotAddUp:
            return .totalsDoNotAddUp
        case .partiallyObscured:
            return .partiallyObscured
        case .blurOrGlare:
            return .blurOrGlare
        case .handwritten:
            return .handwritten
        case .notAReceipt:
            return .notAReceipt
        case .multipleReceipts:
            return .multipleReceipts
        }
    }
}
