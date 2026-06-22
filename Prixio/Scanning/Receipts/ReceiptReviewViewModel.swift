//
//  ReceiptReviewViewModel.swift
//  Prixio
//
//  Drives the receipt review surface: presents extracted store/date/totals and line
//  items, lets the user correct lines, promote trustworthy ones into price history, and
//  mark the receipt reviewed.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class ReceiptReviewViewModel: ObservableObject {
    let capture: ReceiptCapture
    private let context: ModelContext

    /// Set when a line fails to persist to price history; surfaced as an alert and cleared on dismiss.
    @Published var promotionError: String?

    /// Set when the user tries to finish a receipt that has no usable total; surfaced as an alert so
    /// the receipt can't be silently marked reviewed and counted as $0 spend.
    @Published var reviewBlockedMessage: String?

    /// Set when persisting the receipt fails; surfaced as an alert so edits (or a "reviewed" state)
    /// aren't silently lost when the underlying SwiftData save throws.
    @Published var saveError: String?

    /// Seam for persisting the context. Defaults to a real `ModelContext.save()`; tests inject a
    /// throwing variant to exercise the save-failure handling. Mirrors `ReceiptLinePromoter.persist`.
    var saveHandler: (ModelContext) throws -> Void = { try $0.save() }

    init(capture: ReceiptCapture, context: ModelContext) {
        self.capture = capture
        self.context = context
    }

    /// Line items in stable, printed order.
    var lineItems: [ReceiptLineItem] {
        capture.lineItems.sorted { $0.createdAt < $1.createdAt }
    }

    var reviewIssues: [ReceiptReviewIssue] {
        capture.reviewIssues
    }

    var promotableCount: Int {
        lineItems.filter { canPromote($0) }.count
    }

    func isPromoted(_ line: ReceiptLineItem) -> Bool {
        line.promotedPriceEntryId != nil
    }

    func canPromote(_ line: ReceiptLineItem) -> Bool {
        guard !isPromoted(line) else {
            return false
        }
        let hasName = !(line.itemNameRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPrice = (line.priceValue ?? 0) > 0
        return hasName && hasPrice
    }

    func promote(_ line: ReceiptLineItem) {
        guard canPromote(line) else {
            return
        }
        do {
            _ = try ReceiptLinePromoter(context: context).promote(line, from: capture)
        } catch {
            // The promoter rolls back the line's link on failure, so the row stays un-promoted;
            // tell the user instead of showing a false "Saved" state.
            promotionError = "Could not save this item to price history. Please try again."
        }
        objectWillChange.send()
    }

    /// A receipt only contributes to spending if it carries a positive total. Without one, marking it
    /// reviewed would silently count it as $0 — so this gates the Done action.
    var hasUsableTotal: Bool {
        (capture.total ?? 0) > 0
    }

    /// Whether this receipt will actually reach the spending totals. Spending math is single-currency
    /// (`SpendingInsightEngine.reportingCurrency`); a receipt in any other currency is excluded by
    /// `spendingReceipts`. Extraction sets `currencyCode` from the model's reading, which can misread a
    /// CAD receipt as e.g. USD — so the review surface exposes the currency and this notice, letting the
    /// user see and fix it instead of the receipt silently counting as $0 spend.
    var countsTowardSpending: Bool {
        capture.currencyCode == SpendingInsightEngine.reportingCurrency
    }

    /// A user-facing explanation shown when the receipt's currency excludes it from spending, or `nil`
    /// when it counts normally.
    var foreignCurrencyNotice: String? {
        guard !countsTowardSpending else { return nil }
        return "This receipt is in \(capture.currencyCode). Spending is tracked in \(SpendingInsightEngine.reportingCurrency), so it won't be added to your totals. Change the currency above if that's wrong."
    }

    /// Normalizes a parsed header amount (total/subtotal/tax/discount/deposit). These are never negative;
    /// a negative would corrupt totals reconciliation and the spending sums, so a negative parse is
    /// dropped to `nil`. The shared `CurrencyFormatter.price(from:)` intentionally still parses negatives
    /// for other call sites, so the guard lives here at the receipt-header entry point.
    static func normalizedAmount(_ value: Decimal?) -> Decimal? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    /// Recomputes the totals-derived review issues (`.missingTotal`, `.totalsDoNotAddUp`) from the
    /// receipt's CURRENT edited header amounts and line items, preserving every other issue that can't
    /// be re-derived from an edit (low-confidence lines, blur, handwritten, `pagesTruncated`, …). The
    /// review surface calls this whenever the user edits a header amount, so the stale extraction-time
    /// flags can actually clear once the numbers reconcile — and a total edited into garbage gets
    /// re-flagged instead of silently passing.
    func recomputeReviewIssues() {
        var issues = Set(capture.reviewIssues).subtracting([.missingTotal, .totalsDoNotAddUp])
        if capture.total == nil {
            issues.insert(.missingTotal)
        }
        let lineSum = capture.lineItems.reduce(Decimal(0)) { $0 + ($1.priceValue ?? 0) }
        if ReceiptExtractionValidator.totalsMismatch(
            total: capture.total,
            subtotal: capture.subtotal,
            tax: capture.tax,
            discount: capture.discountTotal,
            deposit: capture.depositTotal,
            lineSum: lineSum
        ) == true {
            issues.insert(.totalsDoNotAddUp)
        }
        capture.extractionIssuesRaw = issues.isEmpty
            ? nil
            : issues.map(\.rawValue).sorted().joined(separator: ",")
        objectWillChange.send()
    }

    /// Whether the receipt still has an unresolved totals mismatch. The header amounts are editable and
    /// `recomputeReviewIssues()` clears the flag once they reconcile, so this gates Done rather than
    /// letting an order-of-magnitude misread total (e.g. $400 on a $40 basket) flow into spending.
    var hasUnresolvedTotalsMismatch: Bool {
        capture.reviewIssues.contains(.totalsDoNotAddUp)
    }

    /// Marks the receipt reviewed so it counts toward spending. Refuses (returning `false` and setting
    /// `reviewBlockedMessage`) when there is no usable total or an unresolved totals mismatch, leaving
    /// the receipt as a draft the user can fix. Also returns `false` (and rolls the state back) if the
    /// save fails, so the receipt never looks reviewed when that isn't persisted.
    @discardableResult
    func markReviewed() -> Bool {
        // Re-derive the totals issues from the CURRENT edited state before gating. A mismatch flag
        // (especially the no-subtotal line-sum band) can be the result of a misread *line* price, which
        // the per-line editor doesn't route through `onAmountEdited`; without this the user could fix
        // the offending line yet stay permanently blocked behind a stale `.totalsDoNotAddUp` flag.
        recomputeReviewIssues()
        guard hasUsableTotal else {
            reviewBlockedMessage = "Enter the receipt total before marking it done. Without a total it would count as $0 toward your spending."
            return false
        }
        guard !hasUnresolvedTotalsMismatch else {
            reviewBlockedMessage = "The line items don't add up to the printed total. Fix the total, subtotal, discount, or deposit so they reconcile before marking it done."
            return false
        }
        let previousState = capture.reviewState
        capture.reviewState = .reviewed
        guard persist() else {
            capture.reviewState = previousState
            return false
        }
        return true
    }

    /// Deletes the capture entirely (cascades to its line items). Used when the user discards a
    /// mis-scanned or unwanted receipt instead of keeping it as a draft. Returns whether the delete
    /// persisted, so the caller only dismisses on success.
    @discardableResult
    func discard() -> Bool {
        context.delete(capture)
        guard persist(failureMessage: "Couldn’t discard this receipt. Please try again.") else {
            // The delete is already pending in the live context even though the save failed. Roll it
            // back so the capture isn't lost from the context (the caller keeps the sheet open on the
            // returned `false`), matching the rollback-on-failure discipline elsewhere.
            context.rollback()
            objectWillChange.send()
            return false
        }
        return true
    }

    /// Persists pending edits (e.g. "Save Draft"). Returns whether the save succeeded.
    @discardableResult
    func save() -> Bool {
        persist()
    }

    /// Saves the context, surfacing any failure as `saveError` rather than swallowing it, and reports
    /// whether the save succeeded.
    @discardableResult
    private func persist(failureMessage: String = "Couldn't save your changes. Please try again.") -> Bool {
        do {
            try saveHandler(context)
            objectWillChange.send()
            return true
        } catch {
            saveError = failureMessage
            objectWillChange.send()
            return false
        }
    }
}
