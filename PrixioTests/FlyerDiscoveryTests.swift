import Foundation
import Testing
@testable import Prixio

@MainActor
struct FlyerDiscoveryTests {
    @Test
    func bannerCatalogContainsAlbertaBannersInRankOrder() {
        let banners = FlyerBannerCatalog.albertaBanners

        #expect(banners.count == 10)
        #expect(banners.map(\.id) == [
            .realCanadianSuperstore,
            .safeway,
            .sobeys,
            .costco,
            .walmartSupercentre,
            .noFrills,
            .saveOnFoods,
            .freshCo,
            .coOp,
            .fresonBros
        ])
        #expect(banners.map(\.rank) == Array(1...10))
    }

    @Test
    func connectorCatalogUsesOfficialDomainsOnly() throws {
        let connectors = FlyerSourceConnectorCatalog.albertaConnectors

        #expect(connectors.count == 10)
        for connector in connectors {
            guard connector.unsupportedReason == nil else {
                // Unsupported connectors are stubbed with no official URLs by design.
                #expect(connector.officialEntryURLs.isEmpty)
                continue
            }

            #expect(!connector.officialEntryURLs.isEmpty)
            for url in connector.officialEntryURLs {
                #expect(connector.allows(url: url))
            }
            #expect(!connector.allows(url: try #require(URL(string: "https://flipp.com/en-ca/calgary-ab"))))
            #expect(!connector.allows(url: try #require(URL(string: "https://www.flyers-on-line.com/safeway/alberta"))))
        }
    }

    @Test
    func coordinatorUsesKnownURLAndSkipsSearch_whenOfficialURLIsUsable() async throws {
        let connector = makeConnector(
            officialURLs: ["https://example-grocer.ca/flyer"],
            allowedDomains: ["example-grocer.ca"]
        )
        let knownURL = try #require(connector.officialEntryURLs.first)
        let fetcher = FakeFlyerDocumentFetcher(documents: [
            knownURL: .success(.usable(url: knownURL))
        ])
        let searchProvider = FakeFlyerSearchProvider(results: [])
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: [connector],
            fetcher: fetcher,
            searchProvider: searchProvider
        )

        let results = await coordinator.discoverSources()

        let result = try #require(results.first)
        #expect(result.state == .found)
        #expect(result.selectedURL == knownURL)
        #expect(result.method == .knownURL)
        #expect(result.sourceShape == .html)
        #expect(searchProvider.queries.isEmpty)
    }

    @Test
    func coordinatorUsesBraveFallback_whenKnownURLFailsAndOfficialSearchResultWorks() async throws {
        let connector = makeConnector(
            officialURLs: ["https://example-grocer.ca/flyer"],
            allowedDomains: ["example-grocer.ca"],
            queries: ["Example Grocer Alberta flyer official"]
        )
        let knownURL = try #require(connector.officialEntryURLs.first)
        let searchURL = try #require(URL(string: "https://www.example-grocer.ca/weekly-deals"))
        let fetcher = FakeFlyerDocumentFetcher(documents: [
            knownURL: .failure(FakeFlyerError.unavailable),
            searchURL: .success(.usable(url: searchURL))
        ])
        let searchProvider = FakeFlyerSearchProvider(results: [
            FlyerSearchResult(title: "Example Grocer Weekly Flyer", url: searchURL, description: "Alberta deals")
        ])
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: [connector],
            fetcher: fetcher,
            searchProvider: searchProvider
        )

        let result = try #require(await coordinator.discoverSources().first)

        #expect(result.state == .found)
        #expect(result.selectedURL == searchURL)
        #expect(result.method == .braveSearch)
        #expect(searchProvider.queries == ["Example Grocer Alberta flyer official"])
    }

    @Test
    func coordinatorReportsFallbackUnavailable_whenKnownURLFailsAndSearchKeyIsMissing() async throws {
        let connector = makeConnector(
            officialURLs: ["https://example-grocer.ca/flyer"],
            allowedDomains: ["example-grocer.ca"]
        )
        let knownURL = try #require(connector.officialEntryURLs.first)
        let fetcher = FakeFlyerDocumentFetcher(documents: [
            knownURL: .failure(FakeFlyerError.unavailable)
        ])
        let searchProvider = FakeFlyerSearchProvider(error: FlyerSearchError.missingAPIKey)
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: [connector],
            fetcher: fetcher,
            searchProvider: searchProvider
        )

        let result = try #require(await coordinator.discoverSources().first)

        #expect(result.state == .fallbackUnavailable)
        #expect(result.selectedURL == nil)
        #expect(result.message.contains("BRAVE_SEARCH_API_KEY"))
    }

    @Test
    func coordinatorRejectsThirdPartySearchResults() async throws {
        let connector = makeConnector(
            officialURLs: ["https://example-grocer.ca/flyer"],
            allowedDomains: ["example-grocer.ca"],
            queries: ["Example Grocer Alberta flyer official"]
        )
        let knownURL = try #require(connector.officialEntryURLs.first)
        let thirdPartyURL = try #require(URL(string: "https://flipp.com/en-ca/calgary-ab/stores/example-grocer"))
        let fetcher = FakeFlyerDocumentFetcher(documents: [
            knownURL: .failure(FakeFlyerError.unavailable),
            thirdPartyURL: .success(.usable(url: thirdPartyURL))
        ])
        let searchProvider = FakeFlyerSearchProvider(results: [
            FlyerSearchResult(title: "Example Grocer Flyer", url: thirdPartyURL, description: "Calgary flyer")
        ])
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: [connector],
            fetcher: fetcher,
            searchProvider: searchProvider
        )

        let result = try #require(await coordinator.discoverSources().first)
        let fetchedURLs = fetcher.requestedURLs

        #expect(result.state == .failed)
        #expect(result.selectedURL == nil)
        #expect(!fetchedURLs.contains(thirdPartyURL))
        #expect(result.message.contains("third-party"))
    }

    @Test
    func viewModelReportsCompletedSummaryAfterDiscovery() async throws {
        let connector = makeConnector(
            officialURLs: ["https://example-grocer.ca/flyer"],
            allowedDomains: ["example-grocer.ca"]
        )
        let knownURL = try #require(connector.officialEntryURLs.first)
        let fetcher = FakeFlyerDocumentFetcher(documents: [
            knownURL: .success(.usable(url: knownURL))
        ])
        let coordinator = FlyerDiscoveryCoordinator(
            connectors: [connector],
            fetcher: fetcher,
            searchProvider: FakeFlyerSearchProvider(results: [])
        )
        let viewModel = FlyerProcessingPOCViewModel(
            coordinator: coordinator,
            initialResults: [
                FlyerDiscoveryResult(
                    banner: connector.banner,
                    state: .failed,
                    selectedURL: nil,
                    method: nil,
                    message: "Not checked yet."
                )
            ]
        )

        await viewModel.checkFlyers()

        #expect(viewModel.runState == .completed)
        #expect(viewModel.results.first?.state == .found)
        #expect(viewModel.statusSummary == "Found official sources for 1 of 1 banners.")
    }

    private func makeConnector(
        officialURLs: [String],
        allowedDomains: [String],
        queries: [String] = ["Example Grocer Alberta flyer official"]
    ) -> FlyerSourceConnector {
        FlyerSourceConnector(
            banner: FlyerBanner(
                id: .realCanadianSuperstore,
                rank: 1,
                name: "Example Grocer",
                parentType: "Example Parent",
                albertaRationale: "Test banner."
            ),
            officialEntryURLs: officialURLs.compactMap(URL.init(string:)),
            allowedDomains: allowedDomains,
            searchQueries: queries,
            unsupportedReason: nil
        )
    }
}

@MainActor
struct FlyerSourceShapeClassifierTests {
    @Test
    func classifiesPDFFromMIMEType() {
        let result = FlyerSourceShapeClassifier.classify(
            mimeType: "application/pdf",
            bodyText: nil,
            byteCount: 4096
        )
        #expect(result.shape == .pdf)
    }

    @Test
    func classifiesImageFromMIMEType() {
        let result = FlyerSourceShapeClassifier.classify(
            mimeType: "image/jpeg",
            bodyText: nil,
            byteCount: 4096
        )
        #expect(result.shape == .image)
    }

    @Test
    func classifiesJSONFromMIMEType() {
        let result = FlyerSourceShapeClassifier.classify(
            mimeType: "application/json",
            bodyText: "{\"flyer\": true}",
            byteCount: 32
        )
        #expect(result.shape == .json)
    }

    @Test
    func classifiesHTMLWithServerRenderedPricesAsUsable() {
        // Real static flyer content: visible text carries many prices, not just
        // flyer vocabulary.
        let result = FlyerSourceShapeClassifier.classify(
            mimeType: "text/html",
            bodyText: """
            <html><body><h1>Weekly flyer deals</h1>\
            <p>Milk $3.99</p><p>Bread $2.49</p><p>Eggs $4.99</p>\
            <p>Apples $1.99</p><p>Cheese $7.49</p><p>Coffee $9.99</p></body></html>
            """,
            byteCount: 2048
        )
        #expect(result.shape == .html)
        #expect(result.signals.contains("flyer"))
        #expect(result.signals.contains("prices:6"))
    }

    @Test
    func classifiesHTMLWithFlyerWordsButNoPricesAsDynamic() {
        // Mirrors real grocery SPAs (Safeway, Save-On, etc.): nav/title/footer
        // chrome carries "Weekly Flyer"/"Deals" but the prices are JS-rendered,
        // so visible text has no price tokens.
        let result = FlyerSourceShapeClassifier.classify(
            mimeType: "text/html",
            bodyText: """
            <html><body><nav>Weekly Flyer | Deals | Coupons | Offers | Savings</nav>\
            <div id="root"></div></body></html>
            """,
            byteCount: 4096
        )
        #expect(result.shape == .dynamicHTML)
        #expect(result.signals.contains("prices:0"))
        #expect(!result.signals.contains("prices:5"))
    }

    @Test
    func classifiesHTMLWithFlyerTermsOnlyInScriptsOrMetaAsDynamic() {
        // Vocabulary lives only in <script> state and <meta> tags; no visible
        // flyer words and no prices.
        let result = FlyerSourceShapeClassifier.classify(
            mimeType: "text/html",
            bodyText: """
            <!DOCTYPE html><html><head>\
            <script>window.__DATA__={title:"weekly flyer deals and savings",coupon:true};</script>\
            <meta name="description" content="weekly flyer deals, sale, savings, coupon, offer">\
            </head><body><div id="root"></div></body></html>
            """,
            byteCount: 4096
        )
        #expect(result.shape == .dynamicHTML)
        #expect(result.signals == ["prices:0"])
    }

    @Test
    func classifiesHTMLShellWithoutFlyerTermsAsDynamic() {
        let result = FlyerSourceShapeClassifier.classify(
            mimeType: "text/html",
            bodyText: "<html><body><div id=\"app\"></div><script src=\"bundle.js\"></script></body></html>",
            byteCount: 256
        )
        #expect(result.shape == .dynamicHTML)
        #expect(result.signals == ["prices:0"])
    }

    @Test
    func classifiesUnknownWhenNonTextAndNoBody() {
        let result = FlyerSourceShapeClassifier.classify(
            mimeType: "application/octet-stream",
            bodyText: nil,
            byteCount: 4096
        )
        #expect(result.shape == .unknown)
    }
}

private enum FakeFlyerError: Error {
    case unavailable
}

@MainActor
private final class FakeFlyerDocumentFetcher: FlyerDocumentFetching {
    private let documents: [URL: Result<FlyerFetchedDocument, Error>]
    private(set) var requestedURLs: [URL] = []

    init(documents: [URL: Result<FlyerFetchedDocument, Error>]) {
        self.documents = documents
    }

    func fetch(_ url: URL) async throws -> FlyerFetchedDocument {
        requestedURLs.append(url)
        switch documents[url] ?? .failure(FakeFlyerError.unavailable) {
        case .success(let document):
            return document
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
private final class FakeFlyerSearchProvider: FlyerSearchProviding {
    private let results: [FlyerSearchResult]
    private let error: Error?
    private(set) var queries: [String] = []

    init(results: [FlyerSearchResult] = [], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func search(query: String) async throws -> [FlyerSearchResult] {
        queries.append(query)
        if let error {
            throw error
        }
        return results
    }
}

private extension FlyerFetchedDocument {
    static func usable(url: URL) -> FlyerFetchedDocument {
        FlyerFetchedDocument(
            finalURL: url,
            statusCode: 200,
            mimeType: "text/html",
            byteCount: 128,
            sourceShape: .html,
            contentSnippet: "Weekly flyer deals",
            usefulnessSignals: ["flyer", "deal"]
        )
    }
}
