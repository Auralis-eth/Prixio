import Foundation

/// A structured, reviewable price candidate extracted from acquired flyer content
/// (captured flyer JSON or harvested text). This is step 5's output: acquisition
/// produced bytes, extraction turns them into provenance-rich candidates the user
/// can review before any are promoted into trusted price history (steps 6–8).
///
/// Provenance that is uniform across a banner's run (merchant, source URL, fetch
/// time, method) lives on `FlyerExtractionResult`; per-item fields live here.
struct FlyerPriceCandidate: Identifiable, Equatable {
    /// Product name as advertised in the flyer.
    let productName: String
    /// Normalized item key (via `ItemKeyNormalizer`) for matching against shopping
    /// list / price history in step 6.
    let normalizedItemKey: String
    let brand: String?
    /// Advertised price.
    let price: Decimal
    /// Regular/reference price when the flyer shows one alongside the sale price.
    let regularPrice: Decimal?
    let priceKind: PriceKind
    /// Package size text as advertised (e.g. "500 g", "12 x 355 mL"), unparsed.
    let packageSize: String?
    /// Derived unit price when the payload exposed one; not computed here.
    let unitPrice: Decimal?
    let saleStartDate: Date?
    let saleEndDate: Date?
    /// True when the price is gated behind loyalty/membership or a digital coupon.
    let memberOnly: Bool
    /// The raw text/JSON fragment this candidate came from, for review.
    let sourceText: String
    /// 0...1 — higher for structured JSON, lower for text-paired extraction.
    let confidence: Float

    var id: String {
        "\(normalizedItemKey)|\(price)|\(priceKind.rawValue)|\(saleEndDate.map { "\($0.timeIntervalSince1970)" } ?? "")"
    }
}

/// The result of extracting one banner's acquired flyer content. Carries the
/// uniform provenance for every candidate plus a short diagnostic of how the run
/// went, mirroring the discovery/acquisition logging discipline.
struct FlyerExtractionResult: Identifiable, Equatable {
    let banner: FlyerBanner
    let sourceURL: URL?
    let fetchedAt: Date?
    let method: FlyerAcquisitionMethod?
    let candidates: [FlyerPriceCandidate]
    /// Short human-readable summary (counts / why nothing was extracted).
    let message: String

    var id: FlyerBannerID { banner.id }

    var candidateCount: Int { candidates.count }
}
