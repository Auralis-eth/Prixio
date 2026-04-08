import SwiftUI

struct ScanNudgeSheet: View {
    let itemName: String
    let onScanNow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Scan today's price for \(itemName)?")
                    .font(.title3.weight(.semibold))

                Text("This item has stale or missing pricing data. Refreshing it now will improve future trip recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Scan now", action: onScanNow)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Keep It Fresh")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
