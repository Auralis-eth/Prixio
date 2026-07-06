//
//  ReceiptDraftBuilder.swift
//  Prixio
//
//  App code, not model code. Applies a Foundation Models LLMReceiptResult onto a
//  persisted ReceiptCapture: sets header/totals, rebuilds the line items, and records
//  the review issues from ReceiptExtractionValidator. Low-confidence, priceless, or
//  totals-suspect lines are marked needsReview so nothing is silently trusted.
//

import Foundation
import SwiftData

@MainActor
enum ReceiptDraftBuilder {
    static func apply(_ result: LLMReceiptResult, to capture: ReceiptCapture, context: ModelContext) {
        if let storeName = result.storeName, !storeName.isEmpty {
            capture.storeChainNameSnapshot = storeName
        }
        if let purchaseDate = parseDate(result.purchaseDate) {
            capture.purchaseDate = purchaseDate
        }
        // Drop negative header amounts to nil. `@Guide(.minimum(0))` on `LLMReceiptResult` is a model
        // hint, not an enforced constraint, so a model can still emit a negative total/discount/deposit
        // — and a negative would corrupt totals reconciliation and the spending sums. Mirrors the
        // manual-edit guard in `ReceiptReviewViewModel.normalizedAmount`.
        capture.subtotal = nonNegative(result.subtotal)
        capture.tax = nonNegative(result.tax)
        capture.discountTotal = nonNegative(result.discountTotal)
        capture.depositTotal = nonNegative(result.depositTotal)
        capture.total = nonNegative(result.total)
        if let currencyCode = result.currencyCode?.trimmingCharacters(in: .whitespaces), !currencyCode.isEmpty {
            capture.currencyCode = currencyCode.uppercased()
        }
        // The model's category is a *suggestion*: pre-fill it only while the receipt
        // is still awaiting review and the category is untouched (the stored default).
        // A user's re-categorization — or a reviewed receipt — is never overridden by
        // re-extraction.
        if capture.reviewState == .pendingReview,
           capture.category == .groceries,
           let suggested = result.spendingCategory {
            capture.category = suggested
        }

        let extractionIssues = ReceiptExtractionValidator.issues(for: result)
        // Preserve import-origin facts that extraction can't re-derive (e.g. PDF page truncation),
        // then union with the freshly computed extraction issues so re-extraction stays idempotent.
        let importIssues = Set(capture.reviewIssues).intersection([.pagesTruncated])
        let issues = Array(importIssues.union(extractionIssues))
        capture.extractionIssuesRaw = issues.isEmpty ? nil : issues.map(\.rawValue).joined(separator: ",")
        let totalsSuspect = extractionIssues.contains(.totalsDoNotAddUp)

        // Rebuild lines so re-extraction is idempotent.
        for existing in capture.lineItems {
            context.delete(existing)
        }
        capture.lineItems = []

        for line in result.lineItems {
            let hasName = !(line.itemName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            let needsReview = line.lowConfidence || line.price == nil || !hasName || totalsSuspect

            let item = ReceiptLineItem(
                lineText: line.rawText,
                itemNameRaw: line.itemName,
                itemNameNormalized: line.itemName.map(ItemKeyNormalizer.normalize),
                priceValue: line.price,
                quantityValue: line.quantity,
                unitType: line.unit,
                confidence: line.confidence.map(Float.init) ?? (line.lowConfidence ? 0.4 : 0.9),
                needsReview: needsReview,
                receipt: capture
            )
            context.insert(item)
            capture.lineItems.append(item)
        }
    }

    /// A parsed header amount is never negative; a negative reading is dropped to `nil`.
    private static func nonNegative(_ value: Decimal?) -> Decimal? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
