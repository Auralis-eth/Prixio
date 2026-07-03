import Foundation
import Testing
@testable import Prixio

/// Tests for `FlyerAlternativeFinder`: suggesting similar-but-not-matching flyer
/// deals for shopping-list items, alongside (never instead of) direct matches.
@Suite("Flyer alternative suggestions")
struct FlyerAlternativeFinderTests {
    private let matcher = FlyerDealMatcher()
    private let finder = FlyerAlternativeFinder()

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

    private func alternatives(
        queries: [FlyerDealMatcher.Query],
        extractions: [FlyerExtractionResult]
    ) -> [ShoppingItemFlyerAlternatives] {
        finder.findAlternatives(
            matches: matcher.match(queries: queries, extractions: extractions),
            extractions: extractions
        )
    }

    @Test("A same-kind product that is not a direct match is suggested")
    func suggestsSameKindProduct() {
        let extractions = [result(.safeway, [candidate("Soy Milk", price: "3.49")])]
        let suggestions = alternatives(queries: [query("almond milk")], extractions: extractions)

        #expect(suggestions.count == 1)
        #expect(suggestions[0].alternatives.map(\.candidate.productName) == ["Soy Milk"])
    }

    @Test("A broader product is suggested for a more-specific list item")
    func suggestsBroaderProductForSpecificItem() {
        // "daisy sour cream" never direct-matches plain "Sour Cream" (specific query,
        // broader entry) — but it is exactly the alternative worth surfacing.
        let extractions = [result(.safeway, [candidate("Sour Cream", price: "2.49")])]
        let suggestions = alternatives(queries: [query("daisy sour cream")], extractions: extractions)

        #expect(suggestions.count == 1)
        #expect(suggestions[0].alternatives.map(\.candidate.productName) == ["Sour Cream"])
    }

    @Test("Direct matches are never repeated as alternatives")
    func directMatchesAreNotAlternatives() {
        // "Almond Milk" direct-matches the generic "milk" query, so only a same-head
        // non-match could be an alternative — and for a generic query there is none.
        let extractions = [result(.safeway, [candidate("Almond Milk", price: "4.99")])]
        let suggestions = alternatives(queries: [query("milk")], extractions: extractions)

        #expect(suggestions.isEmpty)
    }

    @Test("The shared word must be the head noun of both sides")
    func requiresSharedHeadNounOnBothSides() {
        // "Milk Chocolate" merely mentions milk; "Apple Sauce" shares apple with
        // "apple juice" but as a modifier. Neither is an alternative.
        let extractions = [result(.safeway, [
            candidate("Milk Chocolate", price: "2.99"),
            candidate("Apple Sauce", price: "3.29")
        ])]
        let suggestions = alternatives(
            queries: [query("milk"), query("apple juice")],
            extractions: extractions
        )

        #expect(suggestions.isEmpty)
    }

    @Test("With a direct deal, alternatives must beat the best direct price")
    func alternativesMustBeatBestDirectDeal() {
        let extractions = [result(.safeway, [
            candidate("Almond Milk", price: "3.99"),
            candidate("Soy Milk", price: "3.49"),
            candidate("Oat Milk", price: "4.49")
        ])]
        let suggestions = alternatives(queries: [query("almond milk")], extractions: extractions)

        // Soy (cheaper than the $3.99 direct deal) qualifies; oat does not.
        #expect(suggestions.count == 1)
        #expect(suggestions[0].alternatives.map(\.candidate.productName) == ["Soy Milk"])
    }

    @Test("Suggestions are capped and sorted best price first")
    func capsAndSortsSuggestions() {
        let extractions = [result(.safeway, [
            candidate("Soy Milk", price: "3.99"),
            candidate("Oat Milk", price: "2.99"),
            candidate("Goat Milk", price: "6.49"),
            candidate("Coconut Milk", price: "3.49")
        ])]
        let suggestions = alternatives(queries: [query("almond milk")], extractions: extractions)

        #expect(suggestions[0].alternatives.map(\.candidate.productName) == ["Oat Milk", "Coconut Milk", "Soy Milk"])
    }

    @Test("The same product across banners is collapsed to its best deal")
    func collapsesCrossBannerRepeats() {
        let extractions = [
            result(.safeway, [candidate("Soy Milk", price: "3.99")]),
            result(.walmartSupercentre, [candidate("Soy Milk", price: "3.49")])
        ]
        let suggestions = alternatives(queries: [query("almond milk")], extractions: extractions)

        #expect(suggestions[0].alternatives.count == 1)
        #expect(suggestions[0].alternatives[0].banner.id == .walmartSupercentre)
    }

    @Test("Unrelated products are never suggested")
    func unrelatedProductsAreNotSuggested() {
        let extractions = [result(.safeway, [candidate("Paper Towels", price: "5.99")])]
        let suggestions = alternatives(queries: [query("bananas")], extractions: extractions)

        #expect(suggestions.isEmpty)
    }
}
