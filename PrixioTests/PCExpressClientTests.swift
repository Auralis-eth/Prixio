import Foundation
import Testing
@testable import Prixio

/// Tests for `PCExpressClient` — the direct pcexpress BFF fetch that backs the Loblaw
/// (Real Canadian Superstore / No Frills) flyer path. Request shape and response
/// nesting are verified against the live `flyersPage` endpoint (superstore, store 1521).
@Suite("PCExpress client")
struct PCExpressClientTests {
    private let config = PCExpressClient.BannerConfig(
        siteBanner: "superstore",
        storeID: "1521",
        origin: "https://www.realcanadiansuperstore.ca"
    )

    /// Minimal `flyersPage` SDUI page with two tiles and a `hasMore` flag.
    private func page(_ tiles: String, hasMore: Bool) -> Data {
        Data(#"{"layout":{"sections":{"productListingSection":{"components":[{"data":{"productGrid":{"pagination":{"from":0,"size":48,"hasMore":\#(hasMore),"totalResults":2},"productTiles":[\#(tiles)]}}}]}}}}"#.utf8)
    }

    @Test("Builds a POST with the public apikey, banner headers, and store id nested in fulfillmentInfo")
    func buildsRequest() throws {
        let request = PCExpressClient().request(config: config)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.pcexpress.ca/pcx-bff/api/v2/flyersPage")
        #expect(request.value(forHTTPHeaderField: "x-apikey") == "C1xujSegT5j3ap3yexJjqhOfELwGKYvz")
        #expect(request.value(forHTTPHeaderField: "Site-Banner") == "superstore")
        #expect(request.value(forHTTPHeaderField: "Origin") == "https://www.realcanadiansuperstore.ca")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let fulfillment = try #require(json["fulfillmentInfo"] as? [String: Any])
        #expect(fulfillment["storeId"] as? String == "1521")
    }

    @Test("Parses flyersPage tiles into name/price/regular/size fields")
    func parsesTiles() throws {
        let data = page(#"""
        {"productId":"111_KG","title":"Tomato Beefsteak Red","brand":null,"packageSizing":"$4.23/1kg",
         "pricing":{"price":"1.13","wasPrice":"$1.77"},"deal":{"expiryDate":"2026-07-01T00:00:00Z"}}
        """#, hasMore: false)
        let (tiles, hasMore) = try PCExpressClient.parse(data)
        #expect(hasMore == false)
        #expect(tiles.count == 1)
        let tile = try #require(tiles.first)
        #expect(tile.name == "Tomato Beefsteak Red")
        #expect(tile.price == "1.13")
        #expect(tile.regularPrice == "1.77")
        #expect(tile.packageSize == "$4.23/1kg")
        #expect(tile.validTo == "2026-07-01T00:00:00Z")
    }

    @Test("Fetches once, dedupes by product id, and returns items JSON the extractor mines")
    func fetchesItemsJSON() async throws {
        // A single 48-item slice (here 3 tiles, one repeated to exercise dedup).
        let slice = page(#"{"productId":"A","title":"Cheddar Cheese","pricing":{"price":"6.99","wasPrice":"$8.49"}},"# +
                         #"{"productId":"B","title":"Strawberries","pricing":{"price":"3.99"}},"# +
                         #"{"productId":"A","title":"Cheddar Cheese","pricing":{"price":"6.99"}}"#, hasMore: true)

        var client = PCExpressClient()
        var calls = 0
        client.fetch = { _ in
            calls += 1
            return slice
        }

        let json = try await client.fetchItemsJSON(config: config)
        #expect(calls == 1)

        let content = FlyerAcquiredContent(
            banner: FlyerBannerCatalog.banner(for: .realCanadianSuperstore)!,
            state: .acquired,
            acquisitionMethod: .endpointJSON,
            sourceURL: nil,
            finalURL: nil,
            payloadByteCount: json.utf8.count,
            extractionPayload: json,
            message: "pcexpress"
        )
        let candidates = FlyerPriceExtractor().extract(from: content).candidates
        // Cheddar + Strawberries — the repeated Cheddar tile is deduped.
        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.productName == "Cheddar Cheese" && $0.price == Decimal(string: "6.99") })
        #expect(candidates.contains { $0.productName == "Strawberries" && $0.price == Decimal(string: "3.99") })
    }

    @Test("Throws when no tiles come back")
    func throwsWhenEmpty() async {
        var client = PCExpressClient()
        client.fetch = { _ in
            Data(#"{"layout":{"sections":{"productListingSection":{"components":[]}}}}"#.utf8)
        }
        await #expect(throws: PCExpressError.emptyProducts) {
            _ = try await client.fetchItemsJSON(config: config)
        }
    }
}
