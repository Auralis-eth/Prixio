//
//  ScanViewModel.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation
import FoundationModels
import Photos
import SwiftData
import SwiftUI
import UIKit

import Combine
@MainActor
final class ScanViewModel: ObservableObject {
    enum ScanInputSource: Equatable {
        case camera
        case photoLibrary
    }

    @Published var draft = PriceEntryDraft()
    @Published var isShowingImagePicker = false
    @Published var isShowingConfirmationSheet = false
    @Published var isShowingStoreSheet = false
    @Published var isProcessingOCR = false
    @Published var capturedImage: UIImage?
    @Published var previewImage: UIImage?
    @Published var isFlashEnabled = false
    @Published var showToast = false
    @Published var toastMessage = "Price saved"
    @Published var recentItems: [String] = []
    @Published var searchResults: [StoreCandidate] = []
    @Published private(set) var cameraPreviewRefreshID = UUID()

    private let imageExtractor: any PriceImageExtracting
    private let storeService: any StoreLookupProviding
    private(set) var currentScanSource: ScanInputSource?

    init() {
        self.imageExtractor = DefaultPriceImageExtractor()
        self.storeService = StoreDetectionService()
    }

    init(
        imageExtractor: any PriceImageExtracting,
        storeService: any StoreLookupProviding
    ) {
        self.imageExtractor = imageExtractor
        self.storeService = storeService
    }

    var displayImage: UIImage? {
        guard isShowingConfirmationSheet || isProcessingOCR else {
            return nil
        }
        return previewImage ?? capturedImage
    }

    var storeChipTitle: String {
        guard let candidate = candidatePreview else {
            return "Store unknown"
        }

        if let chainName = candidate.chainName {
            return chainName
        }

        return candidate.locationName
    }

    var storeChipSubtitle: String {
        guard let candidate = candidatePreview else {
            return "Tap to choose manually"
        }

        if let distanceMeters = candidate.distanceMeters {
            return "\(candidate.locationName) · \(distanceMeters.formatted)"
        }

        return candidate.locationName
    }

    private var candidatePreview: StoreCandidate? {
        if !draft.storeLocationName.isEmpty || draft.storeChainName != nil {
            return StoreCandidate(
                id: UUID().uuidString,
                chainName: draft.storeChainName,
                locationName: draft.storeLocationName.isEmpty ? "Detected store" : draft.storeLocationName,
                address: draft.storeAddress,
                coordinate: draft.storeCoordinate,
                distanceMeters: nil,
                mapKitPlaceId: draft.storePlaceId
            )
        }
        return inferredStoreCandidate
    }

    private var inferredStoreCandidate: StoreCandidate?
    private var activeScanID: UUID?

    // A shopping-driven launch request can prefill the item and preferred chain before capture.
    // These survive the draft resets in beginImageReview/PriceDraftBuilder so the scan can bias
    // extraction toward the requested item and keep the user's explicit chain selection.
    private var pendingExpectedItemName: String?
    private var pendingPreferredChainName: String?

    func configureRecentItems(with entries: [PriceEntry]) {
        recentItems = Array(
            entries
                .map(\.itemNameRaw)
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { result, name in
                    if !result.contains(name) {
                        result.append(name)
                    }
                }
                .prefix(6)
        )
    }

    func loadNearbyStoresIfNeeded(sessionStore: ScanSessionStore, location: CLLocation?) async {
        if let cached = sessionStore.cachedCandidatesIfFresh(), !cached.isEmpty {
            inferredStoreCandidate = cached.first
            return
        }

        let stores = await storeService.fetchNearbyStores(location: location)
        sessionStore.updateCandidates(stores)
        inferredStoreCandidate = stores.first
    }

    func searchStores(query: String, currentLocation: CLLocation?) async -> [StoreCandidate] {
        let results = await storeService.search(query: query, near: currentLocation)
        searchResults = results
        return results
    }

    func openPhotoLibraryFallback() {
        Haptics.impact()
        isShowingImagePicker = true
    }

    func applyLaunchRequest(_ request: ScanLaunchRequest) {
        guard !isShowingConfirmationSheet, !isProcessingOCR else {
            return
        }

        draft.itemName = request.itemName
        pendingExpectedItemName = request.itemName.isEmpty ? nil : request.itemName

        if let preferredChainName = request.preferredChainName {
            draft.storeChainName = preferredChainName
            draft.storeChainExplicitlySelected = true
            pendingPreferredChainName = preferredChainName
        }
    }

    func toggleFlash() {
        isFlashEnabled.toggle()
    }

    func processPickedImage(
        _ image: UIImage?,
        sessionStore: ScanSessionStore,
        currentLocation: CLLocation?,
        modelContext: ModelContext,
        source: ScanInputSource = .photoLibrary
    ) async {
        guard let image else {
            return
        }

        let scanID = UUID()
        activeScanID = scanID
        beginImageReview(image, source: source)

        let extractionOutcome = await imageExtractor.extractPriceInformation(
            from: image,
            context: ScanPromptContext(
                storeName: sessionStore.lastStoreCandidate?.chainName,
                expectedItemName: pendingExpectedItemName
            ),
            tools: captureTools(sessionStore: sessionStore, currentLocation: currentLocation, modelContext: modelContext)
        )
        guard activeScanID == scanID else {
            return
        }

        let result: LLMOCRResult
        switch extractionOutcome {
        case .success(let extractedResult):
            result = extractedResult
        case .failure(let failure):
            toastMessage = failure.userMessage
            showToast = true
            isProcessingOCR = false
            return
        }

        draft = PriceDraftBuilder.makeDraft(from: result, image: capturedImage)

        // Fall back to the requested item name only when the model could not read one;
        // a name the model extracted from the tag is preferred over the shopper's query.
        if draft.itemName.isEmpty, let pendingExpectedItemName {
            draft.itemName = pendingExpectedItemName
        }

        if sessionStore.nearbyCandidates.isEmpty {
            let stores = await storeService.fetchNearbyStores(location: currentLocation)
            guard activeScanID == scanID else {
                return
            }
            sessionStore.updateCandidates(stores)
        }

        let isReceipt = ReceiptCaptureClassifier.isReceiptOrInvalid(result)
        let matched = matchStoreCandidate(
            from: sessionStore.nearbyCandidates,
            ocrText: result.relevantText,
            currentLocation: currentLocation
        )
        inferredStoreCandidate = isReceipt ? nil : (matched ?? sessionStore.lastStoreCandidate)
        applyInferredStore(from: inferredStoreCandidate, ocrText: result.relevantText, nearbyCandidates: sessionStore.nearbyCandidates)

        // An explicit chain from the shopping list wins over store inference (which may have
        // overwritten it above with a nearby chain).
        if let pendingPreferredChainName {
            draft.storeChainName = pendingPreferredChainName
            draft.storeChainExplicitlySelected = true
        }
        isProcessingOCR = false
    }

    /// The model-callable tools registered on the Capture extraction session. The model may
    /// call these while reading the photo to normalise unit prices, resolve units/quantities,
    /// infer store context, and ground a price against saved history.
    private func captureTools(
        sessionStore: ScanSessionStore,
        currentLocation: CLLocation?,
        modelContext: ModelContext
    ) -> [any Tool] {
        [
            NormalizeUnitPriceTool(),
            ResolveUnitAndQuantityTool(),
            InferStoreContextTool(
                service: storeService,
                location: currentLocation,
                nearbyCandidates: sessionStore.nearbyCandidates,
                lastStoreCandidate: sessionStore.lastStoreCandidate
            ),
            ItemHistoryTool(repository: PriceEntryRepository(context: modelContext))
        ]
    }

    func applyPriceCandidate(_ candidate: PriceCandidate) {
        draft.priceText = CurrencyFormatter.shared.string(candidate.value)
        draft.quantity = candidate.quantity
    }

    func applyItemSuggestion(_ suggestion: String) {
        draft.itemName = suggestion
    }

    func applyStoreCandidate(_ candidate: StoreCandidate) {
        draft.storeChainName = candidate.chainName ?? draft.storeChainName ?? "Unknown"
        draft.storeChainExplicitlySelected = true
        draft.storeLocationName = candidate.locationName
        draft.storeAddress = candidate.address ?? ""
        draft.storeCoordinate = candidate.coordinate
        draft.storePlaceId = candidate.mapKitPlaceId
        isShowingStoreSheet = false
    }

    func applyChainSelection(_ chainName: String) {
        draft.storeChainName = chainName
        draft.storeChainExplicitlySelected = true
    }

    func dismissConfirmationForRetake() {
        resetCaptureState()
    }

    func discardCapture() {
        resetCaptureState()
    }

    func handleConfirmationSheetDismissed() {
        guard !isShowingConfirmationSheet else {
            return
        }

        if capturedImage != nil || previewImage != nil || activeScanID != nil {
            resetCaptureState()
        }
    }

    func beginImageReview(_ image: UIImage, source: ScanInputSource) {
        // The torch is extinguished by the capture flow once review begins; clear the still-capture
        // preference so the flash button (bound to real torch state) and the next capture start off.
        isFlashEnabled = false
        currentScanSource = source
        previewImage = image
        capturedImage = image
        draft = PriceEntryDraft(
            capturedAt: .now,
            imageData: image.jpegData(compressionQuality: 0.88)
        )
        isProcessingOCR = true
        isShowingConfirmationSheet = true
    }

    func saveCurrentImageToPhotoLibrary() async -> String {
        guard let image = capturedImage ?? previewImage else {
            return "No scan image is available to save."
        }

        let authorizationStatus = await resolvedPhotoLibraryAuthorizationStatus()
        switch authorizationStatus {
        case .authorized, .limited:
            break
        case .denied, .restricted:
            return "Photo Library access is denied. Enable add access in Settings to save reference photos."
        case .notDetermined:
            return "Photo Library permission was not resolved."
        @unknown default:
            return "Photo Library access is unavailable right now."
        }

        do {
            try await saveImageToPhotoLibrary(image)
            return "Saved this scan image to Photos."
        } catch {
            return "Could not save the image to Photos."
        }
    }

    func save(context: ModelContext) {
        guard draft.canSave else {
            return
        }

        do {
            try PriceEntryRepository(context: context).saveEntry(from: draft)
            Haptics.success()
            withAnimation(.easeOut(duration: 0.2)) {
                toastMessage = "Price saved"
                showToast = true
            }
            discardCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                withAnimation(.easeIn(duration: 0.2)) {
                    self?.showToast = false
                }
            }
        } catch {
            isShowingConfirmationSheet = true
        }
    }

    // Widened from `private` to internal so the store-matching logic can be unit-tested directly.
    func applyInferredStore(from candidate: StoreCandidate?, ocrText: String, nearbyCandidates: [StoreCandidate]) {
        guard let candidate else {
            return
        }

        guard shouldAutoApplyStore(candidate: candidate, ocrText: ocrText, nearbyCandidates: nearbyCandidates) else {
            return
        }

        if draft.storeChainName == nil {
            draft.storeChainName = candidate.chainName
        }
        if draft.storeLocationName.isEmpty {
            draft.storeLocationName = candidate.locationName
        }
        if draft.storeAddress.isEmpty {
            draft.storeAddress = candidate.address ?? ""
        }
        if draft.storeCoordinate == nil {
            draft.storeCoordinate = candidate.coordinate
        }
        if draft.storePlaceId == nil {
            draft.storePlaceId = candidate.mapKitPlaceId
        }
        draft.storeChainExplicitlySelected = false
    }

    func matchStoreCandidate(
        from candidates: [StoreCandidate],
        ocrText: String,
        currentLocation: CLLocation?
    ) -> StoreCandidate? {
        if PriceParsingService.looksLikeReceipt(text: ocrText) {
            return nil
        }

        let inferredChain = StoreCatalog.inferredChain(from: ocrText)
        let matched = candidates.first { candidate in
            candidate.chainName == inferredChain
        } ?? candidates.first
        guard let matched else {
            return nil
        }

        if let currentLocation,
           let coordinate = matched.coordinate,
           CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: currentLocation) > 1_500 {
            return nil
        }

        return matched
    }

    func shouldAutoApplyStore(
        candidate: StoreCandidate,
        ocrText: String,
        nearbyCandidates: [StoreCandidate]
    ) -> Bool {
        if PriceParsingService.looksLikeReceipt(text: ocrText) {
            return false
        }

        let closeMatches = nearbyCandidates.filter { nearbyCandidate in
            guard let distance = nearbyCandidate.distanceMeters else {
                return false
            }
            guard let topDistance = candidate.distanceMeters else {
                return false
            }
            return abs(distance - topDistance) <= 50
        }

        return closeMatches.count < 2
    }

    private func invalidateActiveScan() {
        activeScanID = nil
        isProcessingOCR = false
    }

    private func resetCaptureState() {
        invalidateActiveScan()
        isFlashEnabled = false
        isShowingConfirmationSheet = false
        capturedImage = nil
        previewImage = nil
        currentScanSource = nil
        draft = PriceEntryDraft()
        pendingExpectedItemName = nil
        pendingPreferredChainName = nil
        cameraPreviewRefreshID = UUID()
    }

    private func resolvedPhotoLibraryAuthorizationStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    private func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            })
        }
    }
}
