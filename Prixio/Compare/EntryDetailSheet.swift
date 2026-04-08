import SwiftData
import SwiftUI

struct EntryDetailSheet: View {
    let entry: PriceEntry
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingImageViewer = false
    @State private var isShowingDeleteAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    imageCard
                    metadataCard
                    breakdownCard
                }
                .padding(20)
            }
            .navigationTitle("Entry Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) {
                        isShowingDeleteAlert = true
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingImageViewer) {
                ImageViewer(image: previewImage)
            }
            .alert("Delete this entry?", isPresented: $isShowingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the saved price entry from Compare and Shopping List calculations.")
            }
        }
    }

    private var imageCard: some View {
        Button {
            if previewImage != nil {
                isShowingImageViewer = true
            }
        } label: {
            Group {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ContentUnavailableView("No Image", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailRow(label: "Item", value: entry.itemNameRaw)
            detailRow(label: "Store", value: entry.storeChainNameSnapshot ?? "Unknown")
            if let storeLocationName = entry.storeLocationNameSnapshot {
                detailRow(label: "Location", value: storeLocationName)
            }
            detailRow(label: "Captured", value: capturedDateLabel)
            detailRow(label: "Price", value: "\(CurrencyFormatter.shared.display(entry.priceValue))/\(entry.unitType.displayName)")
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var breakdownCard: some View {
        if let normalizedUnitPrice = entry.normalizedUnitPriceValue,
           let normalizedUnitType = entry.normalizedUnitType {
            VStack(alignment: .leading, spacing: 12) {
                Text("Normalization")
                    .font(.headline.weight(.semibold))
                Text(
                    "Captured as \(CurrencyFormatter.shared.display(entry.priceValue))/\(entry.unitType.displayName) -> \(CurrencyFormatter.shared.display(normalizedUnitPrice))/\(normalizedUnitType.displayName)"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    private var previewImage: UIImage? {
        guard !entry.photoAssetId.isEmpty else {
            return nil
        }
        return UIImage(contentsOfFile: entry.photoAssetId)
    }

    private var capturedDateLabel: String {
        let absolute = entry.capturedAt.formatted(date: .abbreviated, time: .shortened)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: entry.capturedAt, relativeTo: .now)
        return "\(absolute) (\(relative))"
    }
}
