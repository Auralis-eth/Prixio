//
//  ScanViewModel.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation
import SwiftData
import SwiftUI
import UIKit

import Combine

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var draft = PriceEntryDraft()
    @Published var isShowingImagePicker = false
    @Published var isShowingConfirmationSheet = false
    @Published var isShowingStoreSheet = false
    @Published var isProcessingOCR = false
    @Published var capturedImage: UIImage?
    @Published var previewImage: UIImage?
    @Published var isFlashEnabled = false
    @Published var showToast = false
    @Published var recentItems: [String] = []
    @Published var searchResults: [StoreCandidate] = []

    @Published var imagePickerSource: UIImagePickerController.SourceType = .camera

    private let ocrService = OCRService()
    private let storeService = StoreDetectionService()

    var displayImage: UIImage? {
        previewImage ?? capturedImage
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
            return "\(candidate.locationName) · \(DistanceFormatter.text(for: distanceMeters))"
        }

        return candidate.locationName
    }

    private var candidatePreview: StoreCandidate? {
        if !draft.storeLocationName.isEmpty || draft.storeChainName != nil {
            return StoreCandidate(
                id: UUID(),
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
        imagePickerSource = .photoLibrary
        isShowingImagePicker = true
    }

    func toggleFlash() {
        isFlashEnabled.toggle()
    }

    func handlePickedImage(
        _ image: UIImage?,
        sessionStore: ScanSessionStore,
        currentLocation: CLLocation?
    ) async {
        guard let image else {
            return
        }

        previewImage = image
        capturedImage = image
        draft = PriceEntryDraft(
            capturedAt: .now,
            imageData: image.jpegData(compressionQuality: 0.88)
        )
        isProcessingOCR = true
        isShowingConfirmationSheet = true

        let result = await ocrService.analyze(image: image)
        draft.ocrText = result.rawText
        draft.confidence = result.confidence
        draft.priceText = result.price.map(CurrencyFormatter.string) ?? ""
        draft.selectedUnit = result.unit
        draft.quantity = result.quantity
        draft.priceCandidates = Array(result.priceCandidates.prefix(2))
        draft.itemName = result.itemNameHint ?? ""

        if sessionStore.nearbyCandidates.isEmpty {
            let stores = await storeService.fetchNearbyStores(location: currentLocation)
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

    func applyPriceCandidate(_ candidate: PriceCandidate) {
        draft.priceText = CurrencyFormatter.string(candidate.value)
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
        isShowingConfirmationSheet = false
        capturedImage = nil
        previewImage = nil
        draft = PriceEntryDraft()
    }

    func discardCapture() {
        isShowingConfirmationSheet = false
        capturedImage = nil
        previewImage = nil
        draft = PriceEntryDraft()
    }

    func save(context: ModelContext) {
        guard draft.canSave else {
            return
        }

        do {
            try PriceEntryRepository(context: context).saveEntry(from: draft)
            Haptics.success()
            withAnimation(.easeOut(duration: 0.2)) {
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
}
