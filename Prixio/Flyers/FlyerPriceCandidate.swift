import Foundation

/// A structured, reviewable price candidate extracted from acquired flyer content
/// (captured flyer JSON or harvested text): acquisition produced bytes, extraction
/// turns them into provenance-rich candidates the user can review before any are
/// promoted into trusted price history.
///
/// Provenance that is uniform across a banner's run (merchant, source URL, fetch
/// time, method) lives on `FlyerExtractionResult`; per-item fields live here.
struct FlyerPriceCandidate: Identifiable, Equatable {
    /// Product name as advertised in the flyer.
    let productName: String
    /// Normalized item key (via `ItemKeyNormalizer`) for matching against shopping
    /// list / price history.
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
    /// Set by the LLM enrichment pass (`FlyerNameEnricher`): the normalized key of
    /// the product's canonical name (brand/size/marketing words removed). Nil until
    /// (or unless) the candidate is enriched — matching falls back to
    /// `normalizedItemKey`.
    var enrichedItemKey: String? = nil
    /// Set by the enrichment pass: the product's normalized head-noun phrase, used by
    /// `ItemKeyNormalizer.matches(queryKey:entryKey:entryHeadNoun:)` instead of the
    /// last-token heuristic.
    var enrichedHeadNoun: String? = nil
    /// Set by the enrichment pass: the product's coarse substitution class (one of
    /// `FlyerNameEnricher.substitutionClasses`), compared for equality by
    /// `FlyerAlternativeFinder` instead of the shared-head-noun heuristic.
    var enrichedSubstitutionClass: String? = nil

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

// MARK: - Enrichment application

extension FlyerPriceCandidate {
    /// A copy carrying the enrichment's normalized keys. Empty normalizations leave
    /// the corresponding field nil so matching falls back deterministically.
    func enriched(with enrichment: EnrichedProductName) -> FlyerPriceCandidate {
        var copy = self
        let canonicalKey = ItemKeyNormalizer.normalize(enrichment.canonicalName)
        let headNoun = ItemKeyNormalizer.normalize(enrichment.headNoun)
        copy.enrichedItemKey = canonicalKey.isEmpty ? nil : canonicalKey
        copy.enrichedHeadNoun = headNoun.isEmpty ? nil : headNoun
        // Classes come from a fixed vocabulary (validated upstream), not free text —
        // carried verbatim.
        copy.enrichedSubstitutionClass = enrichment.substitutionClass
        return copy
    }
}

extension FlyerExtractionResult {
    /// The same result with each candidate whose product name has an enrichment
    /// carrying it; all other candidates pass through unchanged.
    func applyingEnrichments(_ enrichments: [String: EnrichedProductName]) -> FlyerExtractionResult {
        guard !enrichments.isEmpty else { return self }
        return FlyerExtractionResult(
            banner: banner,
            sourceURL: sourceURL,
            fetchedAt: fetchedAt,
            method: method,
            candidates: candidates.map { candidate in
                enrichments[candidate.productName].map(candidate.enriched(with:)) ?? candidate
            },
            message: message
        )
    }
}
