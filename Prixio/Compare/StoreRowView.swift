import SwiftUI

struct StoreRowView: View {
    let row: StoreComparisonRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.displayStoreName)
                    .font(.headline.weight(.semibold))

                if let storeLocationName = row.storeLocationName, storeLocationName != row.displayStoreName {
                    Text(storeLocationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(stalenessLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(stalenessColor)

                if let distanceMeters = row.distanceMeters {
                    Text(distanceMeters.formatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(CurrencyFormatter.shared.display(row.displayPrice))/\(row.displayUnit)")
                    .font(.headline.weight(.semibold))

                trendBadge
            }
        }
        .padding(.vertical, 8)
        .opacity(opacity)
    }

    private var stalenessLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        switch row.stalenessBucket {
        case .fresh:
            return formatter.localizedString(for: row.capturedAt, relativeTo: .now)
        case .aging:
            return "Captured \(formatter.localizedString(for: row.capturedAt, relativeTo: .now))"
        case .stale:
            return "May be outdated"
        case .veryStale:
            return "Old price"
        }
    }

    private var stalenessColor: Color {
        switch row.stalenessBucket {
        case .fresh:
            return .secondary
        case .aging:
            return .secondary
        case .stale:
            return .orange
        case .veryStale:
            return .orange
        }
    }

    private var opacity: Double {
        switch row.stalenessBucket {
        case .fresh:
            return 1
        case .aging:
            return 0.78
        case .stale:
            return 0.6
        case .veryStale:
            return 0.4
        }
    }

    @ViewBuilder
    private var trendBadge: some View {
        switch row.trendDirection {
        case .up(let percent):
            Text("↑ \(percent)%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        case .down(let percent):
            Text("↓ \(percent)%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .flat:
            Text("—")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("—")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
