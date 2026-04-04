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
}
