//
//  BatchReviewView.swift
//  Prixio
//

import CoreLocation
import SwiftUI

/// Batch review surface for Quick (toddler) capture mode: the user scanned a run of tags without
/// reviewing each one, and now confirms or discards them one at a time from a single queue. Each row
/// opens the standard `ConfirmationSheet` editor so the same fields, validation, and store selection
/// apply as in the inline flow.
struct BatchReviewView: View {
    @ObservedObject var viewModel: ScanViewModel
    let recentItems: [String]
    let nearbyCandidates: [StoreCandidate]
    let currentLocation: CLLocation?
    let onClose: () -> Void
    let onSave: (UUID) -> Void
    let onSearchStores: (String) async -> [StoreCandidate]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.pendingCaptures.isEmpty {
                    ContentUnavailableView(
                        "All Caught Up",
                        systemImage: "checkmark.circle",
                        description: Text("No captures left to review.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(viewModel.pendingCaptures) { capture in
                                NavigationLink {
                                    BatchReviewDetailView(
                                        viewModel: viewModel,
                                        captureID: capture.id,
                                        recentItems: recentItems,
                                        nearbyCandidates: nearbyCandidates,
                                        currentLocation: currentLocation,
                                        onSave: onSave,
                                        onSearchStores: onSearchStores
                                    )
                                } label: {
                                    BatchReviewRow(capture: capture)
                                }
                            }
                            .onDelete { offsets in
                                let ids = offsets.map { viewModel.pendingCaptures[$0].id }
                                ids.forEach(viewModel.discardPending(id:))
                            }
                        } footer: {
                            Text("Tap a capture to confirm its details, or swipe to discard.")
                        }
                    }
                }
            }
            .navigationTitle("Review Captures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }
}

private struct BatchReviewRow: View {
    let capture: ScanViewModel.PendingCapture

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            status
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = capture.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.gray.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private var status: some View {
        if capture.isProcessing {
            ProgressView()
        } else if capture.draft.canSave {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Ready to save")
        } else {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityLabel("Needs details")
        }
    }

    private var title: String {
        let name = capture.draft.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        return capture.isProcessing ? "Reading tag…" : "Needs details"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let price = capture.draft.parsedPrice, price > 0 {
            let unit = capture.draft.selectedUnit.map { " / \($0.displayName)" } ?? ""
            parts.append("\(CurrencyFormatter.shared.display(price))\(unit)")
        }
        if let chain = capture.draft.storeChainName, !chain.isEmpty {
            parts.append(chain)
        }
        return parts.isEmpty ? "Tap to add a price and store" : parts.joined(separator: " · ")
    }
}

/// The per-capture editor. Reuses `ConfirmationSheet` against a binding into the queued draft, so
/// saving persists the price and removes it from the queue, and discarding drops it.
private struct BatchReviewDetailView: View {
    @ObservedObject var viewModel: ScanViewModel
    let captureID: UUID
    let recentItems: [String]
    let nearbyCandidates: [StoreCandidate]
    let currentLocation: CLLocation?
    let onSave: (UUID) -> Void
    let onSearchStores: (String) async -> [StoreCandidate]

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingStoreSheet = false

    private var capture: ScanViewModel.PendingCapture? {
        viewModel.pendingCaptures.first { $0.id == captureID }
    }

    var body: some View {
        Group {
            if let capture {
                ConfirmationSheet(
                    draft: viewModel.draftBinding(for: captureID),
                    isProcessingOCR: capture.isProcessing,
                    capturedImage: capture.image,
                    recentItems: recentItems,
                    priceMemory: nil,
                    storeMemory: nil,
                    onPriceCandidateTap: { candidate in
                        let binding = viewModel.draftBinding(for: captureID)
                        binding.wrappedValue.priceText = CurrencyFormatter.shared.string(candidate.value)
                        binding.wrappedValue.quantity = candidate.quantity
                    },
                    onSelectSuggestion: { suggestion in
                        viewModel.draftBinding(for: captureID).wrappedValue.itemName = suggestion
                    },
                    onOpenStoreSelection: { isShowingStoreSheet = true },
                    onRetake: { dismiss() },
                    onDiscard: {
                        viewModel.discardPending(id: captureID)
                        dismiss()
                    },
                    onSavePhotoReference: { "Saving reference photos isn’t available during batch review." },
                    onSave: {
                        onSave(captureID)
                        dismiss()
                    }
                )
                .sheet(isPresented: $isShowingStoreSheet) {
                    StoreSelectionSheet(
                        nearbyCandidates: nearbyCandidates,
                        currentLocation: currentLocation,
                        selectedChainName: capture.draft.storeChainName,
                        selectedLocationName: capture.draft.storeLocationName,
                        onSelectCandidate: { applyStoreCandidate($0) },
                        onSelectChain: { chain in
                            let binding = viewModel.draftBinding(for: captureID)
                            binding.wrappedValue.storeChainName = chain
                            binding.wrappedValue.storeChainExplicitlySelected = true
                        },
                        onSearch: { query in await onSearchStores(query) }
                    )
                    .presentationDetents([.medium, .large])
                }
            } else {
                // The capture was saved or discarded out from under this screen; pop back.
                Color.clear
                    .onAppear { dismiss() }
            }
        }
        .navigationTitle("Confirm Capture")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func applyStoreCandidate(_ candidate: StoreCandidate) {
        let binding = viewModel.draftBinding(for: captureID)
        var draft = binding.wrappedValue
        draft.storeChainName = candidate.chainName ?? draft.storeChainName ?? "Unknown"
        draft.storeChainExplicitlySelected = true
        draft.storeLocationName = candidate.locationName
        draft.storeAddress = candidate.address ?? ""
        draft.storeCoordinate = candidate.coordinate
        draft.storePlaceId = candidate.mapKitPlaceId
        binding.wrappedValue = draft
        isShowingStoreSheet = false
    }
}
