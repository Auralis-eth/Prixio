import Foundation

/// Acquires flyer content straight from a banner's structured endpoint — the Flipp
/// `flyers-ng` API (`FlippFlyerKitClient`) or the Loblaw pcexpress BFF
/// (`PCExpressClient`), selected per banner from `FlyerStorePreparationCatalog`.
///
/// This is the acquisition path for JS-rendered (`dynamicHTML`) banners. Every
/// supported Alberta banner serves its flyer through one of these two public APIs, so
/// the flyer items are fetched directly — no WKWebView, no store-selection gate, no
/// OCR. It replaced the rendered-capture path, which could never read the flyers
/// (Flipp cross-origin iframes and Loblaw Akamai shells) anyway.
///
/// A banner with no endpoint configured (or whose fetch errors / returns too few
/// prices) yields `.acquiredNoPrices` so the gap is honest and debuggable rather than
/// silently empty.
final class EndpointFlyerContentAcquirer: FlyerContentAcquiring {
    private let storeContext: FlyerStoreContext
    /// Structured flyer JSON is a strong signal, so it acquires at a low bar: a handful
    /// of price fields in a fetched item list is unambiguously real flyer data.
    private let acquireThreshold: Int
    private let flyerKitClient: FlippFlyerKitClient
    private let pcExpressClient: PCExpressClient
    private let maxSnippetLength: Int
    private let logger: FlyerAcquisitionLogging

    init(
        storeContext: FlyerStoreContext? = nil,
        acquireThreshold: Int = 3,
        flyerKitClient: FlippFlyerKitClient = FlippFlyerKitClient(),
        pcExpressClient: PCExpressClient = PCExpressClient(),
        maxSnippetLength: Int = 300,
        logger: FlyerAcquisitionLogging? = nil
    ) {
        self.storeContext = storeContext ?? .defaultAlberta
        self.acquireThreshold = acquireThreshold
        self.flyerKitClient = flyerKitClient
        self.pcExpressClient = pcExpressClient
        self.maxSnippetLength = maxSnippetLength
        self.logger = logger ?? ConsoleFlyerAcquisitionLogger()
    }

    func acquire(
        banner: FlyerBanner,
        from url: URL,
        sourceShape _: FlyerSourceShape?,
        storeContext _: String?
    ) async -> FlyerAcquiredContent {
        let label = FlyerAcquisitionLogLabel.make(for: banner)
        let prep = FlyerStorePreparationCatalog.preparation(for: banner.id, context: storeContext)

        // Flipp banners: the deterministic flyers-ng item fetch (two GETs).
        if let merchantID = prep.flippMerchantID,
           let result = await flyerKit(banner: banner, merchantID: merchantID, url: url, label: label) {
            return result
        }

        // Loblaw banners (RCSS / No Frills): the pcexpress flyersPage BFF.
        if let config = prep.pcExpress,
           let result = await pcExpress(banner: banner, config: config, url: url, label: label) {
            return result
        }

        // Reaching here means either no endpoint is configured, or the configured
        // endpoint errored / returned too few prices — say which, so a device log
        // reads honestly.
        let hasEndpoint = prep.flippMerchantID != nil || prep.pcExpress != nil
        logger.log("banner=\(label) phase=\(hasEndpoint ? "endpoint-short" : "endpoint-none") url=\(url.absoluteString)")
        return FlyerAcquiredContent(
            banner: banner,
            state: .acquiredNoPrices,
            acquisitionMethod: nil,
            sourceURL: url,
            finalURL: url,
            storeContext: storeContext.label,
            fetchedAt: Date(),
            message: hasEndpoint
                ? "The banner's structured flyer endpoint returned no usable items (fetch error or below the price threshold)."
                : "No structured flyer endpoint (Flipp/pcexpress) is configured for this banner."
        )
    }

    /// Fetches a Flipp banner's items from the flyers-ng API. Returns an `.acquired`
    /// result when it yields enough prices; `nil` on error or too-few items.
    private func flyerKit(
        banner: FlyerBanner,
        merchantID: Int,
        url: URL,
        label: String
    ) async -> FlyerAcquiredContent? {
        do {
            let json = try await flyerKitClient.fetchItemsJSON(
                merchantID: merchantID,
                postalCode: storeContext.postalCode
            )
            let prices = FlyerPriceSignal.priceSignalCount(in: json)
            logger.log("banner=\(label) phase=flyerkit merchant=\(merchantID) bytes=\(json.utf8.count) prices=\(prices)")
            guard prices >= acquireThreshold else { return nil }
            let result = acquired(banner: banner, url: url, json: json, prices: prices, source: "Flipp")
            logger.log("banner=\(label) phase=flyerkit-finish state=\(result.state.rawValue) prices=\(prices) bytes=\(result.payloadByteCount)")
            return result
        } catch {
            logger.log("banner=\(label) phase=flyerkit-error merchant=\(merchantID) error=\(description(for: error))")
            return nil
        }
    }

    /// Fetches a Loblaw banner's flyer items from the pcexpress BFF. Returns an
    /// `.acquired` result when it yields enough prices; `nil` on error or too-few items.
    private func pcExpress(
        banner: FlyerBanner,
        config: PCExpressClient.BannerConfig,
        url: URL,
        label: String
    ) async -> FlyerAcquiredContent? {
        do {
            let json = try await pcExpressClient.fetchItemsJSON(config: config)
            let prices = FlyerPriceSignal.priceSignalCount(in: json)
            logger.log("banner=\(label) phase=pcexpress banner=\(config.siteBanner) store=\(config.storeID) bytes=\(json.utf8.count) prices=\(prices)")
            guard prices >= acquireThreshold else { return nil }
            let result = acquired(banner: banner, url: url, json: json, prices: prices, source: "pcexpress")
            logger.log("banner=\(label) phase=pcexpress-finish state=\(result.state.rawValue) prices=\(prices) bytes=\(result.payloadByteCount)")
            return result
        } catch {
            logger.log("banner=\(label) phase=pcexpress-error banner=\(config.siteBanner) store=\(config.storeID) error=\(description(for: error))")
            return nil
        }
    }

    private func acquired(
        banner: FlyerBanner,
        url: URL,
        json: String,
        prices: Int,
        source: String
    ) -> FlyerAcquiredContent {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        return FlyerAcquiredContent(
            banner: banner,
            state: .acquired,
            acquisitionMethod: .endpointJSON,
            sourceURL: url,
            finalURL: url,
            storeContext: storeContext.label,
            fetchedAt: Date(),
            payloadContentType: "application/json; endpoint",
            payloadByteCount: trimmed.utf8.count,
            priceTokenCount: prices,
            renderedTextSnippet: snippet(from: trimmed),
            extractionPayload: trimmed.isEmpty ? nil : trimmed,
            message: "Read \(trimmed.utf8.count) bytes of \(source) flyer JSON with \(prices) price tokens."
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
