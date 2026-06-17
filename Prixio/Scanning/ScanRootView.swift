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

struct ScanRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationModel: AppNavigationModel
    @Query(sort: \PriceEntry.createdAt, order: .reverse) private var entries: [PriceEntry]

    @StateObject private var cameraController = CameraController()
    @StateObject private var sessionStore = ScanSessionStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var viewModel = ScanViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?

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

            Text("Point at the price tag.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.74))
                .accessibilityIdentifier("scannerPrompt")
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

                Button(action: capturePhoto) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 84, height: 84)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 64, height: 64)
                    }
                }
                .accessibilityLabel("Shutter button")

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
