import SwiftUI

struct TripOptimizerCard: View {
    let recommendation: TripRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best store for this trip")
                .font(.headline.weight(.semibold))

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
}
