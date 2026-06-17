import CoreLocation
import FoundationModels
import SwiftData
import Testing
import UIKit
@testable import Prixio

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
