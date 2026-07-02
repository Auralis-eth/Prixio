import SwiftData
import SwiftUI

/// A management surface for saved flyer prices (`FlyerPriceRecord`s): review every
/// deal the user saved from a flyer check, with full provenance, and delete ones
/// that are stale or unwanted. Reachable from the Flyer POC.
struct SavedFlyerPricesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FlyerPriceRecord.savedAt, order: .reverse) private var records: [FlyerPriceRecord]

    @State private var errorMessage: String?

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView(
                    "No saved flyer prices",
                    systemImage: "tray",
                    description: Text("Run a flyer check, match it to your list, and tap + on a deal to save it here.")
                )
            } else {
                Section {
                    ForEach(records) { record in
                        SavedFlyerPriceRow(record: record)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    Text("\(records.count) saved flyer price\(records.count == 1 ? "" : "s"). Swipe a row to delete. Advertised prices may differ from in-store.")
                }
            }
        }
        .navigationTitle("Saved Flyer Prices")
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        deleteAll()
                    } label: {
                        Text("Clear All")
                    }
                }
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func delete(_ record: FlyerPriceRecord) {
        do {
            try FlyerPriceRecordRepository(context: modelContext).delete(record)
        } catch {
            errorMessage = "Couldn’t delete this saved price. Please try again."
        }
    }

    private func deleteAll() {
        do {
            let repository = FlyerPriceRecordRepository(context: modelContext)
            for record in records {
                try repository.delete(record)
            }
        } catch {
            errorMessage = "Couldn’t clear saved prices. Please try again."
        }
    }
}

private struct SavedFlyerPriceRow: View {
    let record: FlyerPriceRecord

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.productName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(CurrencyFormatter.shared.display(record.priceValue))
                    .font(.subheadline.weight(.semibold))
                if let regular = record.regularPriceValue {
                    Text(CurrencyFormatter.shared.display(regular))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
            }

            HStack(spacing: 6) {
                Text(record.bannerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if record.isExpired() {
                    Text("Expired")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                if record.memberOnly {
                    Text("· member")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let end = record.saleEndDate {
                    Text("· until \(Self.dateFormatter.string(from: end))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                if let region = record.storeContext {
                    Text(region)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text("· conf \(Int(record.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("· saved \(Self.dateFormatter.string(from: record.savedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
