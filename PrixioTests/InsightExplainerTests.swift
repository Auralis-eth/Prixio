import Foundation
import Testing
@testable import Prixio

/// Tests for the deterministic pieces of natural-language insight explanations:
/// the number-honesty validation, and the trip/item-history evidence builders.
/// Model generation is gated off in unit tests (`OnDeviceModelGate`) and validated
/// on device runs.
@Suite("Insight explanations")
struct InsightExplainerTests {
    // MARK: - Validation

    @Test("A clean reply passes through with whitespace collapsed")
    func cleanReplyPasses() {
        let evidence = InsightEvidence(facts: ["Costco has the best price for 4 of 6 list items."])
        let reply = "Shop at Costco —\n it wins  4 of your 6 items."
        #expect(InsightExplainer.validated(reply, against: evidence)
            == "Shop at Costco — it wins 4 of your 6 items.")
    }

    @Test("A number not present in any fact rejects the reply")
    func inventedNumberRejected() {
        let evidence = InsightEvidence(facts: ["Costco has the best price for 4 of 6 list items."])
        #expect(InsightExplainer.validated("Costco saves you $12.50 on 4 items.", against: evidence) == nil)
        // The same digits *are* allowed when a fact carries them.
        let priced = InsightEvidence(facts: [
            "Costco has the best price for 4 of 6 list items.",
            "Splitting the trip saves $12.50."
        ])
        #expect(InsightExplainer.validated("Costco saves you $12.50 on 4 items.", against: priced) != nil)
    }

    @Test("Empty and over-length replies are rejected")
    func lengthBounds() {
        let evidence = InsightEvidence(facts: ["A fact."])
        #expect(InsightExplainer.validated("   ", against: evidence) == nil)
        let tooLong = String(repeating: "words and more words ", count: 20)
        #expect(InsightExplainer.validated(tooLong, against: evidence) == nil)
    }

    @Test("Number runs are maximal digit runs, not parsed values")
    func numberRunExtraction() {
        #expect(InsightExplainer.numberRuns(in: "$12.99 for 3 items") == ["12", "99", "3"])
        #expect(InsightExplainer.numberRuns(in: "no numbers") == [])
    }

    @Test("Generation is gated off in unit tests")
    func explainGatedOff() async {
        let evidence = InsightEvidence(facts: ["Costco has the best price for 4 of 6 list items."])
        #expect(await InsightExplainer().explain(evidence) == nil)
    }

    // MARK: - Trip evidence

    @MainActor
    @Test("Trip evidence covers winner, basket, split, unpriced items, and the advisory")
    func tripEvidenceFacts() {
        let store = StoreBasketEstimate(
            storeChainID: nil, storeLocationID: nil, storeName: "Costco",
            knownTotal: Decimal(string: "52.40")!, knownItemCount: 4,
            missingItems: [], staleCount: 0
        )
        let other = StoreBasketEstimate(
            storeChainID: nil, storeLocationID: nil, storeName: "Safeway",
            knownTotal: Decimal(string: "20.00")!, knownItemCount: 2,
            missingItems: [], staleCount: 0
        )
        let basket = BasketEstimate(
            perStore: [store],
            cheapestSingleStore: store,
            split: SplitSuggestion(
                stores: [store, other],
                combinedTotal: Decimal(string: "48.15")!,
                savingsVsSingle: Decimal(string: "4.25")!
            ),
            pricedItemCount: 4,
            totalItemCount: 6,
            unpricedItemNames: ["saffron", "kefir"],
            substitutions: []
        )
        let evidence = ShoppingListViewModel.tripEvidence(
            recommendation: .strongWinner(chainID: nil, chainName: "Costco", count: 4, total: 6, staleCount: 1),
            basket: basket,
            advisory: FlyerDealAdvisory(bannerName: "No Frills", matchedItemCount: 2, estimatedSavings: Decimal(3))
        )

        #expect(evidence.facts.count == 6)
        #expect(evidence.facts[0].contains("Costco") && evidence.facts[0].contains("4 of 6"))
        #expect(evidence.facts[1].contains("30 days old"))
        #expect(evidence.facts[2].contains(CurrencyFormatter.shared.display(Decimal(string: "52.40")!)))
        #expect(evidence.facts[3].contains("Costco and Safeway"))
        #expect(evidence.facts[3].contains(CurrencyFormatter.shared.display(Decimal(string: "4.25")!)))
        #expect(evidence.facts[4].contains("2 list items have no price"))
        #expect(evidence.facts[5].contains("No Frills"))
    }

    @MainActor
    @Test("Insufficient data with an empty basket yields no facts")
    func tripEvidenceEmpty() {
        let evidence = ShoppingListViewModel.tripEvidence(
            recommendation: .insufficientData,
            basket: .empty,
            advisory: nil
        )
        #expect(evidence.isEmpty)
    }

    // MARK: - Item-history evidence

    private func point(_ price: String, daysAgo: Int = 0) -> PricePoint {
        PricePoint(
            entryID: UUID(),
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            price: Decimal(string: price)!,
            unitType: .each,
            storeName: "Costco",
            usedNormalizedPricing: false
        )
    }

    @Test("Item-history evidence states the anomaly, band, low, and freshness")
    func itemHistoryEvidenceFacts() {
        let history = ItemPriceHistory(
            itemKey: "butter",
            displayName: "Butter",
            scope: .allStores,
            observationCount: 5,
            latest: point("6.99"),
            lowest: point("4.49", daysAgo: 90),
            highest: point("7.49", daysAgo: 30),
            median: Decimal(string: "5.99")!,
            usualLow: Decimal(string: "5.39")!,
            usualHigh: Decimal(string: "6.59")!,
            hasUsualBand: true,
            freshness: .stale,
            anomaly: .aboveUsual,
            timeline: []
        )
        let evidence = InsightEvidence.itemHistory(history)
        #expect(evidence.facts.count == 4)
        #expect(evidence.facts[0].contains("above the usual range"))
        #expect(evidence.facts[1].contains("5 captured prices"))
        #expect(evidence.facts[2].contains(CurrencyFormatter.shared.display(Decimal(string: "4.49")!)))
        #expect(evidence.facts[3].contains("old"))
    }

    @Test("No usual band means no history evidence")
    func itemHistoryEvidenceRequiresBand() {
        let history = ItemPriceHistory(
            itemKey: "butter",
            displayName: "Butter",
            scope: .allStores,
            observationCount: 1,
            latest: point("6.99"),
            lowest: point("6.99"),
            highest: point("6.99"),
            median: Decimal(string: "6.99")!,
            usualLow: Decimal(string: "6.99")!,
            usualHigh: Decimal(string: "6.99")!,
            hasUsualBand: false,
            freshness: .fresh,
            anomaly: .insufficientData,
            timeline: []
        )
        #expect(InsightEvidence.itemHistory(history).isEmpty)
    }
}
