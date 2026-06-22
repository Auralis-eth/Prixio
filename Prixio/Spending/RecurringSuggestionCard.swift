import SwiftUI

/// A conservative recurring-expense suggestion with confirm/dismiss actions. The app asks before
/// treating a pattern as recurring rather than deciding silently.
struct RecurringSuggestionCard: View {
    let suggestion: RecurringSuggestion
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(suggestion.cadence.displayName, systemImage: "repeat")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(CurrencyFormatter.shared.display(suggestion.averageAmount))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            Text("\(suggestion.displayLabel) · seen \(suggestion.occurrenceCount) times")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Confirm", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                Button("Dismiss", role: .cancel, action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
