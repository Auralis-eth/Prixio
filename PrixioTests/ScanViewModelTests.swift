import CoreLocation
import FoundationModels
import SwiftData
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
