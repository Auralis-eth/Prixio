import SwiftUI

struct TripOptimizerCard: View {
    let recommendation: TripRecommendation
    var basket: BasketEstimate = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best store for this trip")
                .font(.headline.weight(.semibold))

            recommendationContent

            if basket.hasAnyPrices {
                Divider()
                    .padding(.vertical, 2)
                basketContent
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.94, green: 0.96, blue: 0.92),
                            Color(red: 0.84, green: 0.91, blue: 0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    @ViewBuilder
    private var recommendationContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch recommendation {
            case .insufficientData:
                Text("Not enough price data yet.")
                    .font(.title3.weight(.semibold))
                Text("Scan a few more items to get a trip recommendation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .strongWinner(_, let chainName, let count, let total, let staleCount):
                Text("\(chainName) wins for \(count) of \(total) items")
                    .font(.title3.weight(.semibold))
                if staleCount > 0 {
                    Text("\(staleCount) items have older price data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .splitTrip(_, let primaryChainName, let primaryCount, _, let secondaryChainName, let secondaryCount, let staleCount):
                Text("No single best store")
                    .font(.title3.weight(.semibold))
                Text(
                    "\(primaryChainName) (\(primaryCount)) + \((secondaryChainName ?? "Another store")) (\(secondaryCount ?? 0))"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if staleCount > 0 {
                    Text("\(staleCount) items have older price data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var basketContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated basket")
                .font(.subheadline.weight(.semibold))

            if let cheapest = basket.cheapestSingleStore {
                let coversAll = cheapest.coversAllPricedItems
                HStack {
                    Text(cheapest.storeName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(CurrencyFormatter.shared.display(cheapest.knownTotal))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        // A partial total isn't a real basket total and isn't comparable to the
                        // split's combined total, so it's de-emphasized rather than shown as the
                        // headline figure.
                        .foregroundStyle(coversAll ? .primary : .secondary)
                }

                Text(coverageText(for: cheapest))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !coversAll {
                    Text("Partial total — no single store has every item")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let split = basket.split {
                let storeNames = split.stores.map(\.storeName).joined(separator: " + ")
                let detail = split.savingsVsSingle.map { "save \(CurrencyFormatter.shared.display($0))" }
                    ?? "only way to get everything priced"
                Text("Split \(storeNames): \(CurrencyFormatter.shared.display(split.combinedTotal)) — \(detail)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if !basket.unpricedItemNames.isEmpty {
                Text("No price yet for \(basket.unpricedItemNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(basket.substitutions.prefix(3).enumerated()), id: \.offset) { _, sub in
                Text("Cheaper option: \(sub.substituteItemName) at \(sub.substituteStoreName) — \(CurrencyFormatter.shared.display(sub.substitutePrice)) (save \(CurrencyFormatter.shared.display(sub.savings)) vs \(sub.originalItemName))")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func coverageText(for store: StoreBasketEstimate) -> String {
        var text = "\(store.knownItemCount) of \(basket.pricedItemCount) priced items"
        if !store.missingItems.isEmpty {
            text += " · missing \(store.missingItems.joined(separator: ", "))"
        }
        if store.staleCount > 0 {
            text += " · \(store.staleCount) older"
        }
        return text
    }
}
