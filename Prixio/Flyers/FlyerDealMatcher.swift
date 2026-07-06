import Foundation

/// A single flyer deal for a shopping-list item: one extracted candidate at one
/// banner. Several deals can match the same list item (different products, or the
/// same product across banners), which is what powers store-to-store comparison.
struct FlyerDeal: Identifiable, Equatable {
    let banner: FlyerBanner
    let candidate: FlyerPriceCandidate
    /// Provenance carried from the extraction result, so a saved deal records where
    /// and when it came from without re-looking-up the source.
    let sourceURL: URL?
    let fetchedAt: Date?

    init(banner: FlyerBanner, candidate: FlyerPriceCandidate, sourceURL: URL? = nil, fetchedAt: Date? = nil) {
        self.banner = banner
        self.candidate = candidate
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
    }

    var id: String { "\(banner.id.rawValue)|\(candidate.id)" }
}

/// The flyer deals matched to one shopping-list item, best price first.
struct ShoppingItemFlyerMatches: Identifiable, Equatable {
    let itemKey: String
    let displayName: String
    /// Matching deals, sorted by price ascending (best deal first).
    let deals: [FlyerDeal]

    var id: String { itemKey }
    var bestDeal: FlyerDeal? { deals.first }
    var hasDeals: Bool { !deals.isEmpty }
}

/// Matches extracted flyer price candidates against shopping-list items. Pure and
/// deterministic.
///
/// Matching reuses `ItemKeyNormalizer.matches`, the same
/// generic-query→specific-product rule `PriceInsightEngine` uses: the shopping-list
/// item is the query (so a generic "milk" rolls up "Almond Milk"), and the flyer
/// candidate is the entry. A more-specific list item never matches a broader
/// candidate, so "daisy sour cream" won't pull in a generic "sour cream" deal.
/// Candidates carrying an enrichment (`FlyerNameEnricher`) match through the
/// head-noun-aware overload, which fixes trailing-descriptor misses and
/// compound-product false rollups.
struct FlyerDealMatcher {
    /// A shopping-list item to find deals for. `itemKey` may be raw or already
    /// normalized — `ItemKeyNormalizer.matches` normalizes both sides internally.
    struct Query: Equatable {
        let itemKey: String
        let displayName: String

        init(itemKey: String, displayName: String) {
            self.itemKey = itemKey
            self.displayName = displayName
        }
    }

    /// Returns one result per query (including queries with no deals, so callers can
    /// show "no deals found" explicitly). Each result's deals are sorted best-price
    /// first, then by confidence, then by banner rank.
    func match(queries: [Query], extractions: [FlyerExtractionResult]) -> [ShoppingItemFlyerMatches] {
        // Flatten candidates once, tagged with their banner.
        let allDeals: [FlyerDeal] = extractions.flatMap { result in
            result.candidates.map {
                FlyerDeal(banner: result.banner, candidate: $0, sourceURL: result.sourceURL, fetchedAt: result.fetchedAt)
            }
        }

        return queries.map { query in
            let matched = allDeals
                .filter {
                    ItemKeyNormalizer.matches(
                        queryKey: query.itemKey,
                        entryKey: $0.candidate.normalizedItemKey,
                        entryHeadNoun: $0.candidate.enrichedHeadNoun
                    )
                }
                .sorted(by: Self.dealOrder)
            return ShoppingItemFlyerMatches(
                itemKey: query.itemKey,
                displayName: query.displayName,
                deals: matched
            )
        }
    }

    /// The product names worth enriching before matching these queries: candidates
    /// whose key contains *all* of some query's tokens, ignoring the head-noun
    /// anchor. That superset covers both directions enrichment can change: entries
    /// today's rule wrongly rejects (trailing descriptors) and entries it wrongly
    /// accepts (compound products) — while leaving the hundreds of never-relevant
    /// candidates un-enriched, which is what keeps the model pass fast.
    static func enrichmentTargets(queries: [Query], extractions: [FlyerExtractionResult]) -> [String] {
        let querySets = queries
            .map { Set(ItemKeyNormalizer.tokens($0.itemKey)) }
            .filter { !$0.isEmpty }
        guard !querySets.isEmpty else { return [] }

        var seen = Set<String>()
        var targets: [String] = []
        for result in extractions {
            for candidate in result.candidates {
                guard candidate.enrichedHeadNoun == nil,
                      seen.insert(candidate.productName).inserted else { continue }
                let entrySet = Set(ItemKeyNormalizer.tokens(candidate.normalizedItemKey))
                if querySets.contains(where: { $0.isSubset(of: entrySet) }) {
                    targets.append(candidate.productName)
                }
            }
        }
        return targets
    }

    /// Best price first; ties broken by higher confidence, then better-ranked banner,
    /// then product name for stable ordering. Shared with `FlyerAlternativeFinder`
    /// so alternatives sort exactly like direct deals.
    static func dealOrder(_ lhs: FlyerDeal, _ rhs: FlyerDeal) -> Bool {
        if lhs.candidate.price != rhs.candidate.price {
            return lhs.candidate.price < rhs.candidate.price
        }
        if lhs.candidate.confidence != rhs.candidate.confidence {
            return lhs.candidate.confidence > rhs.candidate.confidence
        }
        if lhs.banner.rank != rhs.banner.rank {
            return lhs.banner.rank < rhs.banner.rank
        }
        return lhs.candidate.productName < rhs.candidate.productName
    }
}
