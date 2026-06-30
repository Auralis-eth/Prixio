import Foundation
import Testing
@testable import Prixio

/// Tests for `FlippFlyerKitClient` — the direct Flipp flyerkit fetch that backs the
/// Co-op (and general Flipp) items fallback.
@Suite("Flipp flyerkit client")
struct FlippFlyerKitClientTests {
    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }

    @Test("Builds flyerkit URLs with merchant, token, locale, and postal code")
    func buildsURLs() {
        let client = FlippFlyerKitClient(accessToken: "TOKEN", locale: "en-ca")
        let pubs = client.publicationsURL(merchant: "coopfood", postalCode: "T2P1J9").absoluteString
        #expect(pubs.contains("/flyerkit/publications/coopfood"))
        #expect(pubs.contains("access_token=TOKEN"))
        #expect(pubs.contains("postal_code=T2P1J9"))
        #expect(pubs.contains("locale=en-ca"))

        let products = client.productsURL(publicationID: 7989313).absoluteString
        #expect(products.contains("/flyerkit/publication/7989313/products"))
        #expect(products.contains("access_token=TOKEN"))
    }

    @Test("Picks the publication whose validity window contains now")
    func picksCurrentPublication() {
        let publications: [[String: Any]] = [
            ["id": 100, "valid_from": "2026-06-01", "valid_to": "2026-06-07"],
            ["id": 200, "valid_from": "2026-06-26", "valid_to": "2026-07-02"],
            ["id": 300, "valid_from": "2026-07-10", "valid_to": "2026-07-16"]
        ]
        let id = FlippFlyerKitClient.currentPublicationID(from: publications, now: date("2026-06-30"))
        #expect(id == 200)
    }

    @Test("Falls back to the first publication when none spans now")
    func fallsBackToFirst() {
        let publications: [[String: Any]] = [
            ["id": 900, "valid_from": "2026-07-10", "valid_to": "2026-07-16"]
        ]
        let id = FlippFlyerKitClient.currentPublicationID(from: publications, now: date("2026-06-30"))
        #expect(id == 900)
    }

    @Test("Fetches publications then returns the current publication's products JSON")
    func fetchesProductsJSON() async throws {
        let publicationsJSON = #"[{"id":7989313,"valid_from":"2026-06-26","valid_to":"2026-07-02"}]"#
        let productsJSON = #"[{"name":"Cheddar","current_price":4.99},{"name":"Milk","current_price":3.49}]"#

        var client = FlippFlyerKitClient(accessToken: "T")
        client.fetch = { url in
            if url.absoluteString.contains("/publications/") {
                return Data(publicationsJSON.utf8)
            }
            #expect(url.absoluteString.contains("/publication/7989313/products"))
            return Data(productsJSON.utf8)
        }

        let json = try await client.fetchProductsJSON(merchant: "coopfood", postalCode: "T2P1J9", now: date("2026-06-30"))
        #expect(json == productsJSON)

        // The returned JSON feeds the normal extractor.
        let content = FlyerAcquiredContent(
            banner: FlyerBannerCatalog.banner(for: .coOp)!,
            state: .acquired,
            acquisitionMethod: .endpointJSON,
            sourceURL: nil,
            finalURL: nil,
            payloadByteCount: json.utf8.count,
            extractionPayload: json,
            message: "flyerkit"
        )
        let candidates = FlyerPriceExtractor().extract(from: content).candidates
        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.productName == "Cheddar" && $0.price == Decimal(string: "4.99") })
    }

    @Test("Unwraps a wrapped publications list")
    func unwrapsWrappedPublications() async throws {
        var client = FlippFlyerKitClient()
        client.fetch = { url in
            if url.absoluteString.contains("/publications/") {
                return Data(#"{"publications":[{"id":42,"valid_from":"2026-06-26","valid_to":"2026-07-02"}]}"#.utf8)
            }
            return Data(#"[{"name":"Eggs","current_price":2.99}]"#.utf8)
        }
        let json = try await client.fetchProductsJSON(merchant: "coopfood", postalCode: "T2P1J9", now: date("2026-06-30"))
        #expect(json.contains("Eggs"))
    }

    @Test("Throws when there are no publications")
    func throwsWhenNoPublications() async {
        var client = FlippFlyerKitClient()
        client.fetch = { _ in Data("[]".utf8) }
        await #expect(throws: FlippFlyerKitError.noPublication) {
            _ = try await client.fetchProductsJSON(merchant: "coopfood", postalCode: "T2P1J9")
        }
    }
}
