import Foundation
import Testing
@testable import Prixio

@MainActor
struct FlyerContentAcquisitionTests {
    @Test
    func acquiresContentForSupportedBannersAndSkipsUnsupported() async throws {
        let supportedBanner = try #require(FlyerBannerCatalog.banner(for: .realCanadianSuperstore))
        let unsupportedBanner = try #require(FlyerBannerCatalog.banner(for: .costco))

        let supported = FlyerSourceConnector(
            banner: supportedBanner,
            officialEntryURLs: [try #require(URL(string: "https://a-grocer.ca/flyer"))],
            allowedDomains: ["a-grocer.ca"],
            searchQueries: [],
            unsupportedReason: nil
        )
        let unsupported = FlyerSourceConnector(
            banner: unsupportedBanner,
            officialEntryURLs: [],
            allowedDomains: [],
            searchQueries: [],
            unsupportedReason: "Stubbed unsupported."
        )
        let knownURL = try #require(supported.officialEntryURLs.first)
        let fetcher = FakeAcquisitionFetcher(documents: [
            knownURL: foundDocument(url: knownURL)
        ])
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: [supported, unsupported],
            fetcher: fetcher,
            searchProvider: EmptyFlyerSearchProvider()
        )
        let acquirer = RecordingFlyerContentAcquirer()
        let viewModel = FlyerProcessingPOCViewModel(
            coordinator: coordinator,
            acquirer: acquirer,
            initialResults: [
                seededResult(supportedBanner),
                seededResult(unsupportedBanner)
            ]
        )

        await viewModel.checkFlyers()
        #expect(viewModel.canAcquireContent)

        await viewModel.acquireContent()

        #expect(viewModel.acquisitionState == .completed)
        // Only the supported banner is rendered; the unsupported one is recorded
        // without any acquisition work.
        #expect(acquirer.requestedBanners == [.realCanadianSuperstore])
        #expect(viewModel.acquisition(for: supportedBanner)?.state == .acquired)
        #expect(viewModel.acquisition(for: supportedBanner)?.acquisitionMethod == .renderedHTML)
        #expect(viewModel.acquisition(for: unsupportedBanner)?.state == .unsupported)
    }

    @Test
    func recordsMissingSourceWhenDiscoveryHasNoSelectedURL() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .safeway))
        let connector = FlyerSourceConnector(
            banner: banner,
            officialEntryURLs: [try #require(URL(string: "https://b-grocer.ca/flyer"))],
            allowedDomains: ["b-grocer.ca"],
            searchQueries: ["Example query"],
            unsupportedReason: nil
        )
        let knownURL = try #require(connector.officialEntryURLs.first)
        let fetcher = FakeAcquisitionFetcher(documents: [
            knownURL: .failure(FakeAcquisitionError.unavailable)
        ])
        // Missing key → fallbackUnavailable, which carries no selectedURL.
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: [connector],
            fetcher: fetcher,
            searchProvider: EmptyFlyerSearchProvider(error: FlyerSearchError.missingAPIKey)
        )
        let acquirer = RecordingFlyerContentAcquirer()
        let viewModel = FlyerProcessingPOCViewModel(
            coordinator: coordinator,
            acquirer: acquirer,
            initialResults: [seededResult(banner)]
        )

        await viewModel.checkFlyers()
        #expect(viewModel.results.first?.state == .fallbackUnavailable)

        await viewModel.acquireContent()

        #expect(acquirer.requestedBanners.isEmpty)
        let content = try #require(viewModel.acquisition(for: banner))
        #expect(content.state == .failed)
        #expect(content.sourceURL == nil)
        #expect(content.message.contains("No discovered source URL"))
    }

    @Test
    func cannotAcquireContentBeforeDiscoveryCompletes() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .safeway))
        let acquirer = RecordingFlyerContentAcquirer()
        let viewModel = FlyerProcessingPOCViewModel(
            coordinator: FlyerDiscoveryCoordinator(
                connectors: [],
                fetcher: FakeAcquisitionFetcher(documents: [:]),
                searchProvider: EmptyFlyerSearchProvider()
            ),
            acquirer: acquirer,
            initialResults: [seededResult(banner)]
        )

        #expect(!viewModel.canAcquireContent)
        // No-op before discovery has run.
        await viewModel.acquireContent()
        #expect(viewModel.acquisitionState == .idle)
        #expect(acquirer.requestedBanners.isEmpty)
    }

    @Test
    func routerProcessesStaticHTMLInAppWithoutRendering() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .realCanadianSuperstore))
        let staticAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquired, method: .staticHTML)
        let renderedAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquired, method: .renderedHTML)
        let router = FlyerContentAcquisitionRouter(
            staticAcquirer: staticAcquirer,
            renderedAcquirer: renderedAcquirer
        )

        let result = await router.acquire(
            banner: banner,
            from: try #require(URL(string: "https://a-grocer.ca/flyer")),
            sourceShape: .html,
            storeContext: nil
        )

        #expect(staticAcquirer.requestedBanners == [banner.id])
        #expect(renderedAcquirer.requestedBanners.isEmpty)
        #expect(result.acquisitionMethod == .staticHTML)
    }

    @Test
    func routerRendersDynamicHTMLSourcesWithWebView() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .safeway))
        let staticAcquirer = RecordingFlyerContentAcquirer(method: .staticHTML)
        let renderedAcquirer = RecordingFlyerContentAcquirer(method: .renderedHTML)
        let router = FlyerContentAcquisitionRouter(
            staticAcquirer: staticAcquirer,
            renderedAcquirer: renderedAcquirer
        )

        let result = await router.acquire(
            banner: banner,
            from: try #require(URL(string: "https://b-grocer.ca/flyer")),
            sourceShape: .dynamicHTML,
            storeContext: nil
        )

        #expect(renderedAcquirer.requestedBanners == [banner.id])
        #expect(staticAcquirer.requestedBanners.isEmpty)
        #expect(result.acquisitionMethod == .renderedHTML)
    }

    @Test
    func routerEscalatesStaticHTMLWithoutPricesToRenderedFetch() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .noFrills))
        // Static HTML that yields no prices (JS-gated page) should escalate.
        let staticAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquiredNoPrices, method: .staticHTML)
        let renderedAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquired, method: .renderedHTML)
        let router = FlyerContentAcquisitionRouter(
            staticAcquirer: staticAcquirer,
            renderedAcquirer: renderedAcquirer
        )

        let result = await router.acquire(
            banner: banner,
            from: try #require(URL(string: "https://c-grocer.ca/flyer")),
            sourceShape: .html,
            storeContext: nil
        )

        #expect(staticAcquirer.requestedBanners == [banner.id])
        #expect(renderedAcquirer.requestedBanners == [banner.id])
        #expect(result.acquisitionMethod == .renderedHTML)
        #expect(result.state == .acquired)
    }

    @Test
    func routerDoesNotEscalateJSONWithoutDollarTokens() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .saveOnFoods))
        // JSON has its own pipeline; a zero `$` count must not trigger a render.
        let staticAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquiredNoPrices, method: .endpointJSON)
        let renderedAcquirer = RecordingFlyerContentAcquirer(method: .renderedHTML)
        let router = FlyerContentAcquisitionRouter(
            staticAcquirer: staticAcquirer,
            renderedAcquirer: renderedAcquirer
        )

        let result = await router.acquire(
            banner: banner,
            from: try #require(URL(string: "https://d-grocer.ca/flyer.json")),
            sourceShape: .json,
            storeContext: nil
        )

        #expect(staticAcquirer.requestedBanners == [banner.id])
        #expect(renderedAcquirer.requestedBanners.isEmpty)
        #expect(result.acquisitionMethod == .endpointJSON)
    }

    @Test
    func staticAcquirerProcessesServerRenderedHTMLPrices() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .fresonBros))
        let url = try #require(URL(string: "https://e-grocer.ca/weekly-flyer"))
        let html = """
        <html><body><h1>Weekly flyer deals</h1>\
        <p>Milk $3.99</p><p>Bread $2.49</p><p>Eggs $4.99</p>\
        <p>Apples $1.99</p><p>Cheese $7.49</p><p>Coffee $9.99</p></body></html>
        """
        let fetcher = FakeRawContentFetcher(.success(FlyerRawContent(
            finalURL: url,
            statusCode: 200,
            mimeType: "text/html",
            byteCount: html.utf8.count,
            bodyText: html
        )))
        let acquirer = StaticFlyerContentAcquirer(fetcher: fetcher)

        let result = await acquirer.acquire(banner: banner, from: url, sourceShape: .html, storeContext: nil)

        #expect(result.state == .acquired)
        #expect(result.acquisitionMethod == .staticHTML)
        #expect(result.priceTokenCount == 6)
    }

    @Test
    func staticAcquirerReportsNoPricesForJSShell() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .fresonBros))
        let url = try #require(URL(string: "https://e-grocer.ca/flyer"))
        let shell = "<html><body><div id=\"root\"></div><script src=\"bundle.js\"></script></body></html>"
        let fetcher = FakeRawContentFetcher(.success(FlyerRawContent(
            finalURL: url,
            statusCode: 200,
            mimeType: "text/html",
            byteCount: shell.utf8.count,
            bodyText: shell
        )))
        let acquirer = StaticFlyerContentAcquirer(fetcher: fetcher)

        let result = await acquirer.acquire(banner: banner, from: url, sourceShape: .html, storeContext: nil)

        // A JS shell yields no readable prices, so the router can escalate.
        #expect(result.state == .acquiredNoPrices)
        #expect(result.priceTokenCount == 0)
    }

    @Test
    func staticAcquirerProcessesJSONEndpoint() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .saveOnFoods))
        let url = try #require(URL(string: "https://e-grocer.ca/flyer.json"))
        let json = "{\"items\":[{\"name\":\"Milk\",\"price\":\"$3.99\"},{\"name\":\"Bread\",\"price\":\"$2.49\"}]}"
        let fetcher = FakeRawContentFetcher(.success(FlyerRawContent(
            finalURL: url,
            statusCode: 200,
            mimeType: "application/json",
            byteCount: json.utf8.count,
            bodyText: json
        )))
        let acquirer = StaticFlyerContentAcquirer(fetcher: fetcher)

        let result = await acquirer.acquire(banner: banner, from: url, sourceShape: .json, storeContext: nil)

        #expect(result.state == .acquired)
        #expect(result.acquisitionMethod == .endpointJSON)
        #expect(result.priceTokenCount == 2)
    }

    @Test
    func staticAcquirerReportsFailedWhenFetchThrows() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .saveOnFoods))
        let url = try #require(URL(string: "https://e-grocer.ca/flyer"))
        let acquirer = StaticFlyerContentAcquirer(fetcher: FakeRawContentFetcher(.failure(FakeRawContentError())))

        let result = await acquirer.acquire(banner: banner, from: url, sourceShape: .html, storeContext: nil)

        #expect(result.state == .failed)
        #expect(result.message.contains("Static fetch failed"))
    }

    @Test
    func preparationCatalogFlagsLoblawAntiBotAndFlippFamilyIframe() {
        let context = FlyerStoreContext.defaultAlberta

        for id in [FlyerBannerID.realCanadianSuperstore, .noFrills] {
            let prep = FlyerStorePreparationCatalog.preparation(for: id, context: context)
            #expect(prep.antiBotWalled)
            #expect(!prep.flyerInCrossOriginIframe)
        }

        for id in [FlyerBannerID.safeway, .sobeys, .freshCo, .fresonBros] {
            let prep = FlyerStorePreparationCatalog.preparation(for: id, context: context)
            #expect(prep.flyerInCrossOriginIframe)
            #expect(!prep.antiBotWalled)
        }

        // Save-On is a Salesforce page (readable main-document text), not Flipp.
        for id in [FlyerBannerID.saveOnFoods, .walmartSupercentre, .coOp] {
            let prep = FlyerStorePreparationCatalog.preparation(for: id, context: context)
            #expect(!prep.antiBotWalled)
            #expect(!prep.flyerInCrossOriginIframe)
        }
    }

    @Test
    func documentStartScriptSeedsPostalCodeAndGeolocationOverride() {
        let context = FlyerStoreContext.defaultAlberta
        let script = FlyerStoreInjection.documentStartScript(context, extra: "window.__extra=1;")

        #expect(script.contains(context.postalCode))
        #expect(script.contains("\(context.latitude)"))
        #expect(script.contains("getCurrentPosition"))
        #expect(script.contains("flipp_postal_code"))
        // The per-banner extra is appended.
        #expect(script.contains("window.__extra=1;"))
    }

    @Test
    func postLoadScriptDrivesStorePickerWithSpacedPostalCode() {
        let context = FlyerStoreContext.defaultAlberta
        let script = FlyerStoreInjection.postLoadScript(context)

        #expect(script.contains(context.postalCodeSpaced))
        #expect(script.contains("set( my)? store"))
        #expect(script.contains("postal"))
    }

    @Test
    func storeLocatorScriptFillsPostalThenClicksStore() {
        let context = FlyerStoreContext.defaultAlberta
        let script = FlyerStoreInjection.storeLocatorScript(context)

        #expect(script.contains(context.postalCodeSpaced))
        #expect(script.contains("postal-filled"))
        #expect(script.contains("shop this store"))
    }

    @Test
    func networkCaptureCountsDollarAndJsonPriceForms() {
        #expect(FlyerNetworkCapture.priceSignalCount(in: "Milk $3.99 Bread $2.49") == 2)

        let json = "{\"items\":[{\"name\":\"Milk\",\"current_price\":3.99},{\"name\":\"Eggs\",\"price\":4.49}]}"
        // Two JSON price fields, no `$` tokens.
        #expect(FlyerNetworkCapture.priceSignalCount(in: json) == 2)

        // The interceptor hooks both fetch and XHR and posts to the native handler.
        #expect(FlyerNetworkCapture.interceptorScript.contains("XMLHttpRequest"))
        #expect(FlyerNetworkCapture.interceptorScript.contains(FlyerNetworkCapture.messageHandlerName))
    }

    private func seededResult(_ banner: FlyerBanner) -> FlyerDiscoveryResult {
        FlyerDiscoveryResult(
            banner: banner,
            state: .failed,
            selectedURL: nil,
            method: nil,
            message: "Not checked yet."
        )
    }

    private func foundDocument(url: URL) -> Result<FlyerFetchedDocument, Error> {
        .success(FlyerFetchedDocument(
            finalURL: url,
            statusCode: 200,
            mimeType: "text/html",
            byteCount: 128,
            sourceShape: .html,
            contentSnippet: "Weekly flyer deals",
            usefulnessSignals: ["flyer"]
        ))
    }
}

private enum FakeAcquisitionError: Error {
    case unavailable
}

@MainActor
private final class FakeAcquisitionFetcher: FlyerDocumentFetching {
    private let documents: [URL: Result<FlyerFetchedDocument, Error>]

    init(documents: [URL: Result<FlyerFetchedDocument, Error>]) {
        self.documents = documents
    }

    func fetch(_ url: URL) async throws -> FlyerFetchedDocument {
        switch documents[url] ?? .failure(FakeAcquisitionError.unavailable) {
        case .success(let document):
            return document
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
private final class EmptyFlyerSearchProvider: FlyerSearchProviding {
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func search(query: String) async throws -> [FlyerSearchResult] {
        if let error {
            throw error
        }
        return []
    }
}

@MainActor
private final class RecordingFlyerContentAcquirer: FlyerContentAcquiring {
    private(set) var requestedBanners: [FlyerBannerID] = []
    private(set) var requestedShapes: [FlyerSourceShape?] = []
    private let cannedState: FlyerAcquisitionState
    private let method: FlyerAcquisitionMethod

    init(
        cannedState: FlyerAcquisitionState = .acquired,
        method: FlyerAcquisitionMethod = .renderedHTML
    ) {
        self.cannedState = cannedState
        self.method = method
    }

    func acquire(
        banner: FlyerBanner,
        from url: URL,
        sourceShape: FlyerSourceShape?,
        storeContext: String?
    ) async -> FlyerAcquiredContent {
        requestedBanners.append(banner.id)
        requestedShapes.append(sourceShape)
        return FlyerAcquiredContent(
            banner: banner,
            state: cannedState,
            acquisitionMethod: method,
            sourceURL: url,
            finalURL: url,
            payloadContentType: "text/plain",
            payloadByteCount: 1024,
            priceTokenCount: cannedState == .acquired ? 12 : 0,
            renderedTextSnippet: "Milk $3.99 Bread $2.49",
            message: "Canned acquisition result."
        )
    }
}

private struct FakeRawContentError: Error {}

@MainActor
private final class FakeRawContentFetcher: FlyerRawContentFetching {
    private let result: Result<FlyerRawContent, Error>

    init(_ result: Result<FlyerRawContent, Error>) {
        self.result = result
    }

    func fetchRaw(_ url: URL) async throws -> FlyerRawContent {
        try result.get()
    }
}
