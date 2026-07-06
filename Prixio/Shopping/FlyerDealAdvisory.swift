import Foundation

/// The shopping list's advisory line for saved flyer deals. Basket totals stay
/// capture-only — this rides alongside the estimate as
/// "Flyer deals could save ~$X at <banner>" without changing any total.
struct FlyerDealAdvisory: Equatable {
    let bannerName: String
    /// Distinct active list items with a current (non-expired) flyer price at this banner.
    let matchedItemCount: Int
    /// Potential savings versus each matched item's cheapest captured package price,
    /// summed across items where the flyer price is lower. `nil` when no matched item
    /// has a captured baseline to compare against (deals exist, but there is nothing
    /// to measure savings from).
    let estimatedSavings: Decimal?

    var message: String {
        let items = "\(matchedItemCount) item\(matchedItemCount == 1 ? "" : "s")"
        if let estimatedSavings, estimatedSavings > 0 {
            let amount = CurrencyFormatter.shared.display(estimatedSavings)
            return "Flyer deals could save ~\(amount) at \(bannerName) (\(items))"
        }
        return "\(items) on your list \(matchedItemCount == 1 ? "has" : "have") a flyer deal at \(bannerName)"
    }

    /// Builds the advisory for the active list items, or `nil` when no current flyer
    /// price matches any item. Matching reuses `ItemKeyNormalizer.matches` (the same
    /// head-noun rollup as deal matching and Compare promotion); the savings baseline
    /// is each item's cheapest captured package price, mirroring the basket's
    /// package-price basis. The banner offering the highest savings (then the most
    /// matched items) wins.
    static func compute(
        items: [BasketItemInput],
        records: [FlyerPriceRecord],
        entries: [PriceEntry],
        now: Date = .now
    ) -> FlyerDealAdvisory? {
        let activeRecords = records.filter { !$0.isExpired(asOf: now) }
        guard !activeRecords.isEmpty, !items.isEmpty else { return nil }

        // Distinct items by normalized key — the same de-dup rule as the basket builder.
        var seenKeys = Set<String>()
        let distinctKeys = items.compactMap { item -> String? in
            let key = ItemKeyNormalizer.normalize(item.itemKey)
            guard !key.isEmpty, seenKeys.insert(key).inserted else { return nil }
            return key
        }

        struct BannerTally {
            var matchedKeys = Set<String>()
            var savings = Decimal.zero
            var hasBaseline = false
        }
        var tallies: [String: BannerTally] = [:]

        for key in distinctKeys {
            let matching = activeRecords.filter {
                ItemKeyNormalizer.matches(queryKey: key, entryKey: $0.normalizedItemKey, entryHeadNoun: $0.enrichedHeadNoun)
            }
            guard !matching.isEmpty else { continue }

            // Cheapest captured package price at any store — the honest baseline.
            let baseline = PriceInsightEngine.pricesByStore(
                itemKey: key,
                useNormalizedPricing: false,
                allEntries: entries,
                now: now
            ).values.map(\.price).min()

            for (banner, bannerRecords) in Dictionary(grouping: matching, by: \.bannerName) {
                guard let bestPrice = bannerRecords.map(\.priceValue).min() else { continue }
                var tally = tallies[banner, default: BannerTally()]
                tally.matchedKeys.insert(key)
                if let baseline {
                    tally.hasBaseline = true
                    if baseline > bestPrice {
                        tally.savings += baseline - bestPrice
                    }
                }
                tallies[banner] = tally
            }
        }

        guard let best = tallies.max(by: { lhs, rhs in
            if lhs.value.savings != rhs.value.savings {
                return lhs.value.savings < rhs.value.savings
            }
            if lhs.value.matchedKeys.count != rhs.value.matchedKeys.count {
                return lhs.value.matchedKeys.count < rhs.value.matchedKeys.count
            }
            // Deterministic final tie-break so the advisory doesn't flicker between banners.
            return lhs.key > rhs.key
        }) else { return nil }

        return FlyerDealAdvisory(
            bannerName: best.key,
            matchedItemCount: best.value.matchedKeys.count,
            estimatedSavings: best.value.hasBaseline && best.value.savings > 0 ? best.value.savings : nil
        )
    }
}
