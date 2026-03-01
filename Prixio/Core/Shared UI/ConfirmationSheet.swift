//
//  ConfirmationSheet.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import SwiftUI

struct ConfirmationSheet: View {
    @Binding var draft: PriceEntryDraft

    let capturedImage: UIImage?
    let recentItems: [String]
    let onPriceCandidateTap: (PriceCandidate) -> Void
    let onSelectSuggestion: (String) -> Void
    let onOpenStoreSelection: () -> Void
    let onRetake: () -> Void
    let onDiscard: () -> Void
    let onSave: () -> Void

    @State private var isShowingImageViewer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Button {
                        isShowingImageViewer = true
                    } label: {
                        Group {
                            if let capturedImage {
                                Image(uiImage: capturedImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.gray.opacity(0.12))
                            }
                        }
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Captured image, tap to view full size")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirm details")
                            .font(.title3.weight(.semibold))
                        Text("Just now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldTitle("Item Name")
                    TextField("e.g., Yellow onions", text: $draft.itemName)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    if !recentItems.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentItems, id: \.self) { item in
                                    Button(item) {
                                        onSelectSuggestion(item)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldTitle("Price")
                    TextField("0.00", text: $draft.priceText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Price, editable")

                    if !draft.priceCandidates.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(draft.priceCandidates) { candidate in
                                Button(candidate.label) {
                                    onPriceCandidateTap(candidate)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.teal)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldTitle("Unit")

                    Picker("Unit", selection: Binding(get: {
                        draft.selectedUnit ?? .each
                    }, set: { newValue in
                        draft.selectedUnit = newValue
                    })) {
                        Text("Each").tag(UnitType.each)
                        Text("lb").tag(UnitType.lb)
                        Text("kg").tag(UnitType.kg)
                    }
                    .pickerStyle(.segmented)
                    .overlay {
                        if draft.selectedUnit == nil {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.orange, lineWidth: 2)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    fieldTitle("Store Chain")

                    Menu {
                        ForEach(StoreCatalog.commonChains.map(\.name), id: \.self) { chain in
                            Button(chain) {
                                draft.storeChainName = chain
                                draft.storeChainExplicitlySelected = true
                            }
                        }
                    } label: {
                        HStack {
                            Text(draft.storeChainName ?? "Choose chain")
                                .foregroundStyle(draft.storeChainName == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if !draft.storeChainExplicitlySelected {
                        Text("Confirm the detected store before saving.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                    }

                    fieldTitle("Store Location")

                    Button(action: onOpenStoreSelection) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.storeLocationName.isEmpty ? "Choose branch or nearby store" : draft.storeLocationName)
                                    .foregroundStyle(draft.storeLocationName.isEmpty ? .secondary : .primary)
                                if !draft.storeAddress.isEmpty {
                                    Text(draft.storeAddress)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "location.magnifyingglass")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                HStack(spacing: 12) {
                    Button("Retake", action: onRetake)
                        .buttonStyle(.bordered)

                    Button("Discard", role: .destructive, action: onDiscard)
                        .buttonStyle(.bordered)

                    Spacer()

                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.canSave)
                }
            }
            .padding(20)
        }
        .fullScreenCover(isPresented: $isShowingImageViewer) {
            ImageViewer(image: capturedImage)
        }
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
