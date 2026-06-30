import Foundation
import WebKit
import UIKit

/// Acquires flyer content by rendering a banner's discovered URL in a `WKWebView`,
/// running the page's JavaScript, then reading the rendered visible text. This is
/// strategy 2 ("rendered fetch") from `FlyerContentAcquisitionPlan.md` — the path
/// `FlyerContentAcquisitionRouter` uses for JS-rendered (`dynamicHTML`) and
/// `unknown` sources, and the escalation when a static-HTML page is JS-gated.
///
/// The web view is hosted **in the key window** (invisible, non-interactive) so its
/// content process stays foreground and the page actually renders. To get past
/// store-selection gates, a `FlyerStoreContext` is injected before/after load:
/// geolocation is overridden, the postal code is seeded into common storage keys,
/// the store picker is driven, and the page is scrolled to trigger lazy content.
///
/// Two gates this cannot defeat are diagnosed rather than silently failing:
/// anti-bot walls (Loblaw/Akamai) and flyers isolated in a cross-origin iframe
/// (Flipp) whose text `innerText` cannot read — those are flagged for the
/// snapshot/OCR or endpoint path.
@MainActor
final class WebPageFlyerContentAcquirer: FlyerContentAcquiring {
    private let tickInterval: Duration
    private let maxTicks: Int
    private let priceThreshold: Int
    private let maxSnippetLength: Int
    private let maxOCRPages: Int
    private let maxStoreLocatorTicks: Int
    private let captureAcquireThreshold: Int
    private let enableOCR: Bool
    private let storeContext: FlyerStoreContext
    private let logger: FlyerAcquisitionLogging

    init(
        tickInterval: Duration = .milliseconds(600),
        maxTicks: Int = 24,
        priceThreshold: Int? = nil,
        maxSnippetLength: Int = 300,
        maxOCRPages: Int = 8,
        maxStoreLocatorTicks: Int = 8,
        // Captured flyer JSON is a far stronger signal than rendered text (a 300 KB
        // flyer-endpoint payload with a few price fields is unambiguously real data,
        // not chrome noise), so it acquires at a lower bar than the text threshold.
        captureAcquireThreshold: Int = 3,
        // OCR (createPDF + Vision) read only page chrome (0 prices) across every device
        // run and stalled the run on WEBP-failing pages, so it's off by default. The
        // network-capture + text/attribute harvest are the real price sources.
        enableOCR: Bool = false,
        storeContext: FlyerStoreContext? = nil,
        logger: FlyerAcquisitionLogging? = nil
    ) {
        self.tickInterval = tickInterval
        self.maxTicks = maxTicks
        self.maxOCRPages = maxOCRPages
        self.maxStoreLocatorTicks = maxStoreLocatorTicks
        self.captureAcquireThreshold = captureAcquireThreshold
        self.enableOCR = enableOCR
        // Default to the classifier's static threshold so the "real flyer content"
        // bar matches discovery. Resolved here (main-actor isolated) rather than as
        // a default argument, which would evaluate in a nonisolated context.
        self.priceThreshold = priceThreshold ?? FlyerSourceShapeClassifier.priceSignalThreshold
        self.maxSnippetLength = maxSnippetLength
        self.storeContext = storeContext ?? .defaultAlberta
        self.logger = logger ?? ConsoleFlyerAcquisitionLogger()
    }

    func acquire(
        banner: FlyerBanner,
        from url: URL,
        sourceShape: FlyerSourceShape?,
        storeContext _: String?
    ) async -> FlyerAcquiredContent {
        let label = FlyerAcquisitionLogLabel.make(for: banner)
        let prep = FlyerStorePreparationCatalog.preparation(for: banner.id, context: storeContext)
        logger.log("banner=\(label) phase=rendered-start url=\(url.absoluteString) store=\(storeContext.label) maxTicks=\(maxTicks) iframeExpected=\(prep.flyerInCrossOriginIframe) botWalled=\(prep.antiBotWalled)")

        let navigation = NavigationDelegate()
        let capture = FlyerNetworkCapture()
        let webView = makeHostedWebView(navigationDelegate: navigation, prep: prep, capture: capture)
        defer {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: FlyerNetworkCapture.messageHandlerName)
            webView.removeFromSuperview()
        }

        if webView.superview == nil {
            logger.log("banner=\(label) phase=rendered-warn reason=no-host-window (web view not mounted; render may idle-exit)")
        }

        await seedCookies(prep.cookies, for: url, in: webView)

        var request = URLRequest(url: url)
        request.setValue("en-CA", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 30
        webView.load(request)

        var bestText = ""
        var bestPriceCount = 0
        var noImprovementTicks = 0
        var ranPostLoad = false
        var lastURL = url
        var storeLocatorTicks = 0
        var lastPayloadCount = 0

        for tick in 0..<maxTicks {
            try? await Task.sleep(for: tickInterval)

            // Follow store-selection redirects: choosing a store often navigates to a
            // store-scoped flyer URL (e.g. Save-On `/sm/planning/rsid/<id>/circular`,
            // Sobeys `/store-locator`). When the URL changes, re-arm the picker and
            // reset the settle counter so we wait for the new page's flyer instead of
            // finishing on the intermediate page.
            if let current = webView.url, current != lastURL {
                lastURL = current
                ranPostLoad = false
                noImprovementTicks = 0
                logger.log("banner=\(label) phase=rendered-navigated url=\(current.absoluteString)")
            }

            let path = webView.url?.path.lowercased() ?? ""
            let onStoreScopedFlyer = path.contains("rsid") || path.contains("circular")
            let onStoreLocator = path.contains("locator")
                || path.contains("store-finder")
                || path.contains("find-a-store")
                || path.contains("find-store")

            if onStoreLocator { storeLocatorTicks += 1 } else { storeLocatorTicks = 0 }

            if navigation.isFinished, onStoreLocator, storeLocatorTicks <= maxStoreLocatorTicks {
                // Drive the store-locator each tick: fill the postal field, then once
                // results load, click the first store action so it navigates to the
                // store-scoped flyer. Capped so a locator we can't drive doesn't burn
                // the whole tick budget.
                let status = await evaluate(FlyerStoreInjection.storeLocatorScript(storeContext), in: webView)
                logger.log("banner=\(label) phase=rendered-store-locator t=\(storeLocatorTicks) \(status)")
            } else if navigation.isFinished, !ranPostLoad {
                ranPostLoad = true
                // Drive the store picker — but NOT once we've reached a store-scoped
                // flyer/circular page (e.g. Save-On `/sm/planning/rsid/<id>/circular`),
                // where clicking store buttons navigates us back OFF the flyer.
                if onStoreScopedFlyer {
                    logger.log("banner=\(label) phase=rendered-postload skipped reason=on-flyer-path path=\(path)")
                } else {
                    let status = await evaluate(FlyerStoreInjection.postLoadScript(storeContext), in: webView)
                    logger.log("banner=\(label) phase=rendered-postload \(status.isEmpty ? "did:0" : status)")
                }
            }
            _ = await evaluate(FlyerStoreInjection.scrollScript, in: webView)

            let text = await renderedText(of: webView)
            let priceCount = FlyerSourceShapeClassifier.priceTokenCount(in: text.lowercased())
            if priceCount > bestPriceCount {
                bestPriceCount = priceCount
                bestText = text
                noImprovementTicks = 0
            } else {
                if text.count > bestText.count { bestText = text }
                noImprovementTicks += 1
            }
            // Keep ticking while the page is still streaming flyer data to native —
            // Flipp/Salesforce item fetches arrive a few seconds after load, so don't
            // stop on stalled visible text while captured payloads are still growing.
            if capture.payloadCount > lastPayloadCount {
                lastPayloadCount = capture.payloadCount
                noImprovementTicks = 0
            }
            logger.log("banner=\(label) phase=rendered-tick n=\(tick + 1) prices=\(priceCount) best=\(bestPriceCount) chars=\(text.count) captured=\(capture.payloadCount) navFinished=\(navigation.isFinished) path=\(webView.url?.path ?? "?")")

            // Require the URL to have settled (no fresh redirect) before stopping, so
            // a post-store navigation isn't cut off on the intermediate page. Keep
            // ticking while a store-locator is still being driven, but bail once it's
            // exhausted its attempt budget so it doesn't burn all 24 ticks.
            let locatorExhausted = onStoreLocator && storeLocatorTicks > maxStoreLocatorTicks
            if navigation.isFinished, webView.url == lastURL,
               (!onStoreLocator || locatorExhausted),
               bestPriceCount >= priceThreshold || noImprovementTicks >= 5 {
                break
            }
        }

        let iframeHosts = await evaluate(FlyerStoreInjection.iframeDiagnosticScript, in: webView)
        if !iframeHosts.isEmpty {
            logger.log("banner=\(label) phase=rendered-iframes \(iframeHosts)")
        }

        // Diagnostic: the data-API-looking request URLs the page made. Reveals whether
        // a banner's item fetch fired (and where) when the JSON capture comes up empty.
        let requestSummary = capture.requestSummary
        if !requestSummary.isEmpty {
            logger.log("banner=\(label) phase=rendered-requests \(requestSummary)")
        }

        var method: FlyerAcquisitionMethod = .renderedHTML

        // First, the page's own flyer fetch/XHR (captured from every frame, incl. the
        // cross-origin Flipp iframe) — the most reliable structured price source.
        if bestPriceCount < priceThreshold, capture.payloadCount > 0 {
            let capturedText = capture.capturedText
            let capturedPrices = FlyerNetworkCapture.priceSignalCount(in: capturedText)
            logger.log("banner=\(label) phase=rendered-capture payloads=\(capture.payloadCount) bytes=\(capturedText.utf8.count) prices=\(capturedPrices)")
            if capturedPrices > bestPriceCount {
                bestPriceCount = capturedPrices
                bestText = capturedText
                method = .endpointJSON
            }
        }

        // If still short, optionally read the rendered pixels with OCR. Off by default:
        // OCR read only page chrome (0 prices) on every device run and stalled on
        // WEBP-failing pages. The web view is still mounted, so we can render it here.
        if enableOCR, bestPriceCount < priceThreshold {
            logger.log("banner=\(label) phase=rendered-ocr-start textPrices=\(bestPriceCount)")
            let ocr = await FlyerSnapshotOCR.harvest(
                from: webView,
                maxPages: maxOCRPages,
                maxTextLength: 8000
            ) { line in
                logger.log("banner=\(label) phase=rendered-ocr \(line)")
            }
            logger.log("banner=\(label) phase=rendered-ocr-finish prices=\(ocr.priceCount) chars=\(ocr.text.count)")
            if ocr.priceCount > bestPriceCount {
                bestPriceCount = ocr.priceCount
                bestText = ocr.text
                method = .imageOCR
            }
        }

        let finalURL = webView.url ?? url
        let trimmedText = bestText.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = renderedSnippet(from: trimmedText)
        let payloadBytes = trimmedText.utf8.count
        if let navError = navigation.error {
            logger.log("banner=\(label) phase=rendered-nav-error error=\(description(for: navError))")
        }

        let result = makeResult(
            banner: banner,
            url: url,
            finalURL: finalURL,
            prep: prep,
            method: method,
            bestPriceCount: bestPriceCount,
            payloadBytes: payloadBytes,
            trimmedText: trimmedText,
            snippet: snippet,
            iframeHosts: iframeHosts,
            navError: navigation.error
        )

        logger.log("banner=\(label) phase=rendered-finish state=\(result.state.rawValue) prices=\(result.priceTokenCount) bytes=\(result.payloadByteCount) finalURL=\(finalURL.absoluteString)")
        return result
    }

    private func makeResult(
        banner: FlyerBanner,
        url: URL,
        finalURL: URL,
        prep: FlyerStorePreparation,
        method: FlyerAcquisitionMethod,
        bestPriceCount: Int,
        payloadBytes: Int,
        trimmedText: String,
        snippet: String?,
        iframeHosts: String,
        navError: Error?
    ) -> FlyerAcquiredContent {
        let payloadContentType: String
        let readLabel: String
        switch method {
        case .imageOCR:
            payloadContentType = "text/plain; ocr"
            readLabel = "OCR"
        case .endpointJSON:
            payloadContentType = "application/json; captured"
            readLabel = "captured flyer JSON"
        default:
            payloadContentType = "text/plain; rendered"
            readLabel = "visible text"
        }

        // Captured flyer JSON acquires at a lower bar than rendered text.
        let acquireThreshold = method == .endpointJSON ? captureAcquireThreshold : priceThreshold
        if bestPriceCount >= acquireThreshold {
            return FlyerAcquiredContent(
                banner: banner,
                state: .acquired,
                acquisitionMethod: method,
                sourceURL: url,
                finalURL: finalURL,
                storeContext: storeContext.label,
                fetchedAt: Date(),
                payloadContentType: payloadContentType,
                payloadByteCount: payloadBytes,
                priceTokenCount: bestPriceCount,
                renderedTextSnippet: snippet,
                extractionPayload: trimmedText.isEmpty ? nil : trimmedText,
                message: "Read \(payloadBytes) bytes of \(readLabel) with \(bestPriceCount) price tokens."
            )
        }

        if let navError, trimmedText.isEmpty {
            return FlyerAcquiredContent(
                banner: banner,
                state: .failed,
                acquisitionMethod: method,
                sourceURL: url,
                finalURL: finalURL,
                storeContext: storeContext.label,
                fetchedAt: Date(),
                message: "Rendered fetch failed: \(description(for: navError))."
            )
        }

        // Rendered, but below the flyer-price threshold. Diagnose why so the result
        // routes to the right follow-up instead of reading as a generic gate miss.
        let reason: String
        if prep.flyerInCrossOriginIframe, !iframeHosts.isEmpty {
            reason = "flyer is in a cross-origin iframe (\(iframeHosts)); needs snapshot/OCR or the Flipp endpoint — innerText cannot read it"
        } else if prep.antiBotWalled, payloadBytes < 400 {
            reason = "anti-bot wall returned only a \(payloadBytes)-byte shell; a store context cannot clear it"
        } else if trimmedText.isEmpty {
            reason = "page rendered no visible text (store-selection gate or idle render)"
        } else {
            reason = "only \(bestPriceCount) price tokens in \(payloadBytes) bytes (below the \(priceThreshold) flyer threshold)"
        }

        return FlyerAcquiredContent(
            banner: banner,
            state: .acquiredNoPrices,
            acquisitionMethod: method,
            sourceURL: url,
            finalURL: finalURL,
            storeContext: storeContext.label,
            fetchedAt: Date(),
            payloadContentType: payloadContentType,
            payloadByteCount: payloadBytes,
            priceTokenCount: bestPriceCount,
            renderedTextSnippet: snippet,
            extractionPayload: trimmedText.isEmpty ? nil : trimmedText,
            message: "Rendered but no usable flyer prices: \(reason)."
        )
    }

    /// Builds a `WKWebView` mounted invisibly in the key window, with the
    /// store-context document-start script installed in every frame (so Flipp
    /// iframes also get the geolocation override).
    private func makeHostedWebView(
        navigationDelegate: NavigationDelegate,
        prep: FlyerStorePreparation,
        capture: FlyerNetworkCapture
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let script = WKUserScript(
            source: FlyerStoreInjection.documentStartScript(storeContext, extra: prep.documentStartScript),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(script)

        // Capture the page's own flyer-data fetch/XHR calls (all frames, incl. the
        // cross-origin Flipp iframe) — the most reliable structured price source.
        configuration.userContentController.add(capture, name: FlyerNetworkCapture.messageHandlerName)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: FlyerNetworkCapture.interceptorScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        let frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = navigationDelegate
        webView.isUserInteractionEnabled = false
        // Near-invisible but non-zero so WebKit keeps the layers/process live.
        webView.alpha = 0.01

        if let window = Self.keyWindow() {
            window.addSubview(webView)
            window.sendSubviewToBack(webView)
        }
        return webView
    }

    private func seedCookies(_ cookies: [String: String], for url: URL, in webView: WKWebView) async {
        guard !cookies.isEmpty, let host = url.host else { return }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for (name, value) in cookies {
            guard let cookie = HTTPCookie(properties: [
                .domain: host,
                .path: "/",
                .name: name,
                .value: value,
                .secure: "TRUE"
            ]) else { continue }
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
    }

    private static func keyWindow() -> UIWindow? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = windowScenes.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    private func renderedText(of webView: WKWebView) async -> String {
        // Harvest visible text plus image alt-text/aria-labels/titles, where flyer
        // viewers often embed prices even when the visible price is an image.
        await evaluate(FlyerStoreInjection.textHarvestScript, in: webView)
    }

    private func evaluate(_ javaScript: String, in webView: WKWebView) async -> String {
        do {
            let result = try await webView.evaluateJavaScript(javaScript)
            if let string = result as? String { return string }
            if let number = result as? NSNumber { return number.stringValue }
            return ""
        } catch {
            return ""
        }
    }

    private func renderedSnippet(from text: String) -> String? {
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

/// Captures navigation completion/failure for the polling loop.
@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    var isFinished = false
    var error: Error?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // A new navigation began (e.g. a store-selection redirect). Re-arm so the
        // polling loop waits for this page instead of treating the prior page's
        // completion as final.
        isFinished = false
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isFinished = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        self.error = error
        isFinished = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        self.error = error
        isFinished = true
    }
}
