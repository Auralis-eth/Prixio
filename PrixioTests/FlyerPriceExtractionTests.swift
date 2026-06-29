import Foundation
import Testing
@testable import Prixio

/// Tests for `FlyerPriceExtractor` (flyer-processing step 5): turning acquired
/// payloads (captured JSON + harvested text) into structured `FlyerPriceCandidate`s.
@Suite("Flyer price extraction")
struct FlyerPriceExtractionTests {
    private let extractor = FlyerPriceExtractor()

    private func content(
        method: FlyerAcquisitionMethod,
        payload: String,
        state: FlyerAcquisitionState = .acquired,
        banner: FlyerBanner = FlyerBannerCatalog.banner(for: .safeway)!
    ) -> FlyerAcquiredContent {
        FlyerAcquiredContent(
            banner: banner,
            state: state,
            acquisitionMethod: method,
            sourceURL: URL(string: "https://www.safeway.ca/flyer"),
            finalURL: URL(string: "https://www.safeway.ca/flyer"),
            fetchedAt: Date(timeIntervalSince1970: 1_782_700_000),
            payloadContentType: "application/json; captured",
            payloadByteCount: payload.utf8.count,
            priceTokenCount: 0,
            extractionPayload: payload,
            message: "test"
        )
    }

    // MARK: - JSON strategy

    @Test("Extracts Flipp-shaped item objects with name, sale + regular price, brand, and dates")
    func extractsFlippShapedItems() {
        let payload = """
        {"items":[
          {"name":"Large Eggs One Dozen","brand":"Lucerne","current_price":"3.49","regular_price":"4.99","sale_story":"Save $1.50","valid_from":"2026-06-26","valid_to":"2026-07-02"},
          {"name":"Russet Potatoes 5 lb","current_price":3.99,"valid_from":"2026-06-26","valid_to":"2026-07-02"}
        ]}
        """
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))

        #expect(result.candidateCount == 2)
        let eggs = result.candidates.first { $0.productName == "Large Eggs One Dozen" }
        #expect(eggs?.price == Decimal(string: "3.49"))
        #expect(eggs?.regularPrice == Decimal(string: "4.99"))
        #expect(eggs?.brand == "Lucerne")
        #expect(eggs?.priceKind == .sale)
        #expect(eggs?.saleStartDate != nil)
        #expect(eggs?.saleEndDate != nil)
        #expect(eggs?.confidence == 0.9)
        // Brand folds into the normalized item key.
        #expect(eggs?.normalizedItemKey.contains("lucerne") == true)

        let potatoes = result.candidates.first { $0.productName == "Russet Potatoes 5 lb" }
        #expect(potatoes?.price == Decimal(string: "3.99"))
        // No regular price shown → regular flyer price, not a sale.
        #expect(potatoes?.priceKind == .regular)
        #expect(potatoes?.regularPrice == nil)
    }

    @Test("Parses a price given as a dollar string and a multi-buy dollar string")
    func parsesDollarStringPrices() {
        let payload = """
        {"products":[
          {"title":"Cheddar Cheese","price":"$5.99"},
          {"title":"Canned Soup","price":"2/$3.00"}
        ]}
        """
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        #expect(result.candidates.first { $0.productName == "Cheddar Cheese" }?.price == Decimal(string: "5.99"))
        // Multi-buy: takes the dollar amount (best-effort).
        #expect(result.candidates.first { $0.productName == "Canned Soup" }?.price == Decimal(string: "3.00"))
    }

    @Test("Recursively walks nested JSON structures to find item objects")
    func walksNestedStructures() {
        let payload = """
        {"flyer":{"pages":[{"blocks":[
          {"product":{"name":"Sliced Bread","current_price":2.49}}
        ]}]}}
        """
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        #expect(result.candidateCount == 1)
        #expect(result.candidates.first?.productName == "Sliced Bread")
        #expect(result.candidates.first?.price == Decimal(string: "2.49"))
    }

    @Test("Flags member-only pricing from a loyalty field")
    func flagsMemberOnly() {
        let payload = """
        {"items":[{"name":"Member Steak","current_price":9.99,"loyalty_only":true}]}
        """
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        let candidate = result.candidates.first
        #expect(candidate?.memberOnly == true)
        #expect(candidate?.priceKind == .member)
    }

    @Test("Skips objects that lack a name or a price")
    func skipsNonItemObjects() {
        let payload = """
        {"store":{"id":6638,"name":"Calgary Downtown","postal":"T2P1J9"},
         "meta":{"version":"2","count":0},
         "items":[{"name":"Bananas","current_price":0.69}]}
        """
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        // Store (name, no price) and meta (no name/price) are ignored; only Bananas.
        #expect(result.candidateCount == 1)
        #expect(result.candidates.first?.productName == "Bananas")
    }

    @Test("Ignores implausible prices (zero / out of range)")
    func ignoresImplausiblePrices() {
        let payload = """
        {"items":[
          {"name":"Free Sample","current_price":0},
          {"name":"Mispriced","current_price":999999},
          {"name":"Real Item","current_price":4.49}
        ]}
        """
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        #expect(result.candidateCount == 1)
        #expect(result.candidates.first?.productName == "Real Item")
    }

    @Test("Parses capture-style newline-joined JSON documents per line")
    func parsesNewlineJoinedPayloads() {
        let payload = #"{"items":[{"name":"Milk 2L","current_price":3.79}]}"#
            + "\n"
            + #"{"items":[{"name":"Butter","current_price":4.99}]}"#
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        #expect(result.candidateCount == 2)
        #expect(result.candidates.contains { $0.productName == "Milk 2L" })
        #expect(result.candidates.contains { $0.productName == "Butter" })
    }

    @Test("Recovers item objects from a truncated/concatenated captured payload")
    func recoversFromTruncatedConcatenatedPayload() {
        // Mirrors real capture: several flyer docs joined by newlines, and the last
        // document cut off mid-structure at the byte cap (invalid as a whole, and
        // unparseable per line) — yet the intact item objects must still be mined.
        let doc1 = #"{"publication":{"id":42},"items":[{"name":"Strawberries 1 lb","current_price":2.99,"valid_to":"2026-07-02"},{"name":"Avocado","current_price":0.99,"valid_to":"2026-07-02"}]}"#
        let truncated = #"{"items":[{"name":"Ground Coffee 930g","current_price":9.99,"valid_to":"2026-07-02"},{"name":"Cut Off Item","curren"#
        let payload = doc1 + "\n" + truncated

        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        // The three complete items are recovered; the truncated trailing item is not.
        #expect(result.candidates.contains { $0.productName == "Strawberries 1 lb" && $0.price == Decimal(string: "2.99") })
        #expect(result.candidates.contains { $0.productName == "Avocado" })
        #expect(result.candidates.contains { $0.productName == "Ground Coffee 930g" && $0.price == Decimal(string: "9.99") })
        #expect(!result.candidates.contains { $0.productName == "Cut Off Item" })
    }

    @Test("Ignores braces inside string values when scanning objects")
    func ignoresBracesInsideStrings() {
        let payload = #"{"items":[{"name":"Recipe Mix {family size}","current_price":4.49}]}"#
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        #expect(result.candidateCount == 1)
        #expect(result.candidates.first?.productName == "Recipe Mix {family size}")
        #expect(result.candidates.first?.price == Decimal(string: "4.49"))
    }

    @Test("Dedupes identical items captured more than once")
    func dedupesIdenticalItems() {
        let one = #"{"items":[{"name":"Apples","current_price":1.99,"valid_to":"2026-07-02"}]}"#
        let payload = one + "\n" + one + "\n" + one
        let result = extractor.extract(from: content(method: .endpointJSON, payload: payload))
        #expect(result.candidateCount == 1)
    }

    // MARK: - Text strategy

    @Test("Extracts dollar-priced product lines from harvested text")
    func extractsTextDollarLines() {
        let payload = """
        Weekly Flyer
        Organic Bananas $0.69
        Whole Milk 2L $4.49
        Flyer valid June 26 to July 2
        """
        let result = extractor.extract(from: content(method: .renderedHTML, payload: payload))
        #expect(result.candidates.contains { $0.productName == "Organic Bananas" && $0.price == Decimal(string: "0.69") })
        #expect(result.candidates.contains { $0.productName == "Whole Milk 2L" && $0.price == Decimal(string: "4.49") })
        // The date line has no price token, so it produces no candidate.
        #expect(result.candidates.allSatisfy { $0.confidence == 0.5 })
        #expect(result.candidates.allSatisfy { $0.priceKind == .unknown })
    }

    @Test("Text path flags member/with-card lines")
    func textPathFlagsMember() {
        let payload = "Ice Cream $3.99 with card"
        let result = extractor.extract(from: content(method: .renderedHTML, payload: payload))
        #expect(result.candidates.first?.memberOnly == true)
        #expect(result.candidates.first?.priceKind == .member)
    }

    // MARK: - Edges

    @Test("Empty payload yields no candidates")
    func emptyPayloadYieldsNothing() {
        let result = extractor.extract(from: content(method: .endpointJSON, payload: ""))
        #expect(result.candidateCount == 0)
        #expect(result.candidates.isEmpty)
    }

    @Test("Unsupported/no-method content yields no candidates")
    func noMethodYieldsNothing() {
        let bare = FlyerAcquiredContent(
            banner: FlyerBannerCatalog.banner(for: .costco)!,
            state: .unsupported,
            acquisitionMethod: nil,
            sourceURL: nil,
            finalURL: nil,
            message: "unsupported"
        )
        let result = extractor.extract(from: bare)
        #expect(result.candidateCount == 0)
    }
}
