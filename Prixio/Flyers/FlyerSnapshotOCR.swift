import Foundation
import WebKit
import UIKit
import Vision
import PDFKit

/// Reads flyer prices from a rendered web view's **content** via `WKWebView.createPDF`
/// + Vision OCR. Renders the page to PDF (which captures the full scrollable page,
/// decoded images, and cross-origin iframe pixels — and works while the web view is
/// off-screen, unlike `takeSnapshot`), rasterizes each PDF page, and OCRs it.
///
/// This is the read mechanism for flyers whose prices are images or live inside
/// cross-origin iframes (Flipp/Salesforce) that JavaScript `innerText` cannot reach.
/// Used as a fallback inside `WebPageFlyerContentAcquirer` when text/attribute
/// harvest stays below the flyer-price threshold.
@MainActor
enum FlyerSnapshotOCR {
    static func harvest(
        from webView: WKWebView,
        maxPages: Int,
        maxTextLength: Int,
        log: (String) -> Void
    ) async -> (priceCount: Int, text: String) {
        guard let data = await renderPDF(of: webView) else {
            log("pdf=failed")
            return (0, "")
        }
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            log("pdf-parse=failed bytes=\(data.count)")
            return (0, "")
        }

        var combined = ""
        let pageCount = min(document.pageCount, maxPages)
        for index in 0..<pageCount {
            guard let page = document.page(at: index), let cgImage = rasterize(page) else {
                log("ocr-page=\(index + 1) render=failed")
                continue
            }
            let text = await recognizeText(in: cgImage)
            combined += "\n" + text
            log("ocr-page=\(index + 1) ocrChars=\(text.count)")
        }

        let priceCount = FlyerSourceShapeClassifier.priceTokenCount(in: combined.lowercased())
        return (priceCount, String(combined.prefix(maxTextLength)))
    }

    private static func renderPDF(of webView: WKWebView) async -> Data? {
        try? await webView.pdf(configuration: WKPDFConfiguration())
    }

    /// Rasterizes a PDF page to a bounded-size `CGImage` for OCR.
    private static func rasterize(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // Cap dimensions so a very tall single-page flyer stays a manageable image.
        let scale = min(1500 / bounds.width, 12000 / bounds.height, 3.0)
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            let cgContext = context.cgContext
            // PDF coordinate space is bottom-left origin; flip and scale to pixels.
            cgContext.translateBy(x: 0, y: pixelSize.height)
            cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cgContext)
        }
        return image.cgImage
    }

    private static func recognizeText(in cgImage: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do {
            let observations = try await request.perform(on: cgImage)
            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        } catch {
            return ""
        }
    }
}
