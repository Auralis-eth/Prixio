import SwiftUI

struct ShoppingListRowView: View {
    let row: ShoppingListRowData
    let onToggleDone: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleDone) {
                Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: onOpenDetail) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let quantityNote = row.quantityNote, !quantityNote.isEmpty {
                        Text(quantityNote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if let bestStoreName = row.bestStoreName,
                           let bestPriceText = row.bestPriceText {
                            Text("\(bestStoreName) · \(bestPriceText)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.teal)
                        } else {
                            Text("No known price yet")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if let ageText = row.ageText {
                            Text(ageText)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(badgeColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(badgeColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(contentOpacity)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private var badgeColor: Color {
        switch row.stalenessBucket {
        case .fresh:
            return .green
        case .aging:
            return .secondary
        case .stale:
            return .orange
        case .veryStale:
            return .orange
        case nil:
            return .secondary
        }
    }

    private var contentOpacity: Double {
        switch row.stalenessBucket {
        case .fresh:
            return 1
        case .aging:
            return 0.82
        case .stale:
            return 0.68
        case .veryStale:
            return 0.5
        case nil:
            return 1
        }
    }
}
