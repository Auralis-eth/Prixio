import Combine
import CoreLocation
import Foundation

@MainActor
final class ShoppingListViewModel: ObservableObject {
    @Published private(set) var activeRows: [ShoppingListRowData] = []
    @Published private(set) var completedRows: [ShoppingListRowData] = []
    @Published private(set) var tripRecommendation: TripRecommendation = .insufficientData
    @Published private(set) var basketEstimate: BasketEstimate = .empty
    /// Advisory-only flyer line ("Flyer deals could save ~$X at Y"); never feeds the
    /// basket totals.
    @Published private(set) var flyerAdvisory: FlyerDealAdvisory?
    /// Model-written one-liner explaining the trip picture (see `InsightExplainer`).
    /// Additive: every number/label the card shows stays deterministic; this is nil
    /// whenever the model is unavailable or its answer fails validation.
    @Published private(set) var tripExplanation: String?
    /// "You usually buy this" nudges for habitual items missing from the list
    /// (see `ListAdditionSuggestionEngine`). Confirm/dismiss only — never auto-added.
    @Published private(set) var listAdditionSuggestions: [ListAdditionSuggestion] = []
    /// "Probably running low" restock nudges from reviewed receipt history
    /// (see `ConsumptionCadenceEngine`). Receipts evidence actual purchases, so these
    /// outrank the capture-rhythm suggestions above; dismissal is durable via
    /// `RestockRule`. Confirm/dismiss only — never auto-added.
    @Published private(set) var restockSuggestions: [ConsumptionCadenceEngine.RestockSuggestion] = []

    /// "Buy early — the sale ends before you'd naturally restock" nudges
    /// (see `BuyAheadAdvisor`). Advisory only, like `flyerAdvisory`.
    @Published private(set) var buyAheadAdvisories: [BuyAheadAdvisory] = []

    /// Cap so the restock section stays a nudge, not a second list (mirrors
    /// `ListAdditionSuggestionEngine.maxSuggestions`).
    static let maxRestockSuggestions = 3

    /// Suggestions the user has dismissed this session; they stay gone across
    /// recomputes but return next launch (a dismissed habit is still a habit).
    private var dismissedSuggestionKeys: Set<String> = []

    private let insightExplainer: any InsightExplaining
    private var explanationTask: Task<Void, Never>?
    /// Fingerprint of the evidence the current explanation run belongs to, so
    /// unchanged evidence never re-generates and stale replies never land.
    private var explainedFingerprint: String?

    init(insightExplainer: any InsightExplaining = InsightExplainer()) {
        self.insightExplainer = insightExplainer
    }

    func recompute(
        items: [ShoppingListItem],
        entries: [PriceEntry],
        flyerRecords: [FlyerPriceRecord] = [],
        receipts: [ReceiptCapture] = [],
        restockRules: [RestockRule] = [],
        userLocation: CLLocation?,
        now: Date = .now
    ) {
        let suggestionsByItemKey = Dictionary(uniqueKeysWithValues: Set(items.map(\.itemKey)).map { itemKey in
            (
                itemKey,
                PriceInsightEngine.computeBestStoreForItem(
                    itemKey: itemKey,
                    allEntries: entries,
                    now: now
                )
            )
        })

        let rows = items.map { item in
            makeRow(
                for: item,
                suggestion: suggestionsByItemKey[item.itemKey] ?? nil,
                userLocation: userLocation,
                now: now
            )
        }

        activeRows = rows.filter { !$0.isDone }
        completedRows = rows.filter(\.isDone)
        tripRecommendation = makeTripRecommendation(from: activeRows)

        // Basket totals use package prices (you buy a package, not a normalized unit).
        let basketItems = activeRows.map { BasketItemInput(itemKey: $0.itemKey, displayName: $0.displayName) }
        basketEstimate = PriceInsightEngine.computeBasketEstimate(
            items: basketItems,
            useNormalizedPricing: false,
            allEntries: entries,
            now: now
        )

        flyerAdvisory = FlyerDealAdvisory.compute(
            items: basketItems,
            records: flyerRecords,
            entries: entries,
            now: now
        )

        refreshTripExplanation()

        // Restock nudges from receipt cadence. The engine already applies the
        // user's RestockRule decisions; here we only suppress items already on the
        // list — done or not, in either rollup direction (a list "milk" covers a
        // receipt "2% Milk", and vice versa) — a just-checked-off item was just
        // bought, which is exactly when a restock nudge is wrong.
        let cadences = ConsumptionCadenceEngine.computeCadences(receipts: receipts, now: now)
        let listItemKeys = items.map(\.itemKey)
        restockSuggestions = Array(
            ConsumptionCadenceEngine.restockSuggestions(
                cadences: cadences,
                rules: restockRules,
                now: now
            )
            .filter { suggestion in
                !listItemKeys.contains {
                    ItemKeyNormalizer.matchesEitherDirection($0, suggestion.cadence.itemKey)
                }
            }
            .prefix(Self.maxRestockSuggestions)
        )

        // Every list item — done or not — suppresses its suggestion: a just-checked-off
        // item was just bought, which is exactly when a "usually buy" nudge is wrong.
        // A restock suggestion for the same key also wins outright: receipts evidence
        // an actual purchase rhythm, capture history only a scanning rhythm.
        let restockKeys = Set(restockSuggestions.map(\.cadence.itemKey))
        listAdditionSuggestions = ListAdditionSuggestionEngine.proposeAdditions(
            listItemKeys: items.map(\.itemKey),
            allEntries: entries,
            now: now
        )
        .filter { !dismissedSuggestionKeys.contains($0.itemKey) }
        .filter { !restockKeys.contains($0.itemKey) }

        // Buy-ahead advisories: future needs whose flyer deal closes first. Items
        // already on the list are excluded — the flyer advisory above covers them.
        buyAheadAdvisories = BuyAheadAdvisor.compute(
            cadences: cadences,
            records: flyerRecords,
            entries: entries,
            rules: restockRules,
            now: now
        )
        .filter { advisory in
            !listItemKeys.contains {
                ItemKeyNormalizer.matchesEitherDirection($0, advisory.itemKey)
            }
        }
    }

    func dismissListAdditionSuggestion(_ suggestion: ListAdditionSuggestion) {
        dismissedSuggestionKeys.insert(suggestion.itemKey)
        listAdditionSuggestions.removeAll { $0.itemKey == suggestion.itemKey }
    }

    /// Kicks off (or clears) the model-written trip one-liner for the current
    /// deterministic outputs. The explanation clears immediately when the evidence
    /// changes so prose never disagrees with the numbers on screen.
    private func refreshTripExplanation() {
        let evidence = Self.tripEvidence(
            recommendation: tripRecommendation,
            basket: basketEstimate,
            advisory: flyerAdvisory
        )
        // A single fact reads fine as the deterministic label it came from; prose
        // only earns its place tying several together.
        guard evidence.facts.count >= 2 else {
            explanationTask?.cancel()
            explainedFingerprint = nil
            tripExplanation = nil
            return
        }
        guard evidence.fingerprint != explainedFingerprint else { return }
        explainedFingerprint = evidence.fingerprint
        tripExplanation = nil
        explanationTask?.cancel()
        let explainer = insightExplainer
        explanationTask = Task { [weak self] in
            let text = await explainer.explain(evidence)
            guard !Task.isCancelled, let self, self.explainedFingerprint == evidence.fingerprint else {
                return
            }
            self.tripExplanation = text
        }
    }

    /// The deterministic facts behind the trip one-liner, in display order. Pure —
    /// every figure comes from the already-computed recommendation/basket/advisory.
    static func tripEvidence(
        recommendation: TripRecommendation,
        basket: BasketEstimate,
        advisory: FlyerDealAdvisory?
    ) -> InsightEvidence {
        var facts: [String] = []
        switch recommendation {
        case .insufficientData:
            break
        case .strongWinner(_, let chainName, let count, let total, let staleCount):
            facts.append("\(chainName) has the best price for \(count) of \(total) list items.")
            if staleCount > 0 {
                facts.append("\(staleCount) of the item prices are more than 30 days old.")
            }
        case .splitTrip(_, let primaryChainName, let primaryCount, _, let secondaryChainName, let secondaryCount, let staleCount):
            let secondary = secondaryChainName.map { ", and \($0) for \(secondaryCount ?? 0)" } ?? ""
            facts.append("No single store wins: \(primaryChainName) is cheapest for \(primaryCount) items\(secondary).")
            if staleCount > 0 {
                facts.append("\(staleCount) of the item prices are more than 30 days old.")
            }
        }
        if let cheapest = basket.cheapestSingleStore, cheapest.coversAllPricedItems {
            facts.append("The whole priced basket costs \(CurrencyFormatter.shared.display(cheapest.knownTotal)) at \(cheapest.storeName).")
        }
        if let split = basket.split {
            let names = split.stores.map(\.storeName).joined(separator: " and ")
            if let savings = split.savingsVsSingle {
                facts.append("Splitting the trip across \(names) saves \(CurrencyFormatter.shared.display(savings)).")
            } else {
                facts.append("Only a split across \(names) covers every priced item.")
            }
        }
        if !basket.unpricedItemNames.isEmpty {
            facts.append("\(basket.unpricedItemNames.count) list items have no price data yet.")
        }
        if let advisory {
            facts.append(advisory.message + ".")
        }
        return InsightEvidence(facts: facts)
    }

    private func makeRow(
        for item: ShoppingListItem,
        suggestion: PriceInsightEngine.BestStoreSuggestion?,
        userLocation: CLLocation?,
        now _: Date
    ) -> ShoppingListRowData {
        let distanceMeters = distanceMeters(from: userLocation, suggestion: suggestion)
        let ageText = suggestion.map { "\($0.ageDays)d" }
        let bestStoreName = suggestion?.storeChainName ?? suggestion?.storeLocationName
        let bestPriceText = suggestion.map {
            "\(CurrencyFormatter.shared.display($0.comparablePrice))/\($0.comparableUnitType.displayName)"
        }

        return ShoppingListRowData(
            itemID: item.id,
            itemKey: item.itemKey,
            displayName: item.displayName,
            brand: item.brand,
            quantityNote: item.quantityNote,
            isDone: item.isDone,
            suggestion: suggestion,
            bestStoreName: bestStoreName,
            bestPriceText: bestPriceText,
            ageText: ageText,
            stalenessBucket: suggestion?.stalenessBucket,
            distanceMeters: distanceMeters
        )
    }

    private func makeTripRecommendation(from activeRows: [ShoppingListRowData]) -> TripRecommendation {
        guard activeRows.count >= 2 else {
            return .insufficientData
        }

        let suggestions = activeRows.compactMap(\.suggestion)
        guard suggestions.count >= 2 else {
            return .insufficientData
        }

        guard let winnerSummary = PriceInsightEngine.computeTripWinner(
            suggestions: suggestions,
            totalItems: activeRows.count
        ) else {
            return .insufficientData
        }

        let threshold = Double(activeRows.count) * 0.6
        if Double(winnerSummary.winnerCount) >= threshold {
            return .strongWinner(
                chainID: winnerSummary.winner.chainID,
                chainName: winnerSummary.winner.chainName,
                count: winnerSummary.winnerCount,
                total: activeRows.count,
                staleCount: winnerSummary.staleCount
            )
        }

        let secondary = winnerSummary.rankedCounts.dropFirst().first
        return .splitTrip(
            primaryChainID: winnerSummary.winner.chainID,
            primaryChainName: winnerSummary.winner.chainName,
            primaryCount: winnerSummary.winnerCount,
            secondaryChainID: secondary?.store.chainID,
            secondaryChainName: secondary?.store.chainName,
            secondaryCount: secondary?.count,
            staleCount: winnerSummary.staleCount
        )
    }

    private func distanceMeters(
        from userLocation: CLLocation?,
        suggestion: PriceInsightEngine.BestStoreSuggestion?
    ) -> CLLocationDistance? {
        guard
            let userLocation,
            let latitude = suggestion?.storeCoordinateLat,
            let longitude = suggestion?.storeCoordinateLon
        else {
            return nil
        }

        return userLocation.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }
}
