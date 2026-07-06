import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct ConsumptionCadenceEngineTests {
    /// Fixed "today" so predictions are deterministic regardless of when tests run.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self, RestockRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func day(_ offset: Int) -> Date {
        let today = Calendar.current.startOfDay(for: now)
        return Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    private func line(_ name: String, qty: Double? = nil, needsReview: Bool = false) -> ReceiptLineItem {
        ReceiptLineItem(
            lineText: name,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            quantityValue: qty.map { Decimal($0) },
            needsReview: needsReview
        )
    }

    private func receipt(
        daysAgo: Int,
        reviewState: ReceiptReviewState = .reviewed,
        lines: [ReceiptLineItem]
    ) -> ReceiptCapture {
        ReceiptCapture(
            capturedAt: day(-daysAgo),
            purchaseDate: day(-daysAgo),
            reviewState: reviewState,
            lineItems: lines
        )
    }

    /// Inserts receipts so SwiftData relationships resolve, then runs the engine.
    private func cadences(for receipts: [ReceiptCapture]) throws -> [ConsumptionCadenceEngine.ItemCadence] {
        let context = try makeContext()
        for receipt in receipts {
            context.insert(receipt)
        }
        try context.save()
        return ConsumptionCadenceEngine.computeCadences(receipts: receipts, now: now)
    }

    private func cadence(
        itemKey: String = "milk",
        medianIntervalDays: Double = 7,
        lastPurchasedDaysAgo: Int,
        runOutInDays: Int,
        confidence: ConsumptionCadenceEngine.CadenceConfidence = .high
    ) -> ConsumptionCadenceEngine.ItemCadence {
        ConsumptionCadenceEngine.ItemCadence(
            itemKey: itemKey,
            displayName: itemKey,
            purchaseEventCount: 5,
            medianIntervalDays: medianIntervalDays,
            intervalSpreadDays: 0,
            lastPurchasedAt: day(-lastPurchasedDaysAgo),
            predictedRunOutDate: day(runOutInDays),
            confidence: confidence
        )
    }

    // MARK: - Cadence inference

    @Test
    func noCadenceBelowMinimumEvents() throws {
        let result = try cadences(for: [
            receipt(daysAgo: 14, lines: [line("Milk")]),
            receipt(daysAgo: 7, lines: [line("Milk")])
        ])
        #expect(result.isEmpty)
    }

    @Test
    func weeklyPurchasesYieldHighConfidenceCadence() throws {
        let result = try cadences(for: [40, 33, 26, 19, 12, 5].map {
            receipt(daysAgo: $0, lines: [line("Milk")])
        })
        let milk = try #require(result.first)
        #expect(result.count == 1)
        #expect(milk.itemKey == "milk")
        #expect(milk.purchaseEventCount == 6)
        #expect(milk.medianIntervalDays == 7)
        #expect(milk.intervalSpreadDays == 0)
        #expect(milk.confidence == .high)
        #expect(milk.lastPurchasedAt == day(-5))
        #expect(milk.predictedRunOutDate == day(2))
    }

    @Test
    func medianAbsorbsVacationGap() throws {
        // Intervals 7, 7, 7, 21, 7 — the outlier gap must not move the median.
        let result = try cadences(for: [49, 42, 35, 28, 7, 0].map {
            receipt(daysAgo: $0, lines: [line("Coffee")])
        })
        let coffee = try #require(result.first)
        #expect(coffee.medianIntervalDays == 7)
        #expect(coffee.confidence == .high)
        #expect(coffee.predictedRunOutDate == day(7))
    }

    @Test
    func irregularPurchasesAreSuppressed() throws {
        // Intervals 2, 30, 3, 45: spread ratio far above the medium gate.
        let result = try cadences(for: [80, 78, 48, 45, 0].map {
            receipt(daysAgo: $0, lines: [line("Cake Candles")])
        })
        #expect(result.isEmpty)
    }

    @Test
    func sameDayLinesCollapseIntoOneEvent() throws {
        let result = try cadences(for: [
            receipt(daysAgo: 14, lines: [line("Milk"), line("Milk")]),
            receipt(daysAgo: 7, lines: [line("Milk")]),
            receipt(daysAgo: 0, lines: [line("Milk")])
        ])
        let milk = try #require(result.first)
        #expect(milk.purchaseEventCount == 3)
        #expect(milk.medianIntervalDays == 7)
    }

    @Test
    func unreviewedReceiptsAndLinesAreIgnored() throws {
        let result = try cadences(for: [
            receipt(daysAgo: 21, lines: [line("Milk")]),
            receipt(daysAgo: 14, lines: [line("Milk")]),
            receipt(daysAgo: 7, lines: [line("Milk", needsReview: true)]),
            receipt(daysAgo: 0, reviewState: .pendingReview, lines: [line("Milk")])
        ])
        // Only two trusted events remain — below the minimum, so no cadence.
        #expect(result.isEmpty)
    }

    @Test
    func purchaseDateTakesPrecedenceOverCaptureDate() throws {
        // All three receipts scanned today, but bought a week apart.
        let receipts = [14, 7, 0].map { daysAgo in
            ReceiptCapture(
                capturedAt: day(0),
                purchaseDate: day(-daysAgo),
                reviewState: .reviewed,
                lineItems: [line("Eggs")]
            )
        }
        let result = try cadences(for: receipts)
        let eggs = try #require(result.first)
        #expect(eggs.purchaseEventCount == 3)
        #expect(eggs.medianIntervalDays == 7)
        #expect(eggs.lastPurchasedAt == day(0))
    }

    @Test
    func differentNormalizedKeysKeepSeparateClocks() throws {
        let result = try cadences(for: [14, 7, 0].map {
            receipt(daysAgo: $0, lines: [line("Almond Milk"), line("2% Milk")])
        })
        #expect(result.count == 2)
        #expect(Set(result.map(\.itemKey)).count == 2)
        #expect(result.allSatisfy { $0.medianIntervalDays == 7 })
    }

    @Test
    func stockUpScalesThePrediction() throws {
        // Weekly buys of one unit, then a double stock-up: the last two packs
        // should last two intervals.
        let receipts = [35, 28, 21, 14, 7].map {
            receipt(daysAgo: $0, lines: [line("Dog Food", qty: 1)])
        } + [receipt(daysAgo: 0, lines: [line("Dog Food", qty: 2)])]
        let result = try cadences(for: receipts)
        let dogFood = try #require(result.first)
        #expect(dogFood.medianIntervalDays == 7)
        #expect(dogFood.predictedRunOutDate == day(14))
    }

    // MARK: - Urgency

    @Test
    func urgencyClassifiesAgainstPredictedRunOut() {
        let overdue = cadence(lastPurchasedDaysAgo: 10, runOutInDays: -3)
        #expect(ConsumptionCadenceEngine.urgency(for: overdue, now: now) == .probablyOut(daysOverdue: 3))

        // Within the grace window, overdue still reads as "due now", not "out".
        let inGrace = cadence(lastPurchasedDaysAgo: 9, runOutInDays: -2)
        #expect(ConsumptionCadenceEngine.urgency(for: inGrace, now: now) == .dueSoon(daysRemaining: 0))

        let soon = cadence(lastPurchasedDaysAgo: 5, runOutInDays: 2)
        #expect(ConsumptionCadenceEngine.urgency(for: soon, now: now) == .dueSoon(daysRemaining: 2))

        let stocked = cadence(lastPurchasedDaysAgo: 1, runOutInDays: 6)
        #expect(ConsumptionCadenceEngine.urgency(for: stocked, now: now) == .stocked)
    }

    // MARK: - Restock suggestions

    @Test
    func dismissedRuleSuppressesSuggestion() {
        let milk = cadence(lastPurchasedDaysAgo: 10, runOutInDays: -3)
        let dismissed = RestockRule(itemKey: "milk", displayName: "Milk", status: .dismissed)
        let suggestions = ConsumptionCadenceEngine.restockSuggestions(
            cadences: [milk],
            rules: [dismissed],
            now: now
        )
        #expect(suggestions.isEmpty)
    }

    @Test
    func confirmedOverrideReplacesInferredInterval() throws {
        // Inferred weekly → 3 days overdue; the user says it's really every 12 days.
        let milk = cadence(lastPurchasedDaysAgo: 10, runOutInDays: -3)
        let confirmed = RestockRule(
            itemKey: "milk",
            displayName: "Milk",
            status: .confirmed,
            overrideIntervalDays: 12
        )
        let suggestions = ConsumptionCadenceEngine.restockSuggestions(
            cadences: [milk],
            rules: [confirmed],
            now: now
        )
        let suggestion = try #require(suggestions.first)
        #expect(suggestion.cadence.medianIntervalDays == 12)
        #expect(suggestion.cadence.predictedRunOutDate == day(2))
        #expect(suggestion.urgency == .dueSoon(daysRemaining: 2))
    }

    @Test
    func lapsedItemsAreNotSuggested() {
        // 23 days overdue on a weekly cadence (> 3 intervals): probably discontinued.
        let lapsed = cadence(itemKey: "oat milk", lastPurchasedDaysAgo: 30, runOutInDays: -23)
        // 8 days overdue: still worth suggesting.
        let current = cadence(itemKey: "butter", lastPurchasedDaysAgo: 15, runOutInDays: -8)
        let suggestions = ConsumptionCadenceEngine.restockSuggestions(
            cadences: [lapsed, current],
            rules: [],
            now: now
        )
        #expect(suggestions.map(\.cadence.itemKey) == ["butter"])
    }

    @Test
    func suggestionsSortMostUrgentFirst() {
        let dueSoon = cadence(itemKey: "coffee", lastPurchasedDaysAgo: 5, runOutInDays: 2)
        let overdue = cadence(itemKey: "milk", lastPurchasedDaysAgo: 12, runOutInDays: -5)
        let stocked = cadence(itemKey: "rice", lastPurchasedDaysAgo: 1, runOutInDays: 20)
        let suggestions = ConsumptionCadenceEngine.restockSuggestions(
            cadences: [dueSoon, overdue, stocked],
            rules: [],
            now: now
        )
        #expect(suggestions.map(\.cadence.itemKey) == ["milk", "coffee"])
        #expect(suggestions.first?.urgency == .probablyOut(daysOverdue: 5))
    }
}
