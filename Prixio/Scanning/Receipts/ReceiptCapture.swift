import Foundation
import SwiftData

/// Where a receipt entered the app. Receipts can be captured live or imported, and the ingestion
/// path is preserved for later auditing and retention decisions.
enum ReceiptSource: String, Codable, CaseIterable, Sendable {
    case cameraPhoto
    case importedImage
    case importedPDF
}

/// Review lifecycle for a captured receipt. A receipt starts as `pendingReview` and only becomes
/// `reviewed` once the user has confirmed (and optionally promoted) its line items.
enum ReceiptReviewState: String, Codable, CaseIterable, Sendable {
    case pendingReview
    case reviewed
}

/// One receipt-level capture: a basket, not a price. Receipts deliberately live in their own model
/// so that capturing a receipt never writes a `PriceEntry` directly — trustworthy lines are promoted
/// individually via `ReceiptLineItem.promotedPriceEntryId` after user review.
@Model
final class ReceiptCapture: Identifiable {
    var id: UUID
    var createdAt: Date
    var capturedAt: Date
    /// The purchase date read from the receipt, when available (distinct from when it was scanned).
    var purchaseDate: Date?

    var storeChainId: UUID?
    var storeLocationId: UUID?
    var storeChainNameSnapshot: String?
    var storeLocationNameSnapshot: String?

    var subtotal: Decimal?
    var tax: Decimal?
    var discountTotal: Decimal?
    var depositTotal: Decimal?
    var total: Decimal?
    var currencyCode: String

    /// Original image reference kept at least until review is complete. Retention beyond review is
    /// an open product question (see PriceCaptureAndIntelligence.md).
    var imageData: Data?
    var photoAssetId: String?
    /// Raw OCR/model text retained for audit, correction, and later reprocessing.
    var rawText: String?

    var sourceRaw: String
    var reviewStateRaw: String
    /// Which spending category this receipt's basket counts toward. Defaults to groceries (the common
    /// case) but is user-editable at review so a hardware-store or restaurant receipt doesn't inflate
    /// the grocery figure. Has a stored default so existing receipts migrate cleanly.
    var categoryRaw: String = ExpenseCategory.groceries.rawValue
    /// Comma-joined `ReceiptReviewIssue` raw values from extraction validation.
    var extractionIssuesRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \ReceiptLineItem.receipt)
    var lineItems: [ReceiptLineItem]

    var source: ReceiptSource {
        get { ReceiptSource(rawValue: sourceRaw) ?? .cameraPhoto }
        set { sourceRaw = newValue.rawValue }
    }

    var reviewState: ReceiptReviewState {
        get { ReceiptReviewState(rawValue: reviewStateRaw) ?? .pendingReview }
        set { reviewStateRaw = newValue.rawValue }
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .groceries }
        set { categoryRaw = newValue.rawValue }
    }

    var reviewIssues: [ReceiptReviewIssue] {
        (extractionIssuesRaw ?? "")
            .split(separator: ",")
            .compactMap { ReceiptReviewIssue(rawValue: String($0)) }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        capturedAt: Date,
        purchaseDate: Date? = nil,
        storeChainId: UUID? = nil,
        storeLocationId: UUID? = nil,
        storeChainNameSnapshot: String? = nil,
        storeLocationNameSnapshot: String? = nil,
        subtotal: Decimal? = nil,
        tax: Decimal? = nil,
        discountTotal: Decimal? = nil,
        depositTotal: Decimal? = nil,
        total: Decimal? = nil,
        currencyCode: String = AppCurrency.defaultCode,
        imageData: Data? = nil,
        photoAssetId: String? = nil,
        rawText: String? = nil,
        source: ReceiptSource = .cameraPhoto,
        reviewState: ReceiptReviewState = .pendingReview,
        category: ExpenseCategory = .groceries,
        extractionIssuesRaw: String? = nil,
        lineItems: [ReceiptLineItem] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.purchaseDate = purchaseDate
        self.storeChainId = storeChainId
        self.storeLocationId = storeLocationId
        self.storeChainNameSnapshot = storeChainNameSnapshot
        self.storeLocationNameSnapshot = storeLocationNameSnapshot
        self.subtotal = subtotal
        self.tax = tax
        self.discountTotal = discountTotal
        self.depositTotal = depositTotal
        self.total = total
        self.currencyCode = currencyCode
        self.imageData = imageData
        self.photoAssetId = photoAssetId
        self.rawText = rawText
        self.sourceRaw = source.rawValue
        self.reviewStateRaw = reviewState.rawValue
        self.categoryRaw = category.rawValue
        self.extractionIssuesRaw = extractionIssuesRaw
        self.lineItems = lineItems
    }
}
