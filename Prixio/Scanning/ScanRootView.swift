//
//  ScanRootView.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ScanRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationModel: AppNavigationModel
    @Query(sort: \PriceEntry.createdAt, order: .reverse) private var entries: [PriceEntry]

    @StateObject private var cameraController = CameraController()
    @StateObject private var sessionStore = ScanSessionStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var viewModel = ScanViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?

    /// Set when persisting swipe-dismissed receipt edits fails, surfaced as an alert so the user's
    /// corrections aren't silently lost.
    @State private var receiptDraftSaveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                scannerBackground

                VStack(spacing: 0) {
                    topHUD
                    Spacer()
                    bottomHUD
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if viewModel.showToast {
                    VStack {
                        ToastView(text: viewModel.toastMessage)
                        Spacer()
                    }
                    .padding(.top, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
        }
        .onDisappear {
            extinguishTorch()
        }
        .task {
            viewModel.configureRecentItems(with: entries)
            try? PriceEntryRepository(context: modelContext).seedChainsIfNeeded()
            await cameraController.prepare()
            locationManager.requestWhenInUseAuthorization()
            await viewModel.loadNearbyStoresIfNeeded(
                sessionStore: sessionStore,
                location: locationManager.currentLocation
            )
        }
        .onChange(of: entries.count) { _, _ in
            viewModel.configureRecentItems(with: entries)
        }
        .onChange(of: locationManager.currentLocation) { _, location in
            Task {
                await viewModel.loadNearbyStoresIfNeeded(
                    sessionStore: sessionStore,
                    location: location
                )
            }
        }
        .photosPicker(
            isPresented: $viewModel.isShowingImagePicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .fileImporter(
            isPresented: $viewModel.isShowingPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            Task {
                await handlePDFImport(result)
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                await handleSelectedPhotoItem(item)
            }
        }
        .onChange(of: navigationModel.pendingScanLaunchRequest) { _, request in
            applyPendingScanLaunchRequest(request)
        }
        .sheet(isPresented: $viewModel.isShowingConfirmationSheet, onDismiss: {
            viewModel.handleConfirmationSheetDismissed()
            extinguishTorch()
            Task {
                await cameraController.resumePreview()
            }
        }) {
            ConfirmationSheet(
                draft: $viewModel.draft,
                isProcessingOCR: viewModel.isProcessingOCR,
                capturedImage: viewModel.capturedImage,
                recentItems: viewModel.recentItems,
                priceMemory: priceMemoryInsight,
                storeMemory: storeMemoryInsight,
                onPriceCandidateTap: viewModel.applyPriceCandidate,
                onSelectSuggestion: viewModel.applyItemSuggestion,
                onOpenStoreSelection: { viewModel.isShowingStoreSheet = true },
                onRetake: {
                    viewModel.dismissConfirmationForRetake()
                    extinguishTorch()
                    Task {
                        await cameraController.resumePreview()
                    }
                },
                onDiscard: {
                    viewModel.discardCapture()
                    extinguishTorch()
                },
                onSavePhotoReference: {
                    await viewModel.saveCurrentImageToPhotoLibrary()
                },
                onSave: {
                    viewModel.save(context: modelContext)
                    extinguishTorch()
                    Task {
                        await cameraController.resumePreview()
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(viewModel.isProcessingOCR)
        }
        .sheet(item: $viewModel.receiptUnderReview, onDismiss: {
            // A swipe-to-dismiss bypasses the Save Draft / Done buttons; persist in-flight edits as a
            // draft so the user's corrections aren't silently lost. Save Draft / Done / Discard have
            // already persisted (or deleted) by the time this fires, leaving the context clean — so the
            // `hasChanges` guard makes this a true no-op for them and only saves when the swipe actually
            // left unsaved edits behind, rather than redundantly re-committing the whole context.
            guard modelContext.hasChanges else { return }
            do {
                try modelContext.save()
            } catch {
                // Roll back the unsaved edits so the context isn't left in a half-applied state, and
                // tell the user rather than swallowing the failure.
                modelContext.rollback()
                receiptDraftSaveError = "Couldn’t save your receipt edits. Open the receipt from the Spending tab to review it again."
            }
        }) { capture in
            ReceiptReviewView(
                viewModel: ReceiptReviewViewModel(capture: capture, context: modelContext),
                onClose: { viewModel.receiptUnderReview = nil }
            )
        }
        .sheet(isPresented: $viewModel.isShowingStoreSheet) {
            StoreSelectionSheet(
                nearbyCandidates: sessionStore.nearbyCandidates,
                currentLocation: locationManager.currentLocation,
                selectedChainName: viewModel.draft.storeChainName,
                selectedLocationName: viewModel.draft.storeLocationName,
                onSelectCandidate: { candidate in
                    viewModel.applyStoreCandidate(candidate)
                    sessionStore.useLastStore(candidate)
                },
                onSelectChain: viewModel.applyChainSelection,
                onSearch: { query in
                    await viewModel.searchStores(
                        query: query,
                        currentLocation: locationManager.currentLocation
                    )
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(
            "Couldn’t Save",
            isPresented: Binding(
                get: { receiptDraftSaveError != nil },
                set: { if !$0 { receiptDraftSaveError = nil } }
            ),
            presenting: receiptDraftSaveError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // Recomputed reactively as the user edits the draft, so the "usual price" read always reflects
    // the current item name, price, and unit. Stays silent until those fields are usable.
    private var priceMemoryInsight: PriceMemoryInsight? {
        guard
            !viewModel.isProcessingOCR,
            let price = viewModel.draft.parsedPrice,
            price > 0,
            let unit = viewModel.draft.selectedUnit,
            !viewModel.draft.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return PriceInsightEngine.computePriceMemory(
            itemName: viewModel.draft.itemName,
            currentPrice: price,
            unitType: unit,
            allEntries: entries
        )
    }

    // Store-relative read for the matched item: is the selected store usually cheaper, average, or
    // pricier than other stores? Stays silent until the item, unit, and a chosen store are usable.
    private var storeMemoryInsight: StoreMemoryInsight? {
        guard
            !viewModel.isProcessingOCR,
            let unit = viewModel.draft.selectedUnit,
            !viewModel.draft.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let storeName = viewModel.draft.storeChainName,
            !storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return PriceInsightEngine.computeStoreMemory(
            itemName: viewModel.draft.itemName,
            currentStoreName: storeName,
            unitType: unit,
            allEntries: entries
        )
    }

    private var scannerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.20, blue: 0.16),
                    Color(red: 0.06, green: 0.08, blue: 0.09),
                    Color(red: 0.14, green: 0.11, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let image = viewModel.displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay {
                        Rectangle()
                            .fill(.black.opacity(0.28))
                            .ignoresSafeArea()
                    }
            } else {
                if cameraController.authorizationStatus == .authorized {
                    CameraPreviewView(session: cameraController.session)
                        .id(viewModel.cameraPreviewRefreshID)
                        .ignoresSafeArea()
                        .overlay {
                            Rectangle()
                                .fill(.black.opacity(0.18))
                                .ignoresSafeArea()
                        }
                    ScannerGuideOverlay()
                } else {
                    CameraUnavailableOverlay(
                        authorizationStatus: cameraController.authorizationStatus,
                        onImportPhoto: viewModel.openPhotoLibraryFallback
                    )
                }
            }
        }
    }

    private var topHUD: some View {
        VStack(spacing: 14) {
            Picker("Capture mode", selection: $viewModel.scanMode) {
                ForEach(ScanMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .accessibilityIdentifier("scanModePicker")

            HStack {
                Spacer()
                Button(action: {
                    viewModel.isShowingStoreSheet = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.storeChipTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(viewModel.storeChipSubtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel("Detected store: \(viewModel.storeChipTitle), editable")
                Spacer()
            }

            Text(viewModel.scanMode.capturePrompt)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.74))
                .accessibilityIdentifier("scannerPrompt")

            if viewModel.scanMode == .receipt {
                Button {
                    viewModel.presentPDFImporter()
                } label: {
                    Label("Import PDF from Files", systemImage: "doc.badge.plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityIdentifier("importReceiptPDFButton")
            }
        }
    }

    private var bottomHUD: some View {
        VStack(spacing: 16) {
            if viewModel.isProcessingOCR {
                ProgressView("Extracting details")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.4), in: Capsule())
            }

            HStack(alignment: .center) {
                Button(action: toggleTorch) {
                    Image(systemName: cameraController.isTorchEnabled ? "bolt.fill" : "bolt.slash")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(!cameraController.isTorchAvailable)
                .opacity(cameraController.isTorchAvailable ? 1 : 0.4)
                .accessibilityLabel("Flash toggle")

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                }
                .contentShape(Circle())
                // Tap captures in the current mode; a long press is a convenience shortcut into
                // Receipt mode. Using distinct gestures (rather than a Button + simultaneous long
                // press) keeps the long press from also triggering a capture on release.
                .onTapGesture {
                    capturePhoto()
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    viewModel.switchToReceiptModeViaShortcut()
                }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Shutter button")
                .accessibilityHint("Captures using the current mode")
                .accessibilityAction {
                    capturePhoto()
                }
                .accessibilityAction(named: "Switch to Receipt Mode") {
                    viewModel.switchToReceiptModeViaShortcut()
                }

                Spacer()

                Button(action: {
                    extinguishTorch()
                    viewModel.openPhotoLibraryFallback()
                }) {
                    Group {
                        if let image = viewModel.capturedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.16))
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    
                }
                .accessibilityLabel("Gallery or last photo")
            }

            if let lastEntry = entries.first {
                HStack {
                    Text("Last save")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))

                    Spacer()

                    Text("\(lastEntry.itemNameRaw) • \(CurrencyFormatter.shared.display(lastEntry.priceValue)) / \(lastEntry.unitType.displayName)")
                        .font(.caption)
                       .foregroundStyle(.white.opacity(0.84))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.28), in: Capsule())
            }
        }
    }

    private func capturePhoto() {
        guard cameraController.authorizationStatus == .authorized else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }

        Haptics.impact()
        Task {
            let image = try? await cameraController.capturePhoto(flashEnabled: viewModel.isFlashEnabled)
            // The still flash (if enabled) has already fired during capture; the live preview is
            // about to be replaced by the captured image and confirmation sheet, so the torch must
            // not stay lit.
            viewModel.isFlashEnabled = false
            await cameraController.setTorch(false)
            if let image {
                await viewModel.processPickedImage(
                    image,
                    sessionStore: sessionStore,
                    currentLocation: locationManager.currentLocation,
                    modelContext: modelContext,
                    source: .camera
                )
            }
        }
    }

    private func handleSelectedPhotoItem(_ item: PhotosPickerItem?) async {
        defer {
            selectedPhotoItem = nil
        }

        guard
            let item,
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            return
        }

        // Reviewing a library image replaces the live preview, so the torch must not stay lit.
        viewModel.isFlashEnabled = false
        await cameraController.setTorch(false)

        await viewModel.processPickedImage(
            image,
            sessionStore: sessionStore,
            currentLocation: locationManager.currentLocation,
            modelContext: modelContext,
            source: .photoLibrary
        )
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) async {
        let urls: [URL]
        switch result {
        case .success(let value):
            urls = value
        case .failure:
            viewModel.reportReceiptImportFailure()
            return
        }
        guard let url = urls.first else {
            // The picker reported success with no file (e.g. cancelled); nothing to report.
            return
        }

        // Imported files arrive as security-scoped URLs; access must be opened before reading.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            viewModel.reportReceiptImportFailure("That PDF could not be read.")
            return
        }

        await viewModel.ingestReceiptPDF(data: data, modelContext: modelContext)
    }

    private func applyPendingScanLaunchRequest(_ request: ScanLaunchRequest?) {
        guard request != nil, let consumedRequest = navigationModel.consumePendingScanLaunchRequest() else {
            return
        }

        viewModel.applyLaunchRequest(consumedRequest)
    }

    private func toggleTorch() {
        viewModel.toggleFlash()
        Task { await cameraController.setTorch(viewModel.isFlashEnabled) }
    }

    private func extinguishTorch() {
        viewModel.isFlashEnabled = false
        Task { await cameraController.setTorch(false) }
    }
}
