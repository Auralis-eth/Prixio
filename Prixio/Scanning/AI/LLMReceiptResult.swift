//
//  LLMReceiptResult.swift
//  Prixio
//
//  The structured output produced by the Foundation Models image-analysis flow for
//  receipts. Mirrors LLMOCRResult (single price tags) but describes a whole basket:
//  store, date, totals, and itemized lines. No Vision OCR — the multimodal model reads
//  the receipt photo directly and returns this @Generable type.
//

import Foundation
import FoundationModels

@Generable
struct LLMReceiptResult {
    @Guide(description: "The store or merchant name printed on the receipt. Null if not legible.")
    var storeName: String?

    @Guide(description: "Purchase date printed on the receipt, formatted YYYY-MM-DD. Null if absent or unreadable.")
    var purchaseDate: String?

    @Guide(description: "Sum of item prices before tax, if printed.", .minimum(0))
    var subtotal: Decimal?

    @Guide(description: "Total tax charged, if printed.", .minimum(0))
    var tax: Decimal?

    @Guide(description: "Total discounts or savings, as a positive amount, if printed.", .minimum(0))
    var discountTotal: Decimal?

    @Guide(description: "Total bottle/container deposits, as a positive amount, if printed.", .minimum(0))
    var depositTotal: Decimal?

    @Guide(description: "The final amount paid (grand total), if printed.", .minimum(0))
    var total: Decimal?

    @Guide(description: "The ISO 4217 currency code (e.g. CAD, USD) if it can be determined from the receipt. Null if unclear.")
    var currencyCode: String? = nil

    @Guide(description: "The single spending category that best fits this receipt's merchant and items as a whole. Use groceries for supermarket food baskets; use other when nothing fits well. Null if unclear.")
    var spendingCategory: ExpenseCategory? = nil

    @Guide(description: "Every purchased line item in printed order. Exclude subtotal, tax, total, and other summary rows.", .maximumCount(60))
    var lineItems: [LLMReceiptLine]

    @Guide(description: "Every problem that applies to this receipt extraction. Empty only if the receipt is clean and fully legible.", .maximumCount(10))
    var issues: [LLMReceiptIssue]
}

@Generable
struct LLMReceiptLine {
    @Guide(description: "The verbatim text of this receipt line.")
    var rawText: String

    @Guide(description: "The product name for this line, cleaned of register codes and abbreviations where you are confident. Null if not identifiable.")
    var itemName: String?

    @Guide(description: "The price charged for this line.", .minimum(0))
    var price: Decimal?

    @Guide(description: "Quantity purchased on this line. Usually 1.", .minimum(0))
    var quantity: Decimal?

    @Guide(description: "Unit the line price applies to, if discernible. Most receipt lines are each.")
    var unit: UnitType?

    @Guide(description: "Your confidence in this line's name and price, from 0 (guess) to 1 (certain).", .range(0...1))
    var confidence: Double? = nil

    @Guide(description: "True if this line was hard to read or you are unsure of its name or price.")
    var lowConfidence: Bool
}

@Generable
enum LLMReceiptIssue: String, Codable {
    case totalsDoNotAddUp
    case partiallyObscured
    case blurOrGlare
    case handwritten
    case notAReceipt
    case multipleReceipts
}
