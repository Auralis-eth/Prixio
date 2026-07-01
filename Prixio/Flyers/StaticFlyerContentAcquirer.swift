import Foundation

/// A bounded raw fetch used by static acquisition — enough to classify and process
/// the body in-app without a web view.
struct FlyerRawContent: Equatable {
    let finalURL: URL
    let statusCode: Int
    let mimeType: String?
    let byteCount: Int
    /// Decoded bounded text for text-like content (HTML/JSON/text); `nil` for
    /// binary content (PDF/image) we never stringify.
    let bodyText: String?

    var isUsable: Bool {
        (200...299).contains(statusCode) && byteCount > 0
    }
}

protocol FlyerRawContentFetching {
    func fetchRaw(_ url: URL) async throws -> FlyerRawContent
}

final class URLSessionFlyerRawContentFetcher: FlyerRawContentFetching {
    private let session: URLSession

    /// Static flyer HTML/JSON can be large; decode a generous-but-bounded prefix so
    /// price tokens deep in the document are still seen while memory stays capped.
    private let maxDecodedBytes = 512 * 1024

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRaw(_ url: URL) async throws -> FlyerRawContent {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("Prixio/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("en-CA", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlyerDocumentFetchError.nonHTTPResponse
        }

        let mimeType = httpResponse.mimeType
        return FlyerRawContent(
            finalURL: httpResponse.url ?? url,
            statusCode: httpResponse.statusCode,
            mimeType: mimeType,
            byteCount: data.count,
            bodyText: decodedText(from: data, mimeType: mimeType)
        )
    }

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
}

/// Acquires flyer content for sources that expose it without running JavaScript:
/// server-rendered HTML, JSON endpoints, and binary PDF/image assets. Reuses the
/// discovery classifier so the price bar matches discovery. Binary assets are
/// fetched and recorded for the OCR milestone but not yet read for prices.
///
/// The acquirer re-classifies from the live response rather than trusting the
/// discovery-time shape (which may have rotated). If a page expected to be static
/// HTML turns out to be a JS shell, it reports `acquiredNoPrices` so the router can
/// escalate to a rendered fetch.
final class StaticFlyerContentAcquirer: FlyerContentAcquiring {
    private let fetcher: FlyerRawContentFetching
    private let priceThreshold: Int
    private let maxSnippetLength: Int
    private let logger: FlyerAcquisitionLogging

    init(
        fetcher: FlyerRawContentFetching = URLSessionFlyerRawContentFetcher(),
        priceThreshold: Int? = nil,
        maxSnippetLength: Int = 300,
        logger: FlyerAcquisitionLogging = ConsoleFlyerAcquisitionLogger()
    ) {
        self.fetcher = fetcher
        self.priceThreshold = priceThreshold ?? FlyerSourceShapeClassifier.priceSignalThreshold
        self.maxSnippetLength = maxSnippetLength
        self.logger = logger
    }

    func acquire(
        banner: FlyerBanner,
        from url: URL,
        sourceShape: FlyerSourceShape?,
        storeContext: String?
    ) async -> FlyerAcquiredContent {
        let label = FlyerAcquisitionLogLabel.make(for: banner)
        logger.log("banner=\(label) phase=static-start url=\(url.absoluteString)")

        let raw: FlyerRawContent
        do {
            raw = try await fetcher.fetchRaw(url)
        } catch {
            logger.log("banner=\(label) phase=static-fetch-error url=\(url.absoluteString) error=\(description(for: error))")
            let result = FlyerAcquiredContent(
                banner: banner,
                state: .failed,
                acquisitionMethod: nil,
                sourceURL: url,
                finalURL: url,
                storeContext: storeContext,
                fetchedAt: Date(),
                message: "Static fetch failed: \(description(for: error))."
            )
            return logged(result, label: label)
        }

        logger.log("banner=\(label) phase=static-fetch-finish status=\(raw.statusCode) mime=\(raw.mimeType ?? "unknown") bytes=\(raw.byteCount) finalURL=\(raw.finalURL.absoluteString)")

        guard raw.isUsable else {
            let result = FlyerAcquiredContent(
                banner: banner,
                state: .failed,
                acquisitionMethod: nil,
                sourceURL: url,
                finalURL: raw.finalURL,
                storeContext: storeContext,
                fetchedAt: Date(),
                payloadContentType: raw.mimeType,
                payloadByteCount: raw.byteCount,
                message: "Unusable static response (HTTP \(raw.statusCode), \(raw.byteCount) bytes)."
            )
            return logged(result, label: label)
        }

        // Classify from the live response — the source of truth — rather than the
        // discovery-time shape.
        let (shape, _) = FlyerSourceShapeClassifier.classify(
            mimeType: raw.mimeType,
            bodyText: raw.bodyText,
            byteCount: raw.byteCount
        )
        logger.log("banner=\(label) phase=static-classify shape=\(shape.rawValue)")

        let result: FlyerAcquiredContent
        switch shape {
        case .html:
            result = acquiredHTML(banner: banner, url: url, raw: raw, storeContext: storeContext)
        case .json:
            result = acquiredJSON(banner: banner, url: url, raw: raw, storeContext: storeContext)
        case .pdf, .image:
            result = acquiredBinary(banner: banner, url: url, raw: raw, shape: shape, storeContext: storeContext)
        case .dynamicHTML, .unknown:
            // Expected static, got a JS shell. Report no prices so the router can
            // escalate to a rendered fetch.
            let visible = FlyerSourceShapeClassifier.visibleText(from: raw.bodyText ?? "")
            result = FlyerAcquiredContent(
                banner: banner,
                state: .acquiredNoPrices,
                acquisitionMethod: .staticHTML,
                sourceURL: url,
                finalURL: raw.finalURL,
                storeContext: storeContext,
                fetchedAt: Date(),
                payloadContentType: raw.mimeType,
                payloadByteCount: raw.byteCount,
                priceTokenCount: 0,
                renderedTextSnippet: snippet(from: visible),
                message: "Static fetch returned a JS shell; rendered extraction needed."
            )
        }
        return logged(result, label: label)
    }

    private func logged(_ result: FlyerAcquiredContent, label: String) -> FlyerAcquiredContent {
        logger.log("banner=\(label) phase=static-finish state=\(result.state.rawValue) method=\(result.acquisitionMethod?.rawValue ?? "none") prices=\(result.priceTokenCount) bytes=\(result.payloadByteCount)")
        return result
    }

    private func acquiredHTML(
        banner: FlyerBanner,
        url: URL,
        raw: FlyerRawContent,
        storeContext: String?
    ) -> FlyerAcquiredContent {
        let visible = FlyerSourceShapeClassifier.visibleText(from: raw.bodyText ?? "")
        let priceCount = FlyerSourceShapeClassifier.priceTokenCount(in: visible)
        let hasPrices = priceCount > 0
        return FlyerAcquiredContent(
            banner: banner,
            state: hasPrices ? .acquired : .acquiredNoPrices,
            acquisitionMethod: .staticHTML,
            sourceURL: url,
            finalURL: raw.finalURL,
            storeContext: storeContext,
            fetchedAt: Date(),
            payloadContentType: raw.mimeType ?? "text/html",
            payloadByteCount: raw.byteCount,
            priceTokenCount: priceCount,
            renderedTextSnippet: snippet(from: visible),
            extractionPayload: visible.isEmpty ? nil : visible,
            message: hasPrices
                ? "Processed static HTML in-app with \(priceCount) price tokens."
                : "Static HTML had no readable prices; rendered extraction may be needed."
        )
    }

    private func acquiredJSON(
        banner: FlyerBanner,
        url: URL,
        raw: FlyerRawContent,
        storeContext: String?
    ) -> FlyerAcquiredContent {
        let body = raw.bodyText ?? ""
        // JSON often carries prices as numeric fields without a `$`, so a zero token
        // count does not mean the payload is empty — the structured payload itself
        // is the win.
        let priceCount = FlyerSourceShapeClassifier.priceTokenCount(in: body.lowercased())
        return FlyerAcquiredContent(
            banner: banner,
            state: .acquired,
            acquisitionMethod: .endpointJSON,
            sourceURL: url,
            finalURL: raw.finalURL,
            storeContext: storeContext,
            fetchedAt: Date(),
            payloadContentType: raw.mimeType ?? "application/json",
            payloadByteCount: raw.byteCount,
            priceTokenCount: priceCount,
            renderedTextSnippet: snippet(from: body),
            extractionPayload: body.isEmpty ? nil : body,
            message: "Processed JSON endpoint payload (\(raw.byteCount) bytes, \(priceCount) price tokens)."
        )
    }

    private func acquiredBinary(
        banner: FlyerBanner,
        url: URL,
        raw: FlyerRawContent,
        shape: FlyerSourceShape,
        storeContext: String?
    ) -> FlyerAcquiredContent {
        let method: FlyerAcquisitionMethod = shape == .pdf ? .endpointPDF : .imageOCR
        return FlyerAcquiredContent(
            banner: banner,
            state: .acquiredNoPrices,
            acquisitionMethod: method,
            sourceURL: url,
            finalURL: raw.finalURL,
            storeContext: storeContext,
            fetchedAt: Date(),
            payloadContentType: raw.mimeType,
            payloadByteCount: raw.byteCount,
            priceTokenCount: 0,
            renderedTextSnippet: nil,
            message: "Fetched \(shape.label) asset (\(raw.byteCount) bytes); OCR extraction pending."
        )
    }

    private func snippet(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxSnippetLength))
    }

    private func description(for error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message.replacingOccurrences(of: "\n", with: " ")
        }
        return String(describing: error).replacingOccurrences(of: "\n", with: " ")
    }
}

/// Picks the acquisition mechanism per destination from the source shape discovery
/// classified: static HTML/JSON/PDF/image are processed in-app; JS-rendered
/// (`dynamicHTML`) and `unknown` sources are fetched from the banner's structured
/// endpoint (Flipp / pcexpress) via `EndpointFlyerContentAcquirer`. Static HTML that
/// yields no readable prices escalates to the endpoint path, since a page can become
/// JS-gated after discovery (and the banner may still expose a Flipp/pcexpress source).
final class FlyerContentAcquisitionRouter: FlyerContentAcquiring {
    private let staticAcquirer: FlyerContentAcquiring
    private let endpointAcquirer: FlyerContentAcquiring
    private let logger: FlyerAcquisitionLogging

    init(
        staticAcquirer: FlyerContentAcquiring? = nil,
        endpointAcquirer: FlyerContentAcquiring? = nil,
        logger: FlyerAcquisitionLogging = ConsoleFlyerAcquisitionLogger()
    ) {
        self.logger = logger
        self.staticAcquirer = staticAcquirer ?? StaticFlyerContentAcquirer(logger: logger)
        self.endpointAcquirer = endpointAcquirer ?? EndpointFlyerContentAcquirer(logger: logger)
    }

    func acquire(
        banner: FlyerBanner,
        from url: URL,
        sourceShape: FlyerSourceShape?,
        storeContext: String?
    ) async -> FlyerAcquiredContent {
        let label = FlyerAcquisitionLogLabel.make(for: banner)
        switch sourceShape {
        case .dynamicHTML?, .unknown?, .none:
            logger.log("banner=\(label) phase=route shape=\(sourceShape?.rawValue ?? "none") path=endpoint url=\(url.absoluteString)")
            return await endpointAcquirer.acquire(
                banner: banner,
                from: url,
                sourceShape: sourceShape,
                storeContext: storeContext
            )
        case .html?, .json?, .pdf?, .image?:
            logger.log("banner=\(label) phase=route shape=\(sourceShape?.rawValue ?? "none") path=static url=\(url.absoluteString)")
            let result = await staticAcquirer.acquire(
                banner: banner,
                from: url,
                sourceShape: sourceShape,
                storeContext: storeContext
            )
            if shouldEscalateToEndpoint(result, shape: sourceShape) {
                logger.log("banner=\(label) phase=escalate reason=static-html-no-prices path=endpoint")
                return await endpointAcquirer.acquire(
                    banner: banner,
                    from: url,
                    sourceShape: sourceShape,
                    storeContext: storeContext
                )
            }
            return result
        }
    }

    /// Only HTML escalates: JSON/PDF/image have their own downstream pipelines and the
    /// endpoint path would not help them.
    private func shouldEscalateToEndpoint(_ result: FlyerAcquiredContent, shape: FlyerSourceShape?) -> Bool {
        shape == .html && result.state == .acquiredNoPrices
    }
}
