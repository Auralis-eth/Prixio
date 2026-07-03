import Foundation
import SwiftData
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
        let viewModel = FlyerCheckViewModel(
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
        #expect(viewModel.acquisition(for: supportedBanner)?.acquisitionMethod == .endpointJSON)
        #expect(viewModel.acquisition(for: unsupportedBanner)?.state == .unsupported)
    }

    @Test("Concurrent acquisition publishes a result for every supported banner")
    func acquiresAllSupportedBannersConcurrently() async throws {
        // The acquisition run fans out in a task group; every banner must still
        // land a published result regardless of completion order.
        let bannerIDs: [FlyerBannerID] = [.safeway, .sobeys, .walmartSupercentre]
        let banners = try bannerIDs.map { try #require(FlyerBannerCatalog.banner(for: $0)) }
        let connectors = try banners.map { banner in
            FlyerSourceConnector(
                banner: banner,
                officialEntryURLs: [try #require(URL(string: "https://\(banner.id.rawValue)-grocer.ca/flyer"))],
                allowedDomains: ["\(banner.id.rawValue)-grocer.ca"],
                searchQueries: [],
                unsupportedReason: nil
            )
        }
        let documents = try connectors.reduce(into: [URL: Result<FlyerFetchedDocument, Error>]()) { docs, connector in
            let url = try #require(connector.officialEntryURLs.first)
            docs[url] = foundDocument(url: url)
        }
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: connectors,
            fetcher: FakeAcquisitionFetcher(documents: documents),
            searchProvider: EmptyFlyerSearchProvider()
        )
        let acquirer = RecordingFlyerContentAcquirer()
        let viewModel = FlyerCheckViewModel(
            coordinator: coordinator,
            acquirer: acquirer,
            initialResults: banners.map(seededResult)
        )

        await viewModel.checkFlyers()
        await viewModel.acquireContent()

        #expect(viewModel.acquisitionState == .completed)
        // Completion order is nondeterministic under the task group — compare as sets.
        #expect(Set(acquirer.requestedBanners) == Set(bannerIDs))
        for banner in banners {
            #expect(viewModel.acquisition(for: banner)?.state == .acquired)
        }
    }

    @Test("runFullCheck runs every stage and matches the real shopping list")
    func fullCheckRunsAllStagesAgainstRealList() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .safeway))
        let connector = FlyerSourceConnector(
            banner: banner,
            officialEntryURLs: [try #require(URL(string: "https://safeway-grocer.ca/flyer"))],
            allowedDomains: ["safeway-grocer.ca"],
            searchQueries: [],
            unsupportedReason: nil
        )
        let url = try #require(connector.officialEntryURLs.first)
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: [connector],
            fetcher: FakeAcquisitionFetcher(documents: [url: foundDocument(url: url)]),
            searchProvider: EmptyFlyerSearchProvider()
        )
        // Whole Milk direct-matches the list item; the cheaper Soy Milk is similar
        // but not a match, so it must surface as an alternative suggestion.
        let acquirer = RecordingFlyerContentAcquirer(
            payload: #"[{"name":"Whole Milk","price":3.99},{"name":"Soy Milk","price":2.99}]"#
        )
        let viewModel = FlyerCheckViewModel(
            coordinator: coordinator,
            acquirer: acquirer,
            initialResults: [seededResult(banner)]
        )

        let container = try ModelContainer(
            for: ShoppingList.self, ShoppingListItem.self, FlyerPriceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let repository = ShoppingListRepository(context: context)
        let list = try repository.fetchOrCreateDefaultList()
        _ = try repository.addItem(to: list, displayName: "Whole Milk", brand: nil, quantityNote: nil)

        await viewModel.runFullCheck(context: context)

        #expect(viewModel.runState == .completed)
        #expect(viewModel.acquisitionState == .completed)
        #expect(viewModel.extractionState == .completed)
        #expect(viewModel.matchState == .completed)
        #expect(viewModel.matchedAgainstRealList)
        #expect(!viewModel.isRunningFullCheck)

        let milk = try #require(viewModel.matches.first)
        #expect(milk.deals.map(\.candidate.productName) == ["Whole Milk"])
        let alternatives = viewModel.alternatives(forItemKey: milk.itemKey)
        #expect(alternatives?.alternatives.map(\.candidate.productName) == ["Soy Milk"])
        #expect(viewModel.reviewableItems.count == 1)
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
        let viewModel = FlyerCheckViewModel(
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
        let viewModel = FlyerCheckViewModel(
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
    func routerProcessesStaticHTMLInAppWithoutEndpoint() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .realCanadianSuperstore))
        let staticAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquired, method: .staticHTML)
        let endpointAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquired, method: .endpointJSON)
        let router = FlyerContentAcquisitionRouter(
            staticAcquirer: staticAcquirer,
            endpointAcquirer: endpointAcquirer
        )

        let result = await router.acquire(
            banner: banner,
            from: try #require(URL(string: "https://a-grocer.ca/flyer")),
            sourceShape: .html,
            storeContext: nil
        )

        #expect(staticAcquirer.requestedBanners == [banner.id])
        #expect(endpointAcquirer.requestedBanners.isEmpty)
        #expect(result.acquisitionMethod == .staticHTML)
    }

    @Test
    func routerRoutesDynamicHTMLToEndpoint() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .safeway))
        let staticAcquirer = RecordingFlyerContentAcquirer(method: .staticHTML)
        let endpointAcquirer = RecordingFlyerContentAcquirer(method: .endpointJSON)
        let router = FlyerContentAcquisitionRouter(
            staticAcquirer: staticAcquirer,
            endpointAcquirer: endpointAcquirer
        )

        let result = await router.acquire(
            banner: banner,
            from: try #require(URL(string: "https://b-grocer.ca/flyer")),
            sourceShape: .dynamicHTML,
            storeContext: nil
        )

        #expect(endpointAcquirer.requestedBanners == [banner.id])
        #expect(staticAcquirer.requestedBanners.isEmpty)
        #expect(result.acquisitionMethod == .endpointJSON)
    }

    @Test
    func routerEscalatesStaticHTMLWithoutPricesToEndpoint() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .noFrills))
        // Static HTML that yields no prices (JS-gated page) should escalate.
        let staticAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquiredNoPrices, method: .staticHTML)
        let endpointAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquired, method: .endpointJSON)
        let router = FlyerContentAcquisitionRouter(
            staticAcquirer: staticAcquirer,
            endpointAcquirer: endpointAcquirer
        )

        let result = await router.acquire(
            banner: banner,
            from: try #require(URL(string: "https://c-grocer.ca/flyer")),
            sourceShape: .html,
            storeContext: nil
        )

        #expect(staticAcquirer.requestedBanners == [banner.id])
        #expect(endpointAcquirer.requestedBanners == [banner.id])
        #expect(result.acquisitionMethod == .endpointJSON)
        #expect(result.state == .acquired)
    }

    @Test
    func routerDoesNotEscalateJSONWithoutDollarTokens() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .saveOnFoods))
        // JSON has its own pipeline; a zero `$` count must not trigger the endpoint path.
        let staticAcquirer = RecordingFlyerContentAcquirer(cannedState: .acquiredNoPrices, method: .endpointJSON)
        let endpointAcquirer = RecordingFlyerContentAcquirer(method: .endpointJSON)
        let router = FlyerContentAcquisitionRouter(
            staticAcquirer: staticAcquirer,
            endpointAcquirer: endpointAcquirer
        )

        let result = await router.acquire(
            banner: banner,
            from: try #require(URL(string: "https://d-grocer.ca/flyer.json")),
            sourceShape: .json,
            storeContext: nil
        )

        #expect(staticAcquirer.requestedBanners == [banner.id])
        #expect(endpointAcquirer.requestedBanners.isEmpty)
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
    func preparationCatalogMapsBannersToTheirFlyerEndpoint() {
        let context = FlyerStoreContext.defaultAlberta

        // Flipp banners carry a merchant id.
        let flippMerchants: [FlyerBannerID: Int] = [
            .safeway: 2126, .sobeys: 2072, .freshCo: 2267,
            .saveOnFoods: 2062, .walmartSupercentre: 234, .coOp: 2051
        ]
        for (id, merchant) in flippMerchants {
            let prep = FlyerStorePreparationCatalog.preparation(for: id, context: context)
            #expect(prep.flippMerchantID == merchant)
            #expect(prep.pcExpress == nil)
        }

        // Loblaw banners carry a pcexpress config; Flipp is not used.
        for id in [FlyerBannerID.realCanadianSuperstore, .noFrills] {
            let prep = FlyerStorePreparationCatalog.preparation(for: id, context: context)
            #expect(prep.flippMerchantID == nil)
            #expect(prep.pcExpress != nil)
        }

        // Unsupported banners have no endpoint at all.
        for id in [FlyerBannerID.costco, .fresonBros] {
            let prep = FlyerStorePreparationCatalog.preparation(for: id, context: context)
            #expect(prep.flippMerchantID == nil)
            #expect(prep.pcExpress == nil)
        }
    }

    @Test
    func priceSignalCountsDollarAndJsonPriceForms() {
        #expect(FlyerPriceSignal.priceSignalCount(in: "Milk $3.99 Bread $2.49") == 2)

        let json = "{\"items\":[{\"name\":\"Milk\",\"current_price\":3.99},{\"name\":\"Eggs\",\"price\":4.49}]}"
        // Two JSON price fields, no `$` tokens.
        #expect(FlyerPriceSignal.priceSignalCount(in: json) == 2)
    }

    @Test
    func priceSignalKeepsJSONAndRejectsJavaScript() {
        // Real flyer payloads are JSON objects/arrays (incl. leading whitespace/BOM).
        #expect(FlyerPriceSignal.isJSONPayload("{\"items\":[]}"))
        #expect(FlyerPriceSignal.isJSONPayload("  [1,2,3]"))
        #expect(FlyerPriceSignal.isJSONPayload("\u{FEFF}{\"a\":1}"))
        // JavaScript bundles (e.g. Flipp's webpack chunks) and HTML must be rejected,
        // even though their source text mentions price-like words.
        #expect(!FlyerPriceSignal.isJSONPayload("(self.webpackChunkFlipp=self.webpackChunkFlipp||[]).push([[4736],{5023:function(){var price}}"))
        #expect(!FlyerPriceSignal.isJSONPayload("!function(e){\"price\"}"))
        #expect(!FlyerPriceSignal.isJSONPayload("<!DOCTYPE html><div>$3.99</div>"))
        #expect(!FlyerPriceSignal.isJSONPayload(""))
    }

    // MARK: - EndpointFlyerContentAcquirer (the structured-API dispatcher)

    @Test("Flipp banner acquires items via the flyers-ng client")
    func endpointAcquirerFetchesFlippItems() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .coOp))
        var client = FlippFlyerKitClient()
        client.makeSessionID = { "1234567890123456" }
        client.fetch = { url in
            if url.absoluteString.contains("flyer_items") {
                return Data(#"[{"name":"Milk","price":3.99},{"name":"Eggs","price":4.49},{"name":"Bread","price":2.99}]"#.utf8)
            }
            return Data(#"{"flyers":[{"id":42,"merchant_id":2051,"valid_from":"2000-01-01","valid_to":"2999-12-31"}]}"#.utf8)
        }
        let acquirer = EndpointFlyerContentAcquirer(flyerKitClient: client)

        let result = await acquirer.acquire(
            banner: banner,
            from: try #require(URL(string: "https://food.crs/more/foodflyers")),
            sourceShape: .dynamicHTML,
            storeContext: nil
        )

        #expect(result.state == .acquired)
        #expect(result.acquisitionMethod == .endpointJSON)
        #expect(result.priceTokenCount == 3)
        #expect(result.extractionPayload?.contains("Milk") == true)
    }

    @Test("Loblaw banner acquires items via the pcexpress client")
    func endpointAcquirerFetchesPCExpressItems() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .noFrills))
        var client = PCExpressClient()
        client.fetch = { _ in
            Data(#"{"layout":{"sections":{"productListingSection":{"components":[{"data":{"productGrid":{"productTiles":[{"title":"Milk","pricing":{"price":"3.99"}},{"title":"Eggs","pricing":{"price":"4.49"}},{"title":"Bread","pricing":{"price":"2.99"}}]}}}]}}}}"#.utf8)
        }
        let acquirer = EndpointFlyerContentAcquirer(pcExpressClient: client)

        let result = await acquirer.acquire(
            banner: banner,
            from: try #require(URL(string: "https://www.nofrills.ca/print-flyer")),
            sourceShape: .dynamicHTML,
            storeContext: nil
        )

        #expect(result.state == .acquired)
        #expect(result.acquisitionMethod == .endpointJSON)
        #expect(result.priceTokenCount == 3)
        #expect(result.extractionPayload?.contains("Eggs") == true)
    }

    @Test("A configured endpoint that errors reports an honest no-prices result")
    func endpointAcquirerReportsEndpointFailureHonestly() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .coOp))
        var client = FlippFlyerKitClient()
        client.fetch = { _ in throw FlippFlyerKitError.badResponse }
        let acquirer = EndpointFlyerContentAcquirer(flyerKitClient: client)

        let result = await acquirer.acquire(
            banner: banner,
            from: try #require(URL(string: "https://food.crs/more/foodflyers")),
            sourceShape: .dynamicHTML,
            storeContext: nil
        )

        #expect(result.state == .acquiredNoPrices)
        #expect(result.acquisitionMethod == nil)
        // The endpoint exists but failed — the message must not claim it is unconfigured.
        #expect(result.message.contains("returned no usable items"))
    }

    @Test("Items below the price threshold do not acquire")
    func endpointAcquirerRespectsPriceThreshold() async throws {
        let banner = try #require(FlyerBannerCatalog.banner(for: .coOp))
        var client = FlippFlyerKitClient()
        client.makeSessionID = { "1234567890123456" }
        client.fetch = { url in
            if url.absoluteString.contains("flyer_items") {
                return Data(#"[{"name":"Milk","price":3.99},{"name":"Eggs","price":4.49}]"#.utf8)
            }
            return Data(#"{"flyers":[{"id":42,"merchant_id":2051,"valid_from":"2000-01-01","valid_to":"2999-12-31"}]}"#.utf8)
        }
        let acquirer = EndpointFlyerContentAcquirer(acquireThreshold: 3, flyerKitClient: client)

        let result = await acquirer.acquire(
            banner: banner,
            from: try #require(URL(string: "https://food.crs/more/foodflyers")),
            sourceShape: .dynamicHTML,
            storeContext: nil
        )

        #expect(result.state == .acquiredNoPrices)
        #expect(result.message.contains("returned no usable items"))
    }

    @Test("A banner with no endpoint reports the configuration gap")
    func endpointAcquirerReportsMissingEndpoint() async throws {
        // Freson has neither a Flipp merchant id nor a pcexpress config, so the
        // acquirer makes no network calls and reports the gap explicitly.
        let banner = try #require(FlyerBannerCatalog.banner(for: .fresonBros))
        let acquirer = EndpointFlyerContentAcquirer()

        let result = await acquirer.acquire(
            banner: banner,
            from: try #require(URL(string: "https://fresonbros.com/weekly-flyer/")),
            sourceShape: .dynamicHTML,
            storeContext: nil
        )

        #expect(result.state == .acquiredNoPrices)
        #expect(result.acquisitionMethod == nil)
        #expect(result.message.contains("No structured flyer endpoint"))
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
    private let payload: String?

    init(
        cannedState: FlyerAcquisitionState = .acquired,
        method: FlyerAcquisitionMethod = .endpointJSON,
        payload: String? = nil
    ) {
        self.cannedState = cannedState
        self.method = method
        self.payload = payload
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
            extractionPayload: payload,
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
