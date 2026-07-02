import Foundation
import Testing
@testable import Prixio

/// Tests for `FlyerDealMatcher`: matching extracted
/// candidates against shopping-list item keys.
@Suite("Flyer deal matching")
struct FlyerDealMatchingTests {
    private let matcher = FlyerDealMatcher()

    private func candidate(
        _ name: String,
        price: String,
        confidence: Float = 0.9
    ) -> FlyerPriceCandidate {
        FlyerPriceCandidate(
            productName: name,
            normalizedItemKey: ItemKeyNormalizer.normalize(name),
            brand: nil,
            price: Decimal(string: price)!,
            regularPrice: nil,
            priceKind: .regular,
            packageSize: nil,
            unitPrice: nil,
            saleStartDate: nil,
            saleEndDate: nil,
            memberOnly: false,
            sourceText: name,
            confidence: confidence
        )
    }

    private func result(_ bannerID: FlyerBannerID, _ candidates: [FlyerPriceCandidate]) -> FlyerExtractionResult {
        FlyerExtractionResult(
            banner: FlyerBannerCatalog.banner(for: bannerID)!,
            sourceURL: nil,
            fetchedAt: nil,
            method: .endpointJSON,
            candidates: candidates,
            message: "test"
        )
    }

    private func query(_ name: String) -> FlyerDealMatcher.Query {
        FlyerDealMatcher.Query(itemKey: ItemKeyNormalizer.normalize(name), displayName: name)
    }

    @Test("A generic list item rolls up specific matching products")
    func genericItemRollsUpSpecificProducts() {
        // Names whose head noun is "milk" after normalization — a generic query only
        // rolls up products that *refine* it (ItemKeyNormalizer's head-noun rule), so
        // a trailing descriptor or decimal size that displaces the head noun would not
        // match. That is a known normalizer limitation tracked for the enrichment pass.
        let extractions = [
            result(.safeway, [candidate("Almond Milk", price: "4.99"), candidate("2% Milk 4L", price: "5.49")]),
            result(.walmartSupercentre, [candidate("Whole Milk 2L", price: "3.79")])
        ]
        let matches = matcher.match(queries: [query("milk")], extractions: extractions)
        #expect(matches.count == 1)
        let milk = matches[0]
        #expect(milk.deals.count == 3)
        // Best deal is the cheapest, regardless of banner order.
        #expect(milk.bestDeal?.candidate.price == Decimal(string: "3.79"))
        #expect(milk.bestDeal?.banner.id == .walmartSupercentre)
    }

    @Test("Deals are sorted best price first")
    func dealsSortedByPriceAscending() {
        let extractions = [
            result(.safeway, [candidate("Large Eggs", price: "4.49")]),
            result(.sobeys, [candidate("Free Run Eggs", price: "3.99")]),
            result(.noFrills, [candidate("Organic Eggs", price: "2.99")])
        ]
        let matches = matcher.match(queries: [query("eggs")], extractions: extractions)
        let prices = matches[0].deals.map(\.candidate.price)
        #expect(prices == [Decimal(string: "2.99")!, Decimal(string: "3.99")!, Decimal(string: "4.49")!])
    }

    @Test("A more-specific query does not pull in a broader candidate")
    func specificQueryDoesNotMatchBroaderCandidate() {
        let extractions = [result(.safeway, [candidate("Sour Cream", price: "2.49")])]
        let matches = matcher.match(queries: [query("daisy sour cream")], extractions: extractions)
        #expect(matches[0].deals.isEmpty)
    }

    @Test("Unrelated items produce no deals")
    func unrelatedItemsHaveNoDeals() {
        let extractions = [result(.safeway, [candidate("Paper Towels", price: "5.99")])]
        let matches = matcher.match(queries: [query("bananas")], extractions: extractions)
        #expect(matches.count == 1)
        #expect(matches[0].deals.isEmpty)
        #expect(matches[0].hasDeals == false)
    }

    @Test("The same product across banners yields one deal per banner for comparison")
    func sameProductAcrossBannersGivesMultipleDeals() {
        let extractions = [
            result(.safeway, [candidate("Bananas", price: "0.79")]),
            result(.walmartSupercentre, [candidate("Bananas", price: "0.69")])
        ]
        let matches = matcher.match(queries: [query("bananas")], extractions: extractions)
        #expect(matches[0].deals.count == 2)
        #expect(matches[0].bestDeal?.banner.id == .walmartSupercentre)
    }

    @Test("Matches one result entry per query, in query order")
    func oneResultPerQuery() {
        let extractions = [result(.safeway, [candidate("Whole Milk", price: "3.99")])]
        let matches = matcher.match(queries: [query("milk"), query("eggs")], extractions: extractions)
        #expect(matches.count == 2)
        #expect(matches[0].displayName == "milk")
        #expect(matches[0].hasDeals)
        #expect(matches[1].displayName == "eggs")
        #expect(!matches[1].hasDeals)
    }
}
