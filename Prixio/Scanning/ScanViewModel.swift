//
//  ScanViewModel.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation
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

    private let storeService = StoreDetectionService()
    private(set) var currentScanSource: ScanInputSource?

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

        if let preferredChainName = request.preferredChainName {
            draft.storeChainName = preferredChainName
            draft.storeChainExplicitlySelected = true
        }
    }

    func toggleFlash() {
        isFlashEnabled.toggle()
    }

    func handlePickedImage(
        _ image: UIImage?,
        sessionStore: ScanSessionStore,
        currentLocation: CLLocation?,
        source: ScanInputSource = .photoLibrary
    ) async {
        guard let image else {
            return
        }

        let scanID = UUID()
        activeScanID = scanID
        beginImageReview(image, source: source)

        let result = await image.extractOCR()
        guard activeScanID == scanID else {
            return
        }
        draft.ocrText = result.rawText
        draft.confidence = result.confidence
        draft.priceText = result.price.map(CurrencyFormatter.shared.string) ?? ""
        draft.selectedUnit = result.unit
        draft.quantity = result.quantity
        draft.priceCandidates = Array(result.priceCandidates.prefix(2))
        draft.itemName = result.itemNameHint ?? ""
        draft.review = result.review

#if DEBUG
        print("========== SCAN RESULT ==========")
        print("itemName: \(result.itemNameHint ?? "nil")")
        print("price: \(result.price.map { "\($0)" } ?? "nil")")
        print("unit: \(result.unit?.rawValue ?? "nil")")
        print("quantity: \(result.quantity.map { "\($0)" } ?? "nil")")
        print("priceCandidates: \(result.priceCandidates.map { "\($0.value) src=\($0.sourceText)" })")
        print("supportingLines: \(result.supportingLines)")
        print("review: \(result.review.issues.map(\.rawValue)) usedFM=\(result.review.usedFoundationModel)")
        print("===============================")
#endif

        if sessionStore.nearbyCandidates.isEmpty {
            let stores = await storeService.fetchNearbyStores(location: currentLocation)
            guard activeScanID == scanID else {
                return
            }
            sessionStore.updateCandidates(stores)
        }

        let isReceiptCapture = PriceParsingService.looksLikeReceipt(text: result.rawText)
        let matchedCandidate = matchStoreCandidate(
            from: sessionStore.nearbyCandidates,
            ocrText: result.rawText,
            currentLocation: currentLocation
        )
        inferredStoreCandidate = isReceiptCapture ? nil : (matchedCandidate ?? sessionStore.lastStoreCandidate)
        applyInferredStore(from: inferredStoreCandidate, ocrText: result.rawText, nearbyCandidates: sessionStore.nearbyCandidates)
        isProcessingOCR = false
    }
    
    @available(iOS 27.0, *)
    func processPickedImage(
        _ image: UIImage?,
        sessionStore: ScanSessionStore,
        currentLocation: CLLocation?,
        source: ScanInputSource = .photoLibrary
    ) async {
        guard let image else {
            return
        }

        let scanID = UUID()
        activeScanID = scanID
        beginImageReview(image, source: source)

        let result = await image.extractPriceInformation(context: ScanPromptContext(storeName: sessionStore.lastStoreCandidate?.chainName))
        guard activeScanID == scanID else {
            return
        }
        guard let result else {
            isProcessingOCR = false
            return
        }
        draft.ocrText = result.relevantText
        draft.priceText = result.price.map(CurrencyFormatter.shared.string) ?? ""
        draft.selectedUnit = result.unit
        draft.quantity = result.quantity
        // Map the LLM's candidates into PriceCandidate. The model doesn't supply
        // priority/confidence/sourceLineIndexes, so default them: priority follows
        // list order, confidence is 1.0 (LLM-asserted), and there are no source line indexes.
        draft.priceCandidates = result.priceCandidates.enumerated().map { index, candidate in
            PriceCandidate(
                label: candidate.label,
                value: candidate.value,
                quantity: candidate.quantity,
                priority: index,
                sourceText: candidate.sourceText,
                kind: candidate.kind,
                sourceLineIndexes: [],
                confidence: 1.0
            )
        }
        draft.itemName = result.itemName ?? ""

#if DEBUG
        print("========== SCAN RESULT ==========")
        print("itemName: \(result.itemName ?? "nil")")
        print("price: \(result.price.map { "\($0)" } ?? "nil")")
        print("unit: \(result.unit?.rawValue ?? "nil")")
        print("quantity: \(result.quantity.map { "\($0)" } ?? "nil")")
        print("priceCandidates: \(result.priceCandidates.map { "\($0.value) src=\($0.sourceText)" })")
         print("relevantText: \(result.relevantText)")
        print("===============================")
#endif

        if sessionStore.nearbyCandidates.isEmpty {
            let stores = await storeService.fetchNearbyStores(location: currentLocation)
            guard activeScanID == scanID else {
                return
            }
            sessionStore.updateCandidates(stores)
        }

        let isReceiptCapture = PriceParsingService.looksLikeReceipt(text: result.relevantText)
        let matchedCandidate = matchStoreCandidate(
            from: sessionStore.nearbyCandidates,
            ocrText: result.relevantText,
            currentLocation: currentLocation
        )
        inferredStoreCandidate = isReceiptCapture ? nil : (matchedCandidate ?? sessionStore.lastStoreCandidate)
        applyInferredStore(from: inferredStoreCandidate, ocrText: result.relevantText, nearbyCandidates: sessionStore.nearbyCandidates)
        isProcessingOCR = false
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

    private func applyInferredStore(from candidate: StoreCandidate?, ocrText: String, nearbyCandidates: [StoreCandidate]) {
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

    private func matchStoreCandidate(
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

    private func shouldAutoApplyStore(
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
