import Foundation
import SwiftData
import Testing
import UIKit
@testable import Prixio

@Suite(.serialized)
@MainActor
struct ReceiptImportServiceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
    }

    private func makePDFData() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300))
        return renderer.pdfData { context in
            context.beginPage()
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 10, y: 10, width: 40, height: 10))
        }
    }

    @Test
    func importImagePersistsPendingCaptureWithSource() throws {
        let context = try makeContext()
        let service = ReceiptImportService(context: context)

        let capture = try service.importImage(makeImage(), source: .importedImage)

        #expect(capture.source == .importedImage)
        #expect(capture.reviewState == .pendingReview)
        #expect(capture.imageData != nil)
        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).count == 1)
    }

    @Test
    func importPDFPersistsCaptureFromFirstPage() throws {
        let context = try makeContext()
        let service = ReceiptImportService(context: context)

        let capture = try service.importPDF(makePDFData())

        #expect(capture?.source == .importedPDF)
        #expect(capture?.reviewState == .pendingReview)
        #expect(capture?.imageData != nil)
        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).count == 1)
    }

    @Test
    func importPDFReturnsNilAndPersistsNothingForBadData() throws {
        let context = try makeContext()
        let service = ReceiptImportService(context: context)

        let capture = try service.importPDF(Data([0xDE, 0xAD, 0xBE, 0xEF]))

        #expect(capture == nil)
        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).isEmpty)
    }
}
