import Foundation
import SwiftData

/// One parsed line from a receipt. Item-level fields are optional because a line may be unparsed,
/// partially read, or low-confidence; `needsReview` flags lines the user should confirm before they
/// are trusted. A line can be promoted into a trusted `PriceEntry`, recorded loosely via
/// `promotedPriceEntryId` so receipts never own or pollute price-comparison data.
@Model
final class ReceiptLineItem {
    var id: UUID
    var createdAt: Date

    /// The raw text of the line as read, always preserved for correction and reprocessing.
    var lineText: String

    var itemNameRaw: String?
    var itemNameNormalized: String?
    var priceValue: Decimal?
    var quantityValue: Decimal?
    var unitType: UnitType?
    var confidence: Float?

    /// True when the line was read with low confidence and should be confirmed before promotion.
    var needsReview: Bool

    /// The id of the `PriceEntry` this line was promoted into, if any. A loose reference (not a
    /// SwiftData relationship) so promotion is one-directional and price history stays independent.
    var promotedPriceEntryId: UUID?

    var receipt: ReceiptCapture?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        lineText: String,
        itemNameRaw: String? = nil,
        itemNameNormalized: String? = nil,
        priceValue: Decimal? = nil,
        quantityValue: Decimal? = nil,
        unitType: UnitType? = nil,
        confidence: Float? = nil,
        needsReview: Bool = false,
        promotedPriceEntryId: UUID? = nil,
        receipt: ReceiptCapture? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lineText = lineText
        self.itemNameRaw = itemNameRaw
        self.itemNameNormalized = itemNameNormalized
        self.priceValue = priceValue
        self.quantityValue = quantityValue
        self.unitType = unitType
        self.confidence = confidence
        self.needsReview = needsReview
        self.promotedPriceEntryId = promotedPriceEntryId
        self.receipt = receipt
    }
}
