import Foundation
import SwiftData

/// A flyer price the user reviewed and chose to save. Stored separately from
/// user-captured `PriceEntry` so scraped flyer data, whose availability and
/// geography are less certain, never contaminates trusted capture history. Carries full
/// provenance so any surface using it can label source and confidence.
@Model
final class FlyerPriceRecord {
    var id: UUID
    var savedAt: Date

    /// Stable identity for a saved deal (`bannerID|normalizedItemKey|price`), so the
    /// same deal can't be saved twice.
    var dealKey: String

    // Provenance
    var bannerID: String
    var bannerName: String
    var sourceURL: URL?
    var fetchedAt: Date?
    /// Geography/store context the flyer was acquired under (e.g. "AB/Calgary/T2P1J9").
    var storeContext: String?

    // Product
    var productName: String
    var normalizedItemKey: String
    var brand: String?
    var priceValue: Decimal
    var currencyCode: String
    var regularPriceValue: Decimal?
    var priceKindRaw: String
    var packageSize: String?
    var saleStartDate: Date?
    var saleEndDate: Date?
    var memberOnly: Bool
    var confidence: Float
    var sourceText: String

    /// The shopping-list item key this deal was saved for (the matched query), so a
    /// later surface can tie the saved price back to the list item.
    var matchedItemKey: String?

    init(
        id: UUID = UUID(),
        savedAt: Date = .now,
        dealKey: String,
        bannerID: String,
        bannerName: String,
        sourceURL: URL? = nil,
        fetchedAt: Date? = nil,
        storeContext: String? = nil,
        productName: String,
        normalizedItemKey: String,
        brand: String? = nil,
        priceValue: Decimal,
        currencyCode: String = AppCurrency.defaultCode,
        regularPriceValue: Decimal? = nil,
        priceKindRaw: String,
        packageSize: String? = nil,
        saleStartDate: Date? = nil,
        saleEndDate: Date? = nil,
        memberOnly: Bool = false,
        confidence: Float,
        sourceText: String,
        matchedItemKey: String? = nil
    ) {
        self.id = id
        self.savedAt = savedAt
        self.dealKey = dealKey
        self.bannerID = bannerID
        self.bannerName = bannerName
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
        self.storeContext = storeContext
        self.productName = productName
        self.normalizedItemKey = normalizedItemKey
        self.brand = brand
        self.priceValue = priceValue
        self.currencyCode = currencyCode
        self.regularPriceValue = regularPriceValue
        self.priceKindRaw = priceKindRaw
        self.packageSize = packageSize
        self.saleStartDate = saleStartDate
        self.saleEndDate = saleEndDate
        self.memberOnly = memberOnly
        self.confidence = confidence
        self.sourceText = sourceText
        self.matchedItemKey = matchedItemKey
    }
}

extension FlyerPriceRecord {
    /// The stable dealKey for a banner+candidate pairing.
    static func dealKey(bannerID: String, normalizedItemKey: String, price: Decimal) -> String {
        "\(bannerID)|\(normalizedItemKey)|\(price)"
    }
}

// MARK: - Expiry

extension FlyerPriceRecord {
    /// Shelf life for records with no sale-end date: flyers rotate weekly, so after
    /// this long a fetched price is assumed no longer advertised.
    static let fallbackShelfLifeDays = 14
    /// How long an expired record stays in the store (still visible in the
    /// saved-prices manager, labeled expired) before the launch sweep deletes it.
    static let deletionGraceDays = 30

    /// The instant this record's sale window passes. The sale-end date is inclusive —
    /// a flyer "valid to July 5" is still active on July 5, so the record expires at
    /// the start of July 6. Without an end date, the record expires
    /// `fallbackShelfLifeDays` after it was fetched (or saved).
    var expiresAt: Date {
        if let end = saleEndDate {
            return end.addingTimeInterval(86_400)
        }
        let reference = fetchedAt ?? savedAt
        return reference.addingTimeInterval(TimeInterval(Self.fallbackShelfLifeDays) * 86_400)
    }

    /// Whether this record's sale window has passed (see `expiresAt`).
    ///
    /// Expired records are hidden from Compare and shopping estimates but kept in the
    /// saved-prices manager until the deletion grace period lapses.
    func isExpired(asOf now: Date = .now) -> Bool {
        now >= expiresAt
    }
}
