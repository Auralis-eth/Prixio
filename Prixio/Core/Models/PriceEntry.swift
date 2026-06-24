import Foundation
import SwiftData

@Model
final class PriceEntry {
    var id: UUID
    var createdAt: Date
    var capturedAt: Date
    var itemNameRaw: String
    var itemNameNormalized: String
    var brand: String?
    var priceValue: Decimal
    var currencyCode: String
    var unitType: UnitType
    var unitQuantityValue: Decimal?
    var normalizedUnitPriceValue: Decimal?
    var normalizedUnitType: UnitType?
    var storeChainId: UUID?
    var storeLocationId: UUID?
    var storeChainNameSnapshot: String?
    var storeLocationNameSnapshot: String?
    var storeCoordinateLat: Double?
    var storeCoordinateLon: Double?
    var photoAssetId: String
    var ocrText: String?
    var confidence: Float?
    var parserReviewStateRaw: String?
    var parserReviewIssuesRaw: String?
    var parserUsedFoundationModel: Bool
    var parserAmbiguityNotesRaw: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        capturedAt: Date,
        itemNameRaw: String,
        itemNameNormalized: String,
        brand: String? = nil,
        priceValue: Decimal,
        currencyCode: String = "CAD",
        unitType: UnitType,
        unitQuantityValue: Decimal? = nil,
        normalizedUnitPriceValue: Decimal? = nil,
        normalizedUnitType: UnitType? = nil,
        storeChainId: UUID? = nil,
        storeLocationId: UUID? = nil,
        storeChainNameSnapshot: String? = nil,
        storeLocationNameSnapshot: String? = nil,
        storeCoordinateLat: Double? = nil,
        storeCoordinateLon: Double? = nil,
        photoAssetId: String,
        ocrText: String? = nil,
        confidence: Float? = nil,
        parserReviewStateRaw: String? = nil,
        parserReviewIssuesRaw: String? = nil,
        parserUsedFoundationModel: Bool = false,
        parserAmbiguityNotesRaw: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.itemNameRaw = itemNameRaw
        self.itemNameNormalized = itemNameNormalized
        self.brand = brand
        self.priceValue = priceValue
        self.currencyCode = currencyCode
        self.unitType = unitType
        self.unitQuantityValue = unitQuantityValue
        self.normalizedUnitPriceValue = normalizedUnitPriceValue
        self.normalizedUnitType = normalizedUnitType
        self.storeChainId = storeChainId
        self.storeLocationId = storeLocationId
        self.storeChainNameSnapshot = storeChainNameSnapshot
        self.storeLocationNameSnapshot = storeLocationNameSnapshot
        self.storeCoordinateLat = storeCoordinateLat
        self.storeCoordinateLon = storeCoordinateLon
        self.photoAssetId = photoAssetId
        self.ocrText = ocrText
        self.confidence = confidence
        self.parserReviewStateRaw = parserReviewStateRaw
        self.parserReviewIssuesRaw = parserReviewIssuesRaw
        self.parserUsedFoundationModel = parserUsedFoundationModel
        self.parserAmbiguityNotesRaw = parserAmbiguityNotesRaw
    }
}
