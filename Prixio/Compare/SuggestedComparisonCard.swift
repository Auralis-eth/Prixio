import SwiftUI

struct SuggestedComparisonCard: View {
    let card: CompareViewModel.SuggestedComparisonCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.displayName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text("Tracked at \(card.storeCount) stores")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(relativeDateLabel(for: card.latestCapturedAt))
                .font(.caption.weight(.medium))
                .foregroundStyle(.teal)
        }
        .frame(width: 190, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.97, blue: 0.94),
                            Color(red: 0.86, green: 0.92, blue: 0.89)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func relativeDateLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: .now))"
    }
}
