import Foundation
import Testing
@testable import Prixio

/// Tests for `FlippFlyerKitClient` — the direct Flipp `flyers-ng` fetch (the API
/// `Kiizon/flippscrape` uses) that backs the Co-op / Flipp items fallback.
@Suite("Flipp flyerkit client")
struct FlippFlyerKitClientTests {
    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }

    @Test("Builds data and flyer_items URLs with postal code and session id")
    func buildsURLs() {
        let client = FlippFlyerKitClient(locale: "en")
        let data = client.dataURL(postalCode: "T2P1J9", sid: "1234567890123456").absoluteString
        #expect(data.contains("flyers-ng.flippback.com/api/flipp/data"))
        #expect(data.contains("postal_code=T2P1J9"))
        #expect(data.contains("sid=1234567890123456"))
        #expect(data.contains("locale=en"))

        let items = client.itemsURL(flyerID: 7988986, sid: "1234567890123456").absoluteString
        #expect(items.contains("/api/flipp/flyers/7988986/flyer_items"))
        #expect(items.contains("sid=1234567890123456"))
    }

    @Test("Picks the merchant's current flyer by merchant_id and validity window")
    func picksCurrentFlyerByMerchant() {
        let flyers: [[String: Any]] = [
            ["id": 111, "merchant_id": 234, "valid_from": "2026-06-26", "valid_to": "2026-07-02"], // Walmart
            ["id": 222, "merchant_id": 2051, "valid_from": "2026-06-01", "valid_to": "2026-06-07"], // Co-op, expired
            ["id": 333, "merchant_id": 2051, "valid_from": "2026-06-26", "valid_to": "2026-07-02"]  // Co-op, current
        ]
        let id = FlippFlyerKitClient.currentFlyerID(from: flyers, merchantID: 2051, now: date("2026-06-30"))
        #expect(id == 333)
    }

    @Test("Falls back to the merchant's first flyer when none spans now")
    func fallsBackToFirstForMerchant() {
        let flyers: [[String: Any]] = [
            ["id": 900, "merchant_id": 2051, "valid_from": "2026-07-10", "valid_to": "2026-07-16"],
            ["id": 901, "merchant_id": 999, "valid_from": "2026-06-26", "valid_to": "2026-07-02"]
        ]
        let id = FlippFlyerKitClient.currentFlyerID(from: flyers, merchantID: 2051, now: date("2026-06-30"))
        #expect(id == 900)
    }

    @Test("Returns nil when the merchant has no flyers")
    func noFlyerForUnknownMerchant() {
        let flyers: [[String: Any]] = [["id": 1, "merchant_id": 234]]
        #expect(FlippFlyerKitClient.currentFlyerID(from: flyers, merchantID: 2051, now: date("2026-06-30")) == nil)
    }

    @Test("Fetches the merchant's flyer then returns its items JSON, which the extractor mines")
    func fetchesItemsJSON() async throws {
        let dataJSON = #"{"flyers":[{"id":7988986,"merchant":"Calgary Co-op","merchant_id":2051,"valid_from":"2026-06-26","valid_to":"2026-07-02"}]}"#
        let itemsJSON = #"[{"name":"Sparkling Ice Beverage","brand":"Sparkling Ice","price":"5.0"},{"name":"Cheddar","price":"6.99"}]"#

        var client = FlippFlyerKitClient()
        client.makeSessionID = { "1111222233334444" }
        client.fetch = { url in
            if url.absoluteString.contains("/flipp/data") {
                #expect(url.absoluteString.contains("postal_code=T2P1J9"))
                return Data(dataJSON.utf8)
            }
            #expect(url.absoluteString.contains("/flyers/7988986/flyer_items"))
            return Data(itemsJSON.utf8)
        }

        let json = try await client.fetchItemsJSON(merchantID: 2051, postalCode: "T2P1J9", now: date("2026-06-30"))
        #expect(json == itemsJSON)

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
        #expect(candidates.contains { $0.productName == "Sparkling Ice Beverage" && $0.price == Decimal(string: "5.0") })
    }

    @Test("Throws when the postal code has no flyer for the merchant")
    func throwsWhenNoMerchantFlyer() async {
        var client = FlippFlyerKitClient()
        client.fetch = { _ in Data(#"{"flyers":[{"id":1,"merchant_id":234}]}"#.utf8) }
        await #expect(throws: FlippFlyerKitError.noPublication) {
            _ = try await client.fetchItemsJSON(merchantID: 2051, postalCode: "T2P1J9")
        }
    }
}
