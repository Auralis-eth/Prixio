import Foundation
import Testing
import UIKit
@testable import Prixio

struct PDFReceiptRendererTests {
    /// Produces a minimal single-page PDF in memory for rendering round-trips.
    private func makePDFData(pageSize: CGSize = CGSize(width: 200, height: 300)) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 20, y: 20, width: 60, height: 12))
        }
    }

    @Test
    func rendersFirstPageOfValidPDF() {
        let data = makePDFData(pageSize: CGSize(width: 200, height: 300))

        let image = PDFReceiptRenderer.renderFirstPage(from: data, scale: 2.0)

        let rendered = try? #require(image)
        #expect(rendered != nil)
        // 200x300 points at 2x → 400x600 pixels.
        #expect(rendered?.size == CGSize(width: 400, height: 600))
    }

    @Test
    func returnsEmptyForNonPDFData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])

        #expect(PDFReceiptRenderer.renderFirstPage(from: garbage) == nil)
        #expect(PDFReceiptRenderer.renderPages(from: garbage).isEmpty)
    }
}
