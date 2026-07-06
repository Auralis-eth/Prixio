import Foundation
import Testing
@testable import Prixio

/// Coverage for the small presentation-bearing domain enums and the pure `PriceInsightEngine`
/// helpers that nothing else exercises directly. These types are simple, but they drive user-facing
/// labels and threshold math, so a regression in one is easy to ship unnoticed.
struct SpendingDomainEnumTests {

    // MARK: - ExpenseCategory

    @Test
    func expenseCategory_everyCaseHasStableIdentityAndNonEmptyPresentation() {
        for category in ExpenseCategory.allCases {
            #expect(category.id == category.rawValue)
            #expect(!category.displayName.isEmpty)
            #expect(!category.systemImage.isEmpty)
        }
    }

    @Test
    func expenseCategory_billLikeCategories_groupsRecurringObligations() {
        #expect(ExpenseCategory.billLikeCategories == [.bills, .utilities, .rent, .insurance, .phoneInternet])
        #expect(!ExpenseCategory.billLikeCategories.contains(.groceries))
        #expect(!ExpenseCategory.billLikeCategories.contains(.subscriptions))
    }

    // MARK: - RecurrenceCadence

    @Test
    func recurrenceCadence_approximateDays_matchExpectedIntervals() {
        #expect(RecurrenceCadence.weekly.approximateDays == 7)
        #expect(RecurrenceCadence.biweekly.approximateDays == 14)
        #expect(RecurrenceCadence.monthly.approximateDays == 30)
    }

    @Test
    func recurrenceCadence_everyCaseHasStableIdentityAndLabel() {
        #expect(RecurrenceCadence.allCases.count == 3)
        for cadence in RecurrenceCadence.allCases {
            #expect(cadence.id == cadence.rawValue)
            #expect(!cadence.displayName.isEmpty)
        }
    }

    // MARK: - RecurringRuleStatus

    @Test
    func recurringRuleStatus_hasThreeLifecycleStates() {
        #expect(Set(RecurringRuleStatus.allCases) == [.suggested, .confirmed, .dismissed])
        #expect(RecurringRuleStatus(rawValue: "confirmed") == .confirmed)
        #expect(RecurringRuleStatus(rawValue: "bogus") == nil)
    }

    @Test
    func expenseEntryCategory_fallsBackToOther_givenUnknownRawValueAndUpdatesRawValueWhenSet() {
        let expense = ExpenseEntry(amount: Decimal(1), category: .groceries)
        expense.categoryRaw = "legacy-category"

        #expect(expense.category == .other)

        expense.category = .utilities
        #expect(expense.categoryRaw == ExpenseCategory.utilities.rawValue)
    }

    @Test
    func recurringRuleTypedProperties_fallBackForUnknownRawValuesAndUpdateRawValuesWhenSet() {
        let rule = RecurringExpenseRule(matchKey: "merchant:test", displayLabel: "Test")
        rule.cadenceRaw = "quarterly"
        rule.statusRaw = "archived"

        #expect(rule.cadence == .monthly)
        #expect(rule.status == .suggested)

        rule.cadence = .biweekly
        rule.status = .dismissed
        #expect(rule.cadenceRaw == RecurrenceCadence.biweekly.rawValue)
        #expect(rule.statusRaw == RecurringRuleStatus.dismissed.rawValue)
    }

    // MARK: - ScanMode

    @Test
    func scanMode_everyCaseHasStableIdentityAndDistinctPrompts() {
        #expect(ScanMode.allCases.count == 2)
        for mode in ScanMode.allCases {
            #expect(mode.id == mode.rawValue)
            #expect(!mode.title.isEmpty)
            #expect(!mode.capturePrompt.isEmpty)
        }
        #expect(ScanMode.priceTag.title != ScanMode.receipt.title)
        #expect(ScanMode.priceTag.capturePrompt != ScanMode.receipt.capturePrompt)
    }

    // MARK: - ReceiptExtractionFailure

    @Test
    func receiptExtractionFailure_everyCaseHasNonEmptyUserMessage() {
        let cases: [ReceiptExtractionFailure] = [
            .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unavailable, .generationFailed
        ]
        for failure in cases {
            #expect(!failure.userMessage.isEmpty)
        }
    }

    @Test
    func receiptExtractionFailure_isEquatable() {
        #expect(ReceiptExtractionFailure.modelNotReady == .modelNotReady)
        #expect(ReceiptExtractionFailure.modelNotReady != .generationFailed)
    }

    // MARK: - PriceInsightEngine.classifyAnomaly

    @Test
    func classifyAnomaly_classifiesAgainstMedianBands() {
        let median = Decimal(100)
        // Bands at ±10% (usual) and ±20% (strong).
        #expect(PriceInsightEngine.classifyAnomaly(latest: Decimal(80), median: median) == .likelySale)
        #expect(PriceInsightEngine.classifyAnomaly(latest: Decimal(85), median: median) == .belowUsual)
        #expect(PriceInsightEngine.classifyAnomaly(latest: Decimal(100), median: median) == .nearUsual)
        #expect(PriceInsightEngine.classifyAnomaly(latest: Decimal(115), median: median) == .aboveUsual)
        #expect(PriceInsightEngine.classifyAnomaly(latest: Decimal(120), median: median) == .unusuallyHigh)
    }

    @Test
    func classifyAnomaly_returnsInsufficientData_givenNonPositiveMedian() {
        #expect(PriceInsightEngine.classifyAnomaly(latest: Decimal(50), median: Decimal(0)) == .insufficientData)
    }

    // MARK: - PriceInsightEngine.median

    @Test
    func median_returnsMiddleElement_givenOddCount() {
        #expect(PriceInsightEngine.median(of: [Decimal(10), Decimal(20), Decimal(30)]) == Decimal(20))
    }

    @Test
    func median_averagesMiddlePair_givenEvenCount() {
        #expect(PriceInsightEngine.median(of: [Decimal(10), Decimal(20), Decimal(30), Decimal(40)]) == Decimal(25))
    }

    @Test
    func median_returnsNil_givenEmpty() {
        #expect(PriceInsightEngine.median(of: [] as [Decimal]) == nil)
        #expect(PriceInsightEngine.median(of: [] as [Double]) == nil)
    }

    @Test
    func median_returnsSingleElement_givenOneValue() {
        #expect(PriceInsightEngine.median(of: [Decimal(42)]) == Decimal(42))
    }

    // MARK: - PriceInsightEngine.ageInDays

    @Test
    func ageInDays_countsWholeDaysSinceCapture() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tenDaysAgo = now.addingTimeInterval(-10 * 86_400)
        #expect(PriceInsightEngine.ageInDays(since: tenDaysAgo, now: now) == 10)
    }

    @Test
    func ageInDays_clampsToZero_givenFutureCaptureDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(5 * 86_400)
        #expect(PriceInsightEngine.ageInDays(since: future, now: now) == 0)
    }
}
