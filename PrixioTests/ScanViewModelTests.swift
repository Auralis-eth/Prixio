import CoreLocation
import FoundationModels
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Prixio

// Serialized: these tests construct in-memory SwiftData ModelContainers and a @MainActor view model.
// Running them in parallel races SwiftData/Core Data global state and crashes the test runner.
@Suite(.serialized)
@MainActor
struct ScanViewModelTests {
    @Test
    func beginImageReviewShowsCapturedImageOnlyWhileReviewIsActive() async throws {
        let viewModel = ScanViewModel()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        viewModel.beginImageReview(image, source: .camera)

        #expect(viewModel.displayImage != nil)
        #expect(viewModel.isShowingConfirmationSheet)
        #expect(viewModel.isProcessingOCR)
        #expect(viewModel.currentScanSource == .camera)
    }

    @Test
    func retakeClearsReviewStateAndRefreshesCameraPreview() async throws {
        let viewModel = ScanViewModel()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let initialPreviewID = viewModel.cameraPreviewRefreshID

        viewModel.beginImageReview(image, source: .camera)
        viewModel.dismissConfirmationForRetake()

        #expect(viewModel.displayImage == nil)
        #expect(viewModel.capturedImage == nil)
        #expect(viewModel.previewImage == nil)
        #expect(viewModel.isShowingConfirmationSheet == false)
        #expect(viewModel.isProcessingOCR == false)
        #expect(viewModel.currentScanSource == nil)
        #expect(viewModel.cameraPreviewRefreshID != initialPreviewID)
    }

    @Test
    func processPickedImageComposesInjectedExtractionAndStoreLookup() async throws {
        let extracted = LLMOCRResult.fixture(
            relevantText: "Walmart\nOrganic Milk\n$4.99 ea",
            scene: .singleTag,
            priceCandidates: [
                .fixture(label: "$4.99 ea", value: Decimal(string: "4.99")!, kind: .shelf, sourceText: "$4.99 ea")
            ],
            itemName: "Organic Milk",
            price: Decimal(string: "4.99"),
            unit: .each,
            quantity: Decimal(1)
        )
        let store = StoreCandidate(
            id: "walmart",
            chainName: "Walmart",
            locationName: "Walmart Beltline",
            address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 51.04, longitude: -114.07),
            distanceMeters: 120,
            mapKitPlaceId: "pid-walmart"
        )
        let sessionStore = ScanSessionStore()
        let modelContainer = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = ScanViewModel(
            imageExtractor: FakePriceImageExtractor(outcome: .success(extracted)),
            storeService: FakeStoreLookupProvider(candidates: [store])
        )
        let image = makeImage()

        await viewModel.processPickedImage(
            image,
            sessionStore: sessionStore,
            currentLocation: CLLocation(latitude: 51.04, longitude: -114.07),
            modelContext: ModelContext(modelContainer),
            source: .photoLibrary
        )

        #expect(viewModel.draft.itemName == "Organic Milk")
        #expect(viewModel.draft.selectedUnit == .each)
        #expect(viewModel.draft.quantity == Decimal(1))
        #expect(viewModel.draft.storeChainName == "Walmart")
        #expect(viewModel.draft.storeLocationName == "Walmart Beltline")
        #expect(viewModel.draft.storeAddress == "123 Main St")
        #expect(viewModel.draft.storePlaceId == "pid-walmart")
        #expect(viewModel.isProcessingOCR == false)
        #expect(viewModel.isShowingConfirmationSheet)
    }

    @Test
    func receiptModeExtractsAndPresentsReviewWithoutPriceEntry() async throws {
        let sessionStore = ScanSessionStore()
        let modelContainer = try ModelContainer(
            for: PriceEntry.self, ReceiptCapture.self, ReceiptLineItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(modelContainer)
        let extractedReceipt = LLMReceiptResult(
            storeName: "Costco",
            purchaseDate: nil,
            subtotal: nil,
            tax: nil,
            discountTotal: nil,
            depositTotal: nil,
            total: nil,
            lineItems: [
                LLMReceiptLine(rawText: "MILK 4.99", itemName: "Milk", price: Decimal(string: "4.99"), quantity: 1, unit: .each, lowConfidence: false)
            ],
            issues: []
        )
        let viewModel = ScanViewModel(
            imageExtractor: FakePriceImageExtractor(outcome: .success(.fixture())),
            storeService: FakeStoreLookupProvider(candidates: []),
            receiptExtractor: FakeReceiptImageExtractor(outcome: .success(extractedReceipt))
        )
        viewModel.scanMode = .receipt
        let image = makeImage()

        await viewModel.processPickedImage(
            image,
            sessionStore: sessionStore,
            currentLocation: nil,
            modelContext: modelContext,
            source: .camera
        )

        // The price-tag review flow must not be triggered for a receipt capture.
        #expect(viewModel.isShowingConfirmationSheet == false)
        #expect(viewModel.isProcessingOCR == false)
        #expect(viewModel.draft.itemName.isEmpty)
        // The receipt review surface is presented instead.
        #expect(viewModel.receiptUnderReview != nil)

        let receipts = try modelContext.fetch(FetchDescriptor<ReceiptCapture>())
        #expect(receipts.count == 1)
        #expect(receipts.first?.source == .cameraPhoto)
        #expect(receipts.first?.reviewState == .pendingReview)
        #expect(receipts.first?.lineItems.count == 1)
        // A receipt capture must never create a PriceEntry directly.
        #expect(try modelContext.fetch(FetchDescriptor<PriceEntry>()).isEmpty)
    }

    @Test
    func longPressShortcutSwitchesToReceiptModeWithToast() async throws {
        let viewModel = ScanViewModel()
        #expect(viewModel.scanMode == .priceTag)

        viewModel.switchToReceiptModeViaShortcut()

        #expect(viewModel.scanMode == .receipt)
        #expect(viewModel.showToast)
        #expect(viewModel.toastMessage == "Receipt mode")
    }

    @Test
    func longPressShortcutIsNoOpWhenAlreadyInReceiptMode() async throws {
        let viewModel = ScanViewModel()
        viewModel.scanMode = .receipt

        viewModel.switchToReceiptModeViaShortcut()

        #expect(viewModel.scanMode == .receipt)
        #expect(viewModel.showToast == false)
    }

    @Test
    func longPressShortcutIsNoOpDuringReview() async throws {
        let viewModel = ScanViewModel()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        viewModel.beginImageReview(image, source: .camera)

        viewModel.switchToReceiptModeViaShortcut()

        #expect(viewModel.scanMode == .priceTag)
    }

    @Test
    func dismissingSheetWithoutExplicitActionStillResetsCaptureState() async throws {
        let viewModel = ScanViewModel()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        viewModel.beginImageReview(image, source: .photoLibrary)
        viewModel.isProcessingOCR = false
        viewModel.isShowingConfirmationSheet = false
        viewModel.handleConfirmationSheetDismissed()

        #expect(viewModel.displayImage == nil)
        #expect(viewModel.capturedImage == nil)
        #expect(viewModel.previewImage == nil)
        #expect(viewModel.currentScanSource == nil)
        #expect(viewModel.draft.itemName.isEmpty)
    }

    @Test
    func priceTagExtractionFailureTearsDownTheConfirmationSheet() async throws {
        // On a failed extraction the view model must not leave the user stranded on the blank
        // confirmation sheet that `beginImageReview` opened in anticipation of a result — it shows the
        // error toast and resets capture state instead.
        let sessionStore = ScanSessionStore()
        let modelContainer = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = ScanViewModel(
            imageExtractor: FakePriceImageExtractor(outcome: .failure(.generationFailed)),
            storeService: FakeStoreLookupProvider(candidates: [])
        )

        await viewModel.processPickedImage(
            makeImage(),
            sessionStore: sessionStore,
            currentLocation: nil,
            modelContext: ModelContext(modelContainer),
            source: .photoLibrary
        )

        #expect(viewModel.isShowingConfirmationSheet == false)
        #expect(viewModel.isProcessingOCR == false)
        #expect(viewModel.capturedImage == nil)
        #expect(viewModel.previewImage == nil)
        #expect(viewModel.showToast)
        #expect(viewModel.toastMessage == ImagePriceExtractionFailure.generationFailed.userMessage)
    }

    // MARK: - Quick (toddler) capture queue

    @Test
    func savePendingPersistsCompleteDraftAndRemovesItFromQueue() async throws {
        let modelContainer = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(modelContainer)
        let viewModel = ScanViewModel()
        viewModel.pendingCaptures = [
            ScanViewModel.PendingCapture(draft: savableDraft(), image: nil, isProcessing: false)
        ]
        let id = viewModel.pendingCaptures[0].id

        let saved = viewModel.savePending(id: id, context: modelContext)

        #expect(saved)
        #expect(viewModel.pendingCaptures.isEmpty)
        let entries = try modelContext.fetch(FetchDescriptor<PriceEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.itemNameRaw == "Organic Milk")
    }

    @Test
    func savePendingLeavesIncompleteDraftQueuedAndPersistsNothing() async throws {
        let modelContainer = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(modelContainer)
        let viewModel = ScanViewModel()
        // Missing price/unit/store selection — `draft.canSave` is false.
        var incomplete = PriceEntryDraft()
        incomplete.itemName = "Organic Milk"
        viewModel.pendingCaptures = [
            ScanViewModel.PendingCapture(draft: incomplete, image: nil, isProcessing: false)
        ]
        let id = viewModel.pendingCaptures[0].id

        let saved = viewModel.savePending(id: id, context: modelContext)

        #expect(saved == false)
        #expect(viewModel.pendingCaptures.count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<PriceEntry>()).isEmpty)
    }

    @Test
    func savePendingReturnsFalseForUnknownID() async throws {
        let modelContainer = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = ScanViewModel()
        viewModel.pendingCaptures = [
            ScanViewModel.PendingCapture(draft: savableDraft(), image: nil, isProcessing: false)
        ]

        let saved = viewModel.savePending(id: UUID(), context: ModelContext(modelContainer))

        #expect(saved == false)
        // The real capture is untouched.
        #expect(viewModel.pendingCaptures.count == 1)
    }

    @Test
    func discardPendingRemovesOnlyTheMatchingCapture() async throws {
        let viewModel = ScanViewModel()
        viewModel.pendingCaptures = [
            ScanViewModel.PendingCapture(draft: savableDraft(), image: nil, isProcessing: false),
            ScanViewModel.PendingCapture(draft: savableDraft(), image: nil, isProcessing: false)
        ]
        let kept = viewModel.pendingCaptures[0].id
        let removed = viewModel.pendingCaptures[1].id

        viewModel.discardPending(id: removed)

        #expect(viewModel.pendingCaptures.map(\.id) == [kept])
    }

    @Test
    func draftBindingReadsAndWritesTheQueuedDraftInPlace() async throws {
        let viewModel = ScanViewModel()
        viewModel.pendingCaptures = [
            ScanViewModel.PendingCapture(draft: savableDraft(), image: nil, isProcessing: false)
        ]
        let id = viewModel.pendingCaptures[0].id

        let binding = viewModel.draftBinding(for: id)
        #expect(binding.wrappedValue.itemName == "Organic Milk")

        binding.wrappedValue.itemName = "Whole Milk"

        #expect(viewModel.pendingCaptures[0].draft.itemName == "Whole Milk")
    }

    @Test
    func draftBindingForMissingIDReadsEmptyAndIgnoresWrites() async throws {
        let viewModel = ScanViewModel()

        let binding = viewModel.draftBinding(for: UUID())
        #expect(binding.wrappedValue.itemName.isEmpty)

        // Writing through a stale binding must not resurrect a capture.
        binding.wrappedValue.itemName = "Ghost"
        #expect(viewModel.pendingCaptures.isEmpty)
    }

    @Test
    func enqueueQuickCaptureQueuesImmediatelyThenFillsDraftFromExtraction() async throws {
        let extracted = LLMOCRResult.fixture(
            relevantText: "Walmart\nOrganic Milk\n$4.99 ea",
            scene: .singleTag,
            priceCandidates: [
                .fixture(label: "$4.99 ea", value: Decimal(string: "4.99")!, kind: .shelf, sourceText: "$4.99 ea")
            ],
            itemName: "Organic Milk",
            price: Decimal(string: "4.99"),
            unit: .each,
            quantity: Decimal(1)
        )
        let store = StoreCandidate(
            id: "walmart",
            chainName: "Walmart",
            locationName: "Walmart Beltline",
            address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 51.04, longitude: -114.07),
            distanceMeters: 120,
            mapKitPlaceId: "pid-walmart"
        )
        let sessionStore = ScanSessionStore()
        let modelContainer = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = ScanViewModel(
            imageExtractor: FakePriceImageExtractor(outcome: .success(extracted)),
            storeService: FakeStoreLookupProvider(candidates: [store])
        )

        viewModel.enqueueQuickCapture(
            makeImage(),
            sessionStore: sessionStore,
            currentLocation: CLLocation(latitude: 51.04, longitude: -114.07),
            modelContext: ModelContext(modelContainer)
        )

        // The shot is queued synchronously so the camera stays live; extraction runs in the background.
        #expect(viewModel.pendingCaptures.count == 1)
        let id = viewModel.pendingCaptures[0].id
        #expect(viewModel.pendingCaptures[0].isProcessing)

        await waitForProcessingToFinish(viewModel, id: id)

        let capture = try #require(viewModel.pendingCaptures.first { $0.id == id })
        #expect(capture.isProcessing == false)
        #expect(capture.draft.itemName == "Organic Milk")
        #expect(capture.draft.storeChainName == "Walmart")
        // Capturing never opens the inline confirmation sheet in Quick mode.
        #expect(viewModel.isShowingConfirmationSheet == false)
    }

    @Test
    func enqueueQuickCaptureKeepsShotWhenExtractionFails() async throws {
        let sessionStore = ScanSessionStore()
        let modelContainer = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = ScanViewModel(
            imageExtractor: FakePriceImageExtractor(outcome: .failure(.generationFailed)),
            storeService: FakeStoreLookupProvider(candidates: [])
        )

        viewModel.enqueueQuickCapture(
            makeImage(),
            sessionStore: sessionStore,
            currentLocation: CLLocation(latitude: 51.04, longitude: -114.07),
            modelContext: ModelContext(modelContainer)
        )
        let id = viewModel.pendingCaptures[0].id

        await waitForProcessingToFinish(viewModel, id: id)

        // A failed extraction leaves the shot queued (with its image/imageData) so the user can fill
        // in the details by hand during review — it must not be dropped or left spinning.
        let capture = try #require(viewModel.pendingCaptures.first { $0.id == id })
        #expect(capture.isProcessing == false)
        #expect(capture.image != nil)
        #expect(capture.draft.imageData != nil)
        #expect(capture.draft.itemName.isEmpty)
    }

    @Test
    func enqueueQuickCaptureSerializesExtractionAcrossRapidCaptures() async throws {
        let extracted = LLMOCRResult.fixture(
            relevantText: "Organic Milk\n$4.99 ea",
            scene: .singleTag,
            priceCandidates: [
                .fixture(label: "$4.99 ea", value: Decimal(string: "4.99")!, kind: .shelf, sourceText: "$4.99 ea")
            ],
            itemName: "Organic Milk",
            price: Decimal(string: "4.99"),
            unit: .each,
            quantity: Decimal(1)
        )
        let extractor = ConcurrencyTrackingExtractor(outcome: .success(extracted))
        let sessionStore = ScanSessionStore()
        let modelContainer = try ModelContainer(
            for: PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = ScanViewModel(
            imageExtractor: extractor,
            storeService: FakeStoreLookupProvider(candidates: [])
        )
        let location = CLLocation(latitude: 51.04, longitude: -114.07)

        // Fire three captures back-to-back, the way rapid shutter taps arrive in Quick mode.
        for _ in 0..<3 {
            viewModel.enqueueQuickCapture(
                makeImage(),
                sessionStore: sessionStore,
                currentLocation: location,
                modelContext: ModelContext(modelContainer)
            )
        }
        #expect(viewModel.pendingCaptures.count == 3)
        let ids = viewModel.pendingCaptures.map(\.id)

        for id in ids {
            await waitForProcessingToFinish(viewModel, id: id)
        }

        // Every capture was extracted exactly once, and the serial chain never ran two on-device
        // extractions at the same time.
        #expect(extractor.callCount == 3)
        #expect(extractor.maxConcurrent == 1)
        #expect(viewModel.pendingCaptures.allSatisfy { $0.draft.itemName == "Organic Milk" })
    }

    /// Yields the main actor until the queued capture finishes background extraction (or vanishes).
    /// Bounded so a stuck extraction fails the test instead of hanging the run.
    private func waitForProcessingToFinish(_ viewModel: ScanViewModel, id: UUID) async {
        for _ in 0..<1000 {
            guard let capture = viewModel.pendingCaptures.first(where: { $0.id == id }) else {
                return
            }
            if !capture.isProcessing {
                return
            }
            await Task.yield()
        }
    }

    /// A draft that satisfies `PriceEntryDraft.canSave`: named item, positive price, chosen unit, and
    /// an explicitly selected store chain.
    private func savableDraft() -> PriceEntryDraft {
        var draft = PriceEntryDraft()
        draft.itemName = "Organic Milk"
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"
        draft.storeChainExplicitlySelected = true
        return draft
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}

private struct FakePriceImageExtractor: PriceImageExtracting {
    let outcome: ImagePriceExtractionOutcome

    func extractPriceInformation(
        from image: UIImage,
        context: ScanPromptContext,
        tools: [any Tool]
    ) async -> ImagePriceExtractionOutcome {
        outcome
    }
}

/// Records how many extractions overlap. Each call suspends (via `Task.yield`) while "in flight",
/// so if the view model ever ran two extractions concurrently both would be counted as active at the
/// same time and `maxConcurrent` would exceed 1. Confined to the main actor — like the real extractor
/// call site — so the counter mutations are race-free.
@MainActor
private final class ConcurrencyTrackingExtractor: PriceImageExtracting {
    let outcome: ImagePriceExtractionOutcome
    private(set) var callCount = 0
    private(set) var maxConcurrent = 0
    private var active = 0

    init(outcome: ImagePriceExtractionOutcome) {
        self.outcome = outcome
    }

    func extractPriceInformation(
        from image: UIImage,
        context: ScanPromptContext,
        tools: [any Tool]
    ) async -> ImagePriceExtractionOutcome {
        callCount += 1
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        // Suspend repeatedly so any concurrent extraction would observably overlap this window.
        for _ in 0..<5 {
            await Task.yield()
        }
        active -= 1
        return outcome
    }
}

private struct FakeReceiptImageExtractor: ReceiptImageExtracting {
    let outcome: ReceiptExtractionOutcome

    func extractReceipt(from image: UIImage) async -> ReceiptExtractionOutcome {
        outcome
    }
}

@MainActor
private final class FakeStoreLookupProvider: StoreLookupProviding {
    let candidates: [StoreCandidate]

    init(candidates: [StoreCandidate]) {
        self.candidates = candidates
    }

    func fetchNearbyStores(location: CLLocation?) async -> [StoreCandidate] {
        candidates
    }

    func search(query: String, near location: CLLocation?) async -> [StoreCandidate] {
        candidates
    }
}
