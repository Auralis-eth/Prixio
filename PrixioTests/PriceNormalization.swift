//
//  PriceNormalization.swift
//  PrixioTests
//
//  Created by Daniel Bell on 3/7/26.
//

import Foundation
import SwiftData
import Testing
@testable import Prixio

@MainActor
struct PriceNormalization {

    @Test(.tags(.shipGate)) func normalizesPoundsToKilograms() async throws {
        let normalized = try #require(PriceParsingService.normalize(
            price: Decimal(string: "3.99")!,
            unit: .lb,
            quantity: nil
        ))

        #expect(normalized.1 == .kg)
        #expect(rounded(normalized.0, scale: 4) == Decimal(string: "8.7964"))
    }

    @Test(.tags(.shipGate)) func normalizesQuantityAndMetricUnits() async throws {
        let each = try #require(PriceParsingService.normalize(price: Decimal(10), unit: .each, quantity: Decimal(4)))
        #expect(each.0 == Decimal(string: "2.5"))
        #expect(each.1 == .each)

        let kilograms = try #require(PriceParsingService.normalize(price: Decimal(string: "6.50")!, unit: .kg, quantity: nil))
        #expect(kilograms.0 == Decimal(string: "6.50"))
        #expect(kilograms.1 == .kg)

        let liters = try #require(PriceParsingService.normalize(price: Decimal(string: "3.25")!, unit: .liter, quantity: nil))
        #expect(liters.0 == Decimal(string: "3.25"))
        #expect(liters.1 == .liter)

        let hundredGrams = try #require(PriceParsingService.normalize(price: Decimal(string: "1.10")!, unit: .hundredGrams, quantity: nil))
        #expect(hundredGrams.0 == Decimal(11))
        #expect(hundredGrams.1 == .kg)
    }

    @Test(.tags(.shipGate)) func normalizationFallsBackToPackagePriceForNonPositiveQuantity() async throws {
        let zeroQuantity = try #require(PriceParsingService.normalize(price: Decimal(5), unit: .each, quantity: Decimal.zero))
        let negativeQuantity = try #require(PriceParsingService.normalize(price: Decimal(5), unit: .each, quantity: Decimal(-2)))

        #expect(zeroQuantity.0 == Decimal(5))
        #expect(negativeQuantity.0 == Decimal(5))
    }

    @Test(.tags(.shipGate)) func normalizationDividesMultiBuyPriceByQuantity() async throws {
        let normalized = try #require(PriceParsingService.normalize(price: Decimal(5), unit: .each, quantity: Decimal(3)))

        #expect(normalized.0 == Decimal(5) / Decimal(3))
        #expect(normalized.1 == .each)
    }

    @Test(.tags(.shipGate)) func normalizationRejectsNonPositivePrices() async throws {
        #expect(PriceParsingService.normalize(price: Decimal.zero, unit: .each, quantity: nil) == nil)
        #expect(PriceParsingService.normalize(price: Decimal(-1), unit: .kg, quantity: nil) == nil)
    }

    @Test(.tags(.shipGate)) func draftRequiresExplicitStoreSelection() async throws {
        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"

        #expect(draft.canSave == false)

        draft.storeChainExplicitlySelected = true
        #expect(draft.canSave == true)
    }

    @Test(.tags(.shipGate)) func detectsReceiptLikeText() async throws {
        let text = """
        Calgary Co-op
        Subtotal 12.99
        GST 0.65
        Total 13.64
        Thank you
        """

        #expect(PriceParsingService.looksLikeReceipt(text: text) == true)
    }
    
    
    @Test func receiptDetectionAvoidsSavingsFlyerFalsePositive() async throws {
        let text = """
        Weekend Flyer
        Total Savings: $3
        Buy 2 for $5
        """

        #expect(PriceParsingService.looksLikeReceipt(text: text) == false)
    }

    @Test func receiptDetectionRequiresMoreThanSingleSubtotalMarker() async throws {
        // A lone "Subtotal" line is a single marker; word-boundary matching prevents it from
        // also satisfying the "total" marker, so it stays below the two-marker receipt threshold.
        #expect(PriceParsingService.looksLikeReceipt(text: "Subtotal 12.99") == false)
    }
    
    @Test func draftCannotSaveWhenAllRequiredFieldsAreMissing() async throws {
        let draft = PriceEntryDraft()

        #expect(draft.canSave == false)
    }

    @Test func draftRejectsInvalidPriceTextValues() async throws {
        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"
        draft.storeChainExplicitlySelected = true

        draft.priceText = "abc"
        #expect(draft.canSave == false)

        draft.priceText = ""
        #expect(draft.canSave == false)

        draft.priceText = "-1"
        #expect(draft.canSave == false)
    }

    @Test(.tags(.shipGate))
    func draftRejectsReceiptCapturesEvenWhenFieldsAreFilled() async throws {
        var draft = PriceEntryDraft()
        draft.itemName = "Receipt total"
        draft.priceText = "13.64"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"
        draft.storeChainExplicitlySelected = true
        draft.review = OCRReview(issues: [.receiptCapture], usedFoundationModel: true)

        #expect(draft.canSave == false)
    }

    @Test func draftRoundTripStillRequiresExplicitStoreSelection() async throws {
        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"
        draft.storeChainExplicitlySelected = true

        #expect(draft.canSave == true)

        draft.storeChainName = nil
        draft.storeChainExplicitlySelected = false
        #expect(draft.canSave == false)
    }

    @Test(.tags(.shipGate))
    func repositoryPersistsParserReviewMetadata() async throws {
        let container = try ModelContainer(
            for: PriceEntry.self,
                StoreChain.self,
                StoreLocation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let repository = PriceEntryRepository(context: context)

        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"
        draft.storeChainExplicitlySelected = true
        draft.review = OCRReview(
            issues: [.multipleCompetingPrices, .possibleMultiProductScan],
            ambiguityNotes: ["two nearby products"],
            usedFoundationModel: true
        )

        try repository.saveEntry(from: draft)
        let entries = try context.fetch(FetchDescriptor<PriceEntry>())
        let savedEntry = try #require(entries.first)

        #expect(savedEntry.parserReviewStateRaw == OCRReviewState.reviewRequired.rawValue)
        #expect(savedEntry.parserReviewIssuesRaw == "multipleCompetingPrices,possibleMultiProductScan")
        #expect(savedEntry.parserUsedFoundationModel == true)
        #expect(savedEntry.parserAmbiguityNotesRaw == "two nearby products")
    }

    private func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var value = value
        var result = Decimal.zero
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
