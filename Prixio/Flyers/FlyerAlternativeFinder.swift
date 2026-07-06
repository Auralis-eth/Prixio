import Foundation

/// Similar-but-different flyer deals suggested alongside one shopping-list item's
/// direct matches ("no soy milk on sale, but oat milk is").
struct ShoppingItemFlyerAlternatives: Identifiable, Equatable {
    let itemKey: String
    let displayName: String
    /// Suggested alternative deals, best price first.
    let alternatives: [FlyerDeal]

    var id: String { itemKey }
}

/// Suggests flyer deals for products *similar to* a shopping-list item when they are
/// not direct matches — a different product of the same kind (list "almond milk" →
/// flyer "Soy Milk"), or a broader version of a specific item (list "daisy sour
/// cream" → flyer "Sour Cream"). Pure and deterministic, like `FlyerDealMatcher`.
///
/// Similarity has two tiers. When both sides carry a substitution class from the
/// LLM enrichment pass (`FlyerNameEnricher`), class equality decides — so "chicken
/// thighs" can suggest "Chicken Breast" (both "chicken") and "sour cream" never
/// suggests "Ice Cream" (different classes), neither of which the lexical rule gets
/// right. Without a class on both sides, similarity falls back to the original rule:
/// the same head noun (last normalized token) on both sides. That fallback is
/// deliberately stricter than `PriceInsightEngine.areSubstitutable` (which accepts a
/// shared head noun on *either* side): these suggestions are user-facing rows built
/// from scraped data, and the one-sided rule would offer "Milk Chocolate" as an
/// alternative for "milk".
struct FlyerAlternativeFinder {
    /// Cap per item so a common head noun ("cheese") doesn't flood the review list.
    static let maxAlternativesPerItem = 3

    /// Cap on candidate names enriched purely for alternative discovery (the
    /// shared-token prefilter below is much looser than the direct matcher's), so a
    /// generic list item like "milk" can't turn the first cache-cold run into dozens
    /// of model calls.
    static let maxEnrichmentTargets = 96

    /// Returns one entry per item that has at least one alternative. When an item has
    /// a direct deal, an alternative must beat the best direct price to be worth
    /// suggesting; without direct deals any similar deal qualifies. The same product
    /// at several banners is collapsed to its best-priced deal so the capped slots
    /// carry product variety, not banner repeats.
    ///
    /// `queryEnrichments` supplies the *list items'* enrichments, keyed by the match
    /// item's `itemKey` — candidates carry their own on themselves. Items without an
    /// enrichment simply use the head-noun fallback.
    func findAlternatives(
        matches: [ShoppingItemFlyerMatches],
        extractions: [FlyerExtractionResult],
        queryEnrichments: [String: EnrichedProductName] = [:]
    ) -> [ShoppingItemFlyerAlternatives] {
        let allDeals: [FlyerDeal] = extractions.flatMap { result in
            result.candidates.map {
                FlyerDeal(banner: result.banner, candidate: $0, sourceURL: result.sourceURL, fetchedAt: result.fetchedAt)
            }
        }

        return matches.compactMap { item in
            let priceCeiling = item.bestDeal?.candidate.price
            let queryClass = queryEnrichments[item.itemKey]?.substitutionClass
            let similar = allDeals.filter { deal in
                let candidateKey = deal.candidate.normalizedItemKey
                let headNoun = deal.candidate.enrichedHeadNoun
                guard !ItemKeyNormalizer.matches(queryKey: item.itemKey, entryKey: candidateKey, entryHeadNoun: headNoun),
                      Self.isAlternative(
                        queryKey: item.itemKey,
                        candidateKey: candidateKey,
                        candidateHeadNoun: headNoun,
                        queryClass: queryClass,
                        candidateClass: deal.candidate.enrichedSubstitutionClass
                      ) else {
                    return false
                }
                guard let priceCeiling else { return true }
                return deal.candidate.price < priceCeiling
            }

            // Collapse cross-banner repeats of the same product to the best deal.
            var bestByProduct: [String: FlyerDeal] = [:]
            for deal in similar {
                let key = deal.candidate.normalizedItemKey
                if let current = bestByProduct[key], !FlyerDealMatcher.dealOrder(deal, current) {
                    continue
                }
                bestByProduct[key] = deal
            }

            let alternatives = bestByProduct.values
                .sorted(by: FlyerDealMatcher.dealOrder)
                .prefix(Self.maxAlternativesPerItem)
            guard !alternatives.isEmpty else { return nil }
            return ShoppingItemFlyerAlternatives(
                itemKey: item.itemKey,
                displayName: item.displayName,
                alternatives: Array(alternatives)
            )
        }
    }

    /// Whether a non-matching flyer candidate is close enough to suggest. Inputs may
    /// be raw or normalized.
    ///
    /// When both sides carry a substitution class (`FlyerNameEnricher`), class
    /// equality decides — different products of the same kind match even with
    /// unrelated head nouns ("chicken thighs" → "Chicken Breast"), and same-head
    /// products of different kinds are rejected ("sour cream" ✗ "Ice Cream").
    ///
    /// Otherwise, the lexical rule: both keys share the same head noun (length ≥ 3,
    /// so a unit fragment can't anchor a suggestion) but are not the same product.
    /// When the candidate carries an enriched head noun, its phrase's head token
    /// anchors similarity instead of the key's last token — so "Chicken Breast
    /// Boneless Skinless" (head "chicken breast") can be suggested for "turkey
    /// breast"-style queries anchored on the true noun, and a candidate whose
    /// trailing token is a mere descriptor stops anchoring on it.
    static func isAlternative(
        queryKey: String,
        candidateKey: String,
        candidateHeadNoun: String? = nil,
        queryClass: String? = nil,
        candidateClass: String? = nil
    ) -> Bool {
        let queryTokens = ItemKeyNormalizer.tokens(queryKey)
        let candidateTokens = ItemKeyNormalizer.tokens(candidateKey)
        guard !queryTokens.isEmpty, queryTokens != candidateTokens else {
            return false
        }
        if let queryClass, let candidateClass {
            return queryClass == candidateClass
        }
        let candidateHead = candidateHeadNoun.flatMap { ItemKeyNormalizer.tokens($0).last } ?? candidateTokens.last
        guard let queryHead = queryTokens.last, queryHead.count >= 3 else {
            return false
        }
        return queryHead == candidateHead
    }

    /// The candidate product names worth enriching before finding alternatives:
    /// unenriched candidates sharing at least one substantive token (≥ 3 characters)
    /// with some query. Much looser than `FlyerDealMatcher.enrichmentTargets`'s
    /// all-tokens subset — class comparison needs "Chicken Breast" enriched for a
    /// "chicken thighs" query, which shares only "chicken". Candidates sharing *no*
    /// token with any query stay unenriched (and so can never be class-matched);
    /// that bounds the model work and keeps wholly unrelated products out.
    static func enrichmentTargets(
        queries: [FlyerDealMatcher.Query],
        extractions: [FlyerExtractionResult]
    ) -> [String] {
        let queryTokens = Set(
            queries.flatMap { ItemKeyNormalizer.tokens($0.itemKey) }.filter { $0.count >= 3 }
        )
        guard !queryTokens.isEmpty else { return [] }

        var seen = Set<String>()
        var targets: [String] = []
        for result in extractions {
            for candidate in result.candidates {
                guard targets.count < Self.maxEnrichmentTargets else { return targets }
                guard candidate.enrichedSubstitutionClass == nil,
                      seen.insert(candidate.productName).inserted else { continue }
                let tokens = ItemKeyNormalizer.tokens(candidate.normalizedItemKey)
                if tokens.contains(where: queryTokens.contains) {
                    targets.append(candidate.productName)
                }
            }
        }
        return targets
    }
}
