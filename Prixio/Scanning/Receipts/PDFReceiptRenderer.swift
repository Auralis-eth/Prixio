import PDFKit
import UIKit

/// PDF → image conversion so imported receipt PDFs can feed the same image-based extraction pipeline
/// as camera captures. Multi-page receipts are composited into one image (up to a page cap) so they
/// are reviewed and extracted as a single unit.
enum PDFReceiptRenderer {
    /// Maximum pages composited from a single PDF. Pages beyond this are dropped (see
    /// PriceCaptureAndIntelligence.md open questions).
    static let maxCompositePages = 5

    static func renderFirstPage(from data: Data, scale: CGFloat = 2.0) -> UIImage? {
        renderPages(from: data, maxPages: 1, scale: scale).first
    }

    /// Total number of pages in the PDF (0 when the data is not a readable PDF). Used at import time
    /// to detect when pages will be dropped by the composite cap.
    static func pageCount(of data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    /// Renders up to `maxPages` pages and stacks them vertically into a single image so a multi-page
    /// receipt can be reviewed and extracted as one unit. Returns `nil` when the data is not a
    /// readable PDF with at least one page.
    static func renderComposite(from data: Data, maxPages: Int = maxCompositePages, scale: CGFloat = 2.0) -> UIImage? {
        let pages = renderPages(from: data, maxPages: maxPages, scale: scale)
        guard let first = pages.first else {
            return nil
        }
        guard pages.count > 1 else {
            return first
        }

        let width = pages.map(\.size.width).max() ?? first.size.width
        let totalHeight = pages.reduce(CGFloat(0)) { $0 + $1.size.height }
        let canvasSize = CGSize(width: width, height: totalHeight)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return first
        }

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { _ in
            UIColor.white.set()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
            var y: CGFloat = 0
            for page in pages {
                page.draw(in: CGRect(x: 0, y: y, width: page.size.width, height: page.size.height))
                y += page.size.height
            }
        }
    }

    static func renderPages(from data: Data, maxPages: Int = 1, scale: CGFloat = 2.0) -> [UIImage] {
        guard let document = PDFDocument(data: data) else {
            return []
        }

        let pageCount = min(maxPages, document.pageCount)
        guard pageCount > 0 else {
            return []
        }

        var images: [UIImage] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else {
                continue
            }

            let bounds = page.bounds(for: .mediaBox)
            let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard pixelSize.width > 0, pixelSize.height > 0 else {
                continue
            }

            let renderer = UIGraphicsImageRenderer(size: pixelSize)
            let image = renderer.image { context in
                UIColor.white.set()
                context.fill(CGRect(origin: .zero, size: pixelSize))
                // Flip into UIKit's top-left origin and scale to the requested resolution.
                context.cgContext.translateBy(x: 0, y: pixelSize.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
            images.append(image)
        }

        return images
    }
}
