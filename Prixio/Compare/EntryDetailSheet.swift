import SwiftData
import SwiftUI

struct EntryDetailSheet: View {
    /// The user-editable fields handed back to the caller, which owns persistence.
    struct EditedFields {
        let itemName: String
        let brand: String?
        let priceValue: Decimal
        let unit: UnitType
        let storeChainName: String?
        let storeLocationName: String?
    }

    let entry: PriceEntry
    let onSave: (EditedFields) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingImageViewer = false
    @State private var isShowingDeleteAlert = false

    @State private var isEditing = false
    @State private var editItemName = ""
    @State private var editBrand = ""
    @State private var editPriceText = ""
    @State private var editUnit: UnitType = .each
    @State private var editChainName = ""
    @State private var editLocationName = ""
    @State private var isShowingCustomChainAlert = false
    @State private var customChainText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    imageCard
                    if isEditing {
                        editorCard
                    } else {
                        metadataCard
                        breakdownCard
                    }
                }
                .padding(20)
            }
            .navigationTitle(isEditing ? "Edit Entry" : "Entry Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                        }
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Save", action: save)
                            .disabled(!canSave)
                    } else {
                        Button("Edit", action: beginEditing)
                        Button("Delete", role: .destructive) {
                            isShowingDeleteAlert = true
                        }
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
            .alert("Custom Chain", isPresented: $isShowingCustomChainAlert) {
                TextField("Store chain", text: $customChainText)
                    .textInputAutocapitalization(.words)
                Button("Set") {
                    let name = customChainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        editChainName = name
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a store chain that isn’t in the list.")
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
            if let brand = entry.brand, !brand.isEmpty {
                detailRow(label: "Brand", value: brand)
            }
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

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            editField("Item") {
                TextField("Item name", text: $editItemName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
            }

            editField("Brand") {
                TextField("Optional, e.g. PC, Compliments", text: $editBrand)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
            }

            editField("Price") {
                TextField("0.00", text: $editPriceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            editField("Unit") {
                Picker("Unit", selection: $editUnit) {
                    ForEach(UnitType.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.menu)
            }

            editField("Store Chain") {
                Menu {
                    ForEach(StoreCatalog.commonChains.map(\.name), id: \.self) { chain in
                        Button(chain) {
                            editChainName = chain == "Unknown" ? "" : chain
                        }
                    }
                    Button("Custom…") {
                        customChainText = ""
                        isShowingCustomChainAlert = true
                    }
                } label: {
                    HStack {
                        Text(editChainName.isEmpty ? "Unknown" : editChainName)
                            .foregroundStyle(editChainName.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            editField("Store Location") {
                TextField("Optional branch or store name", text: $editLocationName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func editField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
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

    private var parsedEditPrice: Decimal? {
        Decimal(string: editPriceText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        guard
            !editItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let parsedEditPrice,
            parsedEditPrice > 0
        else {
            return false
        }
        return true
    }

    private func beginEditing() {
        editItemName = entry.itemNameRaw
        editBrand = entry.brand ?? ""
        editPriceText = NSDecimalNumber(decimal: entry.priceValue).stringValue
        editUnit = entry.unitType
        editChainName = (entry.storeChainNameSnapshot == "Unknown" ? nil : entry.storeChainNameSnapshot) ?? ""
        editLocationName = entry.storeLocationNameSnapshot ?? ""
        isEditing = true
    }

    private func save() {
        guard let parsedEditPrice, canSave else {
            return
        }

        let trimmedBrand = editBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChain = editChainName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = editLocationName.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(
            EditedFields(
                itemName: editItemName,
                brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
                priceValue: parsedEditPrice,
                unit: editUnit,
                storeChainName: trimmedChain.isEmpty ? nil : trimmedChain,
                storeLocationName: trimmedLocation.isEmpty ? nil : trimmedLocation
            )
        )

        isEditing = false
    }
}
