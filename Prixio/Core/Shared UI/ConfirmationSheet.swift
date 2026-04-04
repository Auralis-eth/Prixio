//
//  ConfirmationSheet.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import SwiftUI

struct ConfirmationSheet: View {
    @Binding var draft: PriceEntryDraft

    let isProcessingOCR: Bool
    let capturedImage: UIImage?
    let recentItems: [String]
    let onPriceCandidateTap: (PriceCandidate) -> Void
    let onSelectSuggestion: (String) -> Void
    let onOpenStoreSelection: () -> Void
    let onRetake: () -> Void
    let onDiscard: () -> Void
    let onSavePhotoReference: () async -> String
    let onSave: () -> Void

    @State private var isShowingImageViewer = false
    @State private var isShowingSaveReviewAlert = false
    @State private var isSavingPhotoReference = false
    @State private var photoSaveMessage: String?
    @State private var isShowingPhotoSaveAlert = false

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

                    Spacer()

                    Button {
                        handleSavePhotoReferenceTap()
                    } label: {
                        if isSavingPhotoReference {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Save Photo", systemImage: "square.and.arrow.down")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(capturedImage == nil || isSavingPhotoReference)
                    .accessibilityLabel("Save scan image to Photos")
                }

                reviewCard

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

                    if let priceReviewMessage {
                        Text(priceReviewMessage)
                            .font(.footnote)
                            .foregroundStyle(priceReviewTone)
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

                    Button("Save", action: handleSaveTap)
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.canSave)
                }
            }
            .padding(20)
        }
        .fullScreenCover(isPresented: $isShowingImageViewer) {
            ImageViewer(image: capturedImage)
        }
        .alert("Review before saving", isPresented: $isShowingSaveReviewAlert) {
            Button("Save Anyway", role: .destructive, action: onSave)
            Button("Keep Reviewing", role: .cancel) {}
        } message: {
            Text(draft.review.summary)
        }
        .alert("Save Photo", isPresented: $isShowingPhotoSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoSaveMessage ?? "Finished saving the photo.")
        }
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var reviewCard: some View {
        if isProcessingOCR {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analyzing shelf tag")
                        .font(.subheadline.weight(.semibold))
                    Text("OCR and price parsing are still filling in the draft.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: reviewIconName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(reviewTone)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.review.title)
                            .font(.subheadline.weight(.semibold))
                        Text(draft.review.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let confidenceText {
                    Text(confidenceText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if !draft.review.issues.isEmpty {
                    issueChips
                }

                if draft.review.usedFoundationModel {
                    Text("Foundation Models helped narrow this scan. Confirm the final fields before saving.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(reviewBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(reviewTone.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private var issueChips: some View {
        FlexibleChipLayout(items: draft.review.issues) { issue in
            Text(issue.shortLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(reviewTone)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(reviewTone.opacity(0.12), in: Capsule())
        }
    }

    private var confidenceText: String? {
        guard let confidence = draft.confidence else {
            return nil
        }
        let percent = Int((confidence * 100).rounded())
        return "Parser confidence: \(percent)%"
    }

    private var priceReviewMessage: String? {
        if draft.review.issues.contains(.possibleMultiProductScan) {
            return "This photo may contain more than one tag. Make sure the selected price matches the item above."
        }
        if draft.review.issues.contains(.multipleCompetingPrices) {
            return "Multiple price lines were detected. Choose the shelf price that belongs to this product."
        }
        if draft.priceCandidates.count > 1 {
            return "More than one likely price was found. Tap the best match if needed."
        }
        return nil
    }

    private var reviewTone: Color {
        switch draft.review.state {
        case .clean:
            return .green
        case .reviewRecommended:
            return .orange
        case .reviewRequired:
            return .red
        }
    }

    private var reviewBackground: Color {
        switch draft.review.state {
        case .clean:
            return Color.green.opacity(0.08)
        case .reviewRecommended:
            return Color.orange.opacity(0.10)
        case .reviewRequired:
            return Color.red.opacity(0.10)
        }
    }

    private var reviewIconName: String {
        switch draft.review.state {
        case .clean:
            return "checkmark.shield"
        case .reviewRecommended:
            return "exclamationmark.bubble"
        case .reviewRequired:
            return "exclamationmark.triangle"
        }
    }

    private var priceReviewTone: Color {
        draft.review.state == .reviewRequired ? .red : .orange
    }

    private func handleSaveTap() {
        if draft.review.requiresExplicitSaveConfirmation {
            isShowingSaveReviewAlert = true
            return
        }
        onSave()
    }

    private func handleSavePhotoReferenceTap() {
        guard !isSavingPhotoReference else {
            return
        }

        isSavingPhotoReference = true
        Task {
            let message = await onSavePhotoReference()
            await MainActor.run {
                photoSaveMessage = message
                isSavingPhotoReference = false
                isShowingPhotoSaveAlert = true
            }
        }
    }
}

private struct FlexibleChipLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    let content: (Data.Element) -> Content

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(chunkedItems.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { item in
                            content(item)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var chunkedItems: [[Data.Element]] {
        var rows: [[Data.Element]] = []
        var currentRow: [Data.Element] = []

        for item in items {
            currentRow.append(item)
            if currentRow.count == 2 {
                rows.append(currentRow)
                currentRow = []
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }
}
