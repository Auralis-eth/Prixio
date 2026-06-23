//
//  ReceiptCurrencyHandlingTests.swift
//  PrixioTests
//
//  Covers the receipt currency handling that closes the "silent $0 spend" gap: extraction
//  applies the model-read currency, the review surface exposes whether the receipt counts
//  toward spending (and a notice when it doesn't), header amounts reject negatives, and the
//  single-currency spending filter actually excludes a foreign-currency receipt until it's
//  corrected back to the reporting currency.
//

import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct ReceiptCurrencyHandlingTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self, PriceEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func reviewedReceipt(currency: String, total: Decimal? = Decimal(string: "12.34")) -> ReceiptCapture {
        let receipt = ReceiptCapture(
            capturedAt: .now,
            storeChainNameSnapshot: "Sobeys",
            total: total,
            currencyCode: currency
        )
        receipt.reviewState = .reviewed
        return receipt
    }

    // MARK: - ReceiptDraftBuilder currency apply branch

    @Test
    func draftBuilderAppliesModelCurrencyUppercased() throws {
        let context = try makeContext()
        let capture = ReceiptCapture(capturedAt: .now)
        context.insert(capture)

        var result = LLMReceiptResult(
            storeName: "Walmart",
            purchaseDate: nil,
            subtotal: nil, tax: nil, discountTotal: nil, depositTotal: nil,
            total: Decimal(string: "9.99"),
            lineItems: [],
            issues: []
        )
        result.currencyCode = "usd"

        ReceiptDraftBuilder.apply(result, to: capture, context: context)

        #expect(capture.currencyCode == "USD")
    }

    @Test
    func draftBuilderKeepsDefaultCurrencyWhenModelReportsNoneOrBlank() throws {
        let context = try makeContext()

        for reported in [nil, "", "   "] as [String?] {
            let capture = ReceiptCapture(capturedAt: .now)
            context.insert(capture)
            var result = LLMReceiptResult(
                storeName: nil, purchaseDate: nil,
                subtotal: nil, tax: nil, discountTotal: nil, depositTotal: nil,
                total: Decimal(string: "5.00"), lineItems: [], issues: []
            )
            result.currencyCode = reported

            ReceiptDraftBuilder.apply(result, to: capture, context: context)

            // A nil/blank reading must not clobber the CAD default the spending math relies on.
            #expect(capture.currencyCode == AppCurrency.defaultCode)
        }
    }

    // MARK: - ReceiptReviewViewModel currency surface

    @Test
    func reportingCurrencyReceiptCountsTowardSpending() throws {
        let context = try makeContext()
        let receipt = reviewedReceipt(currency: AppCurrency.defaultCode)
        context.insert(receipt)
        let viewModel = ReceiptReviewViewModel(capture: receipt, context: context)

        #expect(viewModel.countsTowardSpending)
        #expect(viewModel.foreignCurrencyNotice == nil)
    }

    @Test
    func foreignCurrencyReceiptIsFlaggedAsExcludedWithNotice() throws {
        let context = try makeContext()
        let receipt = reviewedReceipt(currency: "USD")
        context.insert(receipt)
        let viewModel = ReceiptReviewViewModel(capture: receipt, context: context)

        #expect(!viewModel.countsTowardSpending)
        let notice = try #require(viewModel.foreignCurrencyNotice)
        #expect(notice.contains("USD"))
        #expect(notice.contains(AppCurrency.defaultCode))
    }

    @Test
    func foreignCurrencyReceiptCanStillBeMarkedReviewed() throws {
        // A genuinely foreign receipt is legitimately excluded from CAD spending, not blocked — the fix
        // is visibility/correctability, so Done still succeeds with a positive total.
        let context = try makeContext()
        let receipt = reviewedReceipt(currency: "USD")
        receipt.reviewState = .pendingReview
        context.insert(receipt)
        let viewModel = ReceiptReviewViewModel(capture: receipt, context: context)

        #expect(viewModel.markReviewed())
        #expect(receipt.reviewState == .reviewed)
    }

    @Test
    func correctingCurrencyBackToReportingMakesItCount() throws {
        let context = try makeContext()
        let receipt = reviewedReceipt(currency: "USD")
        context.insert(receipt)
        let viewModel = ReceiptReviewViewModel(capture: receipt, context: context)
        #expect(!viewModel.countsTowardSpending)

        // The review picker writes capture.currencyCode; correcting a misread restores inclusion.
        receipt.currencyCode = AppCurrency.defaultCode

        #expect(viewModel.countsTowardSpending)
        #expect(viewModel.foreignCurrencyNotice == nil)
    }

    // MARK: - Negative header-amount guard

    @Test
    func normalizedAmountDropsNegativesAndKeepsZeroAndPositive() {
        #expect(ReceiptReviewViewModel.normalizedAmount(Decimal(string: "-1.00")) == nil)
        #expect(ReceiptReviewViewModel.normalizedAmount(Decimal(string: "-0.01")) == nil)
        #expect(ReceiptReviewViewModel.normalizedAmount(nil) == nil)
        #expect(ReceiptReviewViewModel.normalizedAmount(Decimal(0)) == Decimal(0))
        #expect(ReceiptReviewViewModel.normalizedAmount(Decimal(string: "4.50")) == Decimal(string: "4.50"))
    }

    // MARK: - End-to-end spending exclusion

    @Test
    func spendingFilterExcludesForeignCurrencyButIncludesItOnceCorrected() throws {
        let context = try makeContext()
        let cad = reviewedReceipt(currency: AppCurrency.defaultCode)
        let usd = reviewedReceipt(currency: "USD")
        context.insert(cad)
        context.insert(usd)

        let beforeCorrection = SpendingInsightEngine.spendingReceipts([cad, usd])
        #expect(beforeCorrection.count == 1)
        #expect(beforeCorrection.first === cad)

        // Simulate the user fixing the misread currency in the review picker.
        usd.currencyCode = AppCurrency.defaultCode
        let afterCorrection = SpendingInsightEngine.spendingReceipts([cad, usd])
        #expect(afterCorrection.count == 2)
    }
}
