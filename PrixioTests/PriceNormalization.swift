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
        let normalized = PriceParsingService.normalize(
            price: Decimal(string: "3.99")!,
            unit: .lb,
            quantity: nil
        )

        #expect(normalized?.1 == .kg)
        
        guard var value = normalized?.0 else {
            return
        }
        var result = Decimal.zero
        NSDecimalRound(&result, &value, 4, .plain)
        
        #expect(result == Decimal(string: "8.7964"))
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
        #expect(PriceParsingService.looksLikeReceipt(text: "Subtotal 12.99"))
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
    
}
