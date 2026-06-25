import Foundation

/// The shape of a fetched flyer source, used by the next phase to choose an
/// extractor path. Classification is intentionally lightweight: MIME type first,
/// then simple content signals.
enum FlyerSourceShape: String, Equatable {
    case html
    case pdf
    case image
    case json
    case dynamicHTML
    case unknown

    var label: String {
        switch self {
        case .html:
            "HTML"
        case .pdf:
            "PDF"
        case .image:
            "Image"
        case .json:
            "JSON"
        case .dynamicHTML:
            "Dynamic HTML"
        case .unknown:
            "Unknown"
        }
    }
}

/// Pure, dependency-free classifier so source-shape rules can be unit tested
/// without performing real network work.
enum FlyerSourceShapeClassifier {
    /// Terms that suggest a page actually contains flyer/deal material rather
    /// than being an empty app shell.
    static let usefulTerms = [
        "flyer", "weekly", "deal", "sale", "circular", "savings", "coupon", "offer"
    ]

    /// Minimum number of price tokens (e.g. `$3.99`) that must appear in visible
    /// text before we trust a page as server-rendered `.html` flyer content.
    /// Flyer vocabulary alone is unreliable: retailer navigation, titles, and
    /// footers contain words like "Weekly Flyer" and "Deals" even on pure JS
    /// shells whose prices are rendered client-side. Real static flyer content
    /// carries many prices; chrome carries almost none. Tunable from `prices:N`
    /// in the discovery log.
    static let priceSignalThreshold = 5

    static func classify(
        mimeType: String?,
        bodyText: String?,
        byteCount: Int
    ) -> (shape: FlyerSourceShape, signals: [String]) {
        let mime = (mimeType ?? "").lowercased()

        if mime.contains("application/pdf") {
            return (.pdf, [])
        }
        if mime.hasPrefix("image/") {
            return (.image, [])
        }
        if mime.contains("json") {
            return (.json, [])
        }

        let rawBody = bodyText ?? ""
        let looksLikeHTML = mime.contains("html") || mime.contains("text") || !rawBody.isEmpty

        guard looksLikeHTML else {
            return (.unknown, [])
        }

        // Match against *visible* text only. Real grocery flyer pages are
        // JavaScript SPAs whose raw source contains flyer/deal vocabulary inside
        // <script> bundles, JSON state, and <meta> tags even when no flyer content
        // is server-rendered. Scanning raw HTML therefore false-positives every
        // app shell as a useful `.html` page. Stripping scripts/styles/tags first
        // keeps the signal tied to content a static parse could actually extract.
        let visibleText = visibleText(from: rawBody)
        let matched = usefulTerms.filter { visibleText.contains($0) }
        let priceCount = priceTokenCount(in: visibleText)
        let priceSignal = "prices:\(priceCount)"

        // Treat the page as server-rendered flyer content only when visible text
        // carries enough prices. Flyer-word matches are kept as secondary signals
        // for debugging but do not by themselves promote a page to `.html`.
        if priceCount >= priceSignalThreshold {
            return (.html, matched + [priceSignal])
        }

        // Reachable HTML whose prices (if any) are not in static text: most likely
        // a dynamic app shell that renders content via JavaScript. The next phase
        // will need a rendered fetch rather than a static parse.
        return (.dynamicHTML, matched.isEmpty ? [priceSignal] : matched + [priceSignal])
    }

    /// Counts price-like tokens such as `$3.99`, `$ 5`, or `$12` in the given text.
    static func priceTokenCount(in text: String) -> Int {
        let pattern = "\\$\\s?\\d{1,4}(\\.\\d{2})?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    /// Extracts lowercased visible text from HTML by dropping `<script>`/`<style>`
    /// blocks and then all remaining tags. Intentionally simple and allocation-cheap
    /// rather than a full HTML parser.
    static func visibleText(from html: String) -> String {
        var text = html
        for block in ["script", "style", "noscript"] {
            text = text.replacingOccurrences(
                of: "<\(block)\\b[^>]*>[\\s\\S]*?</\(block)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return text.lowercased()
    }
}

struct FlyerFetchedDocument: Equatable {
    let finalURL: URL
    let statusCode: Int
    let mimeType: String?
    let byteCount: Int
    let sourceShape: FlyerSourceShape
    let contentSnippet: String?
    let usefulnessSignals: [String]

    init(
        finalURL: URL,
        statusCode: Int,
        mimeType: String?,
        byteCount: Int,
        sourceShape: FlyerSourceShape = .unknown,
        contentSnippet: String? = nil,
        usefulnessSignals: [String] = []
    ) {
        self.finalURL = finalURL
        self.statusCode = statusCode
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.sourceShape = sourceShape
        self.contentSnippet = contentSnippet
        self.usefulnessSignals = usefulnessSignals
    }

    var isUsable: Bool {
        (200...299).contains(statusCode) && byteCount > 0
    }
}

protocol FlyerDocumentFetching {
    func fetch(_ url: URL) async throws -> FlyerFetchedDocument
}

enum FlyerDocumentFetchError: LocalizedError, Equatable {
    case nonHTTPResponse

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            "The source did not return an HTTP response."
        }
    }
}

final class URLSessionFlyerDocumentFetcher: FlyerDocumentFetching {
    private let session: URLSession

    /// Upper bound on the body we decode for classification/snippet purposes.
    /// Flyer/deal terms appear early in markup, so a bounded prefix is enough and
    /// keeps memory predictable on large pages.
    private let maxDecodedBytes = 256 * 1024

    /// Maximum length of the debug snippet stored on the document.
    private let maxSnippetLength = 300

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(_ url: URL) async throws -> FlyerFetchedDocument {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("Prixio/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlyerDocumentFetchError.nonHTTPResponse
        }

        let mimeType = httpResponse.mimeType
        let bodyText = decodedText(from: data, mimeType: mimeType)
        let (shape, signals) = FlyerSourceShapeClassifier.classify(
            mimeType: mimeType,
            bodyText: bodyText,
            byteCount: data.count
        )

        return FlyerFetchedDocument(
            finalURL: httpResponse.url ?? url,
            statusCode: httpResponse.statusCode,
            mimeType: mimeType,
            byteCount: data.count,
            sourceShape: shape,
            contentSnippet: snippet(from: bodyText),
            usefulnessSignals: signals
        )
    }

    /// Decodes a bounded text prefix for text-like content only. Binary content
    /// (PDF, image) returns nil so we never try to stringify it.
    private func decodedText(from data: Data, mimeType: String?) -> String? {
        let mime = (mimeType ?? "").lowercased()
        let isTextLike = mime.isEmpty
            || mime.contains("html")
            || mime.contains("text")
            || mime.contains("json")
            || mime.contains("xml")
        guard isTextLike else {
            return nil
        }

        let prefix = data.prefix(maxDecodedBytes)
        return String(data: prefix, encoding: .utf8)
            ?? String(data: prefix, encoding: .isoLatin1)
    }

    private func snippet(from bodyText: String?) -> String? {
        guard let bodyText else {
            return nil
        }

        let collapsed = bodyText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !collapsed.isEmpty else {
            return nil
        }

        return String(collapsed.prefix(maxSnippetLength))
    }
}
