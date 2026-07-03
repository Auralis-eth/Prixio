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
/// Similarity requires the same head noun (last normalized token) on both sides.
/// This is deliberately stricter than `PriceInsightEngine.areSubstitutable` (which
/// accepts a shared head noun on *either* side): these suggestions are user-facing
/// rows built from scraped data, and the one-sided rule would offer "Milk Chocolate"
/// as an alternative for "milk".
struct FlyerAlternativeFinder {
    /// Cap per item so a common head noun ("cheese") doesn't flood the review list.
    static let maxAlternativesPerItem = 3

    /// Returns one entry per item that has at least one alternative. When an item has
    /// a direct deal, an alternative must beat the best direct price to be worth
    /// suggesting; without direct deals any similar deal qualifies. The same product
    /// at several banners is collapsed to its best-priced deal so the capped slots
    /// carry product variety, not banner repeats.
    func findAlternatives(
        matches: [ShoppingItemFlyerMatches],
        extractions: [FlyerExtractionResult]
    ) -> [ShoppingItemFlyerAlternatives] {
        let allDeals: [FlyerDeal] = extractions.flatMap { result in
            result.candidates.map {
                FlyerDeal(banner: result.banner, candidate: $0, sourceURL: result.sourceURL, fetchedAt: result.fetchedAt)
            }
        }

        return matches.compactMap { item in
            let priceCeiling = item.bestDeal?.candidate.price
            let similar = allDeals.filter { deal in
                let candidateKey = deal.candidate.normalizedItemKey
                guard !ItemKeyNormalizer.matches(queryKey: item.itemKey, entryKey: candidateKey),
                      Self.isAlternative(queryKey: item.itemKey, candidateKey: candidateKey) else {
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

    /// Whether a non-matching flyer candidate is close enough to suggest: both keys
    /// share the same head noun (length ≥ 3, so a unit fragment can't anchor a
    /// suggestion) but are not the same product. Inputs may be raw or normalized.
    static func isAlternative(queryKey: String, candidateKey: String) -> Bool {
        let queryTokens = ItemKeyNormalizer.tokens(queryKey)
        let candidateTokens = ItemKeyNormalizer.tokens(candidateKey)
        guard let queryHead = queryTokens.last, queryHead.count >= 3,
              queryHead == candidateTokens.last else {
            return false
        }
        return queryTokens != candidateTokens
    }
}
