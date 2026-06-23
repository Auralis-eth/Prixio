import Foundation
import SwiftData
import Testing
import UIKit
@testable import Prixio

/// Coverage for the multi-page PDF composite path and the page-cap truncation flag — both claimed as
/// done in the price-capture plan but previously exercised only at the single-page level.
@Suite(.serialized)
@MainActor
struct PDFReceiptCompositeTests {
    /// Produces an in-memory PDF with `pageCount` identical pages.
    private func makePDFData(pageCount: Int, pageSize: CGSize = CGSize(width: 200, height: 300)) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            for _ in 0..<pageCount {
                context.beginPage()
                UIColor.black.setFill()
                UIRectFill(CGRect(x: 20, y: 20, width: 60, height: 12))
            }
        }
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self, PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    // MARK: - Rendering

    @Test
    func pageCountReportsActualPages() {
        #expect(PDFReceiptRenderer.pageCount(of: makePDFData(pageCount: 3)) == 3)
        #expect(PDFReceiptRenderer.pageCount(of: Data([0x00, 0x01])) == 0)
    }

    @Test
    func renderPagesCapsAtRequestedMax() {
        let data = makePDFData(pageCount: PDFReceiptRenderer.maxCompositePages + 3)

        let pages = PDFReceiptRenderer.renderPages(from: data, maxPages: PDFReceiptRenderer.maxCompositePages)

        #expect(pages.count == PDFReceiptRenderer.maxCompositePages)
    }

    @Test
    func renderCompositeStacksPagesVertically() {
        // Two pages composited into one image: same width, twice the single-page height.
        let data = makePDFData(pageCount: 2)
        let single = try? #require(PDFReceiptRenderer.renderFirstPage(from: data, scale: 2.0))
        let composite = try? #require(PDFReceiptRenderer.renderComposite(from: data, scale: 2.0))

        #expect(composite?.size.width == single?.size.width)
        #expect(composite?.size.height == (single?.size.height ?? 0) * 2)
    }

    // MARK: - Import truncation flag

    @Test
    func importPDFFlagsTruncationWhenPagesExceedCap() throws {
        let context = try makeContext()
        let service = ReceiptImportService(context: context)
        let data = makePDFData(pageCount: PDFReceiptRenderer.maxCompositePages + 1)

        let capture = try #require(try service.importPDF(data))

        #expect(capture.reviewIssues.contains(.pagesTruncated))
    }

    @Test
    func importPDFDoesNotFlagTruncationWithinCap() throws {
        let context = try makeContext()
        let service = ReceiptImportService(context: context)
        let data = makePDFData(pageCount: 2)

        let capture = try #require(try service.importPDF(data))

        #expect(!capture.reviewIssues.contains(.pagesTruncated))
    }
}
