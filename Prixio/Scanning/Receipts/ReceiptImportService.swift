import SwiftData
import UIKit

/// Brings receipts into the app from the supported ingestion sources (camera, photo library, PDF)
/// and persists them as `pendingReview` captures. Extraction and review happen in later phases; this
/// service only ensures a durable `ReceiptCapture` exists with the original image and source metadata.
enum ReceiptImportError: Error {
    /// The source image could not be JPEG-encoded, so persisting would yield an imageless capture.
    case imageEncodingFailed
}

@MainActor
struct ReceiptImportService {
    let context: ModelContext

    @discardableResult
    func importImage(
        _ image: UIImage,
        source: ReceiptSource,
        capturedAt: Date = .now
    ) throws -> ReceiptCapture {
        // Don't persist a capture with no image: the user could never re-review or re-extract it.
        guard let imageData = image.jpegData(compressionQuality: 0.88) else {
            throw ReceiptImportError.imageEncodingFailed
        }
        let capture = ReceiptCapture(
            capturedAt: capturedAt,
            imageData: imageData,
            source: source,
            reviewState: .pendingReview
        )
        context.insert(capture)
        try context.save()
        return capture
    }

    /// Renders the PDF (up to the page cap, composited into one image) into the capture's image so it
    /// can be reviewed and later extracted. Returns `nil` without persisting anything when the data is
    /// not a readable PDF.
    @discardableResult
    func importPDF(_ data: Data, capturedAt: Date = .now) throws -> ReceiptCapture? {
        guard let pageImage = PDFReceiptRenderer.renderComposite(from: data) else {
            return nil
        }

        guard let imageData = pageImage.jpegData(compressionQuality: 0.88) else {
            throw ReceiptImportError.imageEncodingFailed
        }

        // Surface, rather than silently swallow, the composite page cap so the user knows a long
        // receipt was truncated. Carried as a review issue so it persists into the review surface.
        let truncated = PDFReceiptRenderer.pageCount(of: data) > PDFReceiptRenderer.maxCompositePages

        let capture = ReceiptCapture(
            capturedAt: capturedAt,
            imageData: imageData,
            source: .importedPDF,
            reviewState: .pendingReview,
            extractionIssuesRaw: truncated ? ReceiptReviewIssue.pagesTruncated.rawValue : nil
        )
        context.insert(capture)
        try context.save()
        return capture
    }
}
