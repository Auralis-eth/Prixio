//
//  PrixioTests.swift
//  PrixioTests
//
//  Created by Daniel Bell on 9/22/25.
//

import Foundation
import Testing
@testable import Prixio

@MainActor
struct PrixioTests {

    @Test func parsesMultiBuyOffer() async throws {
        let result = PriceParsingService.extract(from: ["Yellow Onions", "2/$5", "Product of Canada"])

        #expect(result.itemNameHint == "Yellow Onions")
        #expect(result.price == Decimal(string: "5"))
        #expect(result.quantity == Decimal(string: "2"))
    }

    @Test func reconstructsSplitDollarAndCents() async throws {
        let result = PriceParsingService.extract(from: ["Bananas", "17", "99"])

        #expect(result.price == Decimal(string: "17.99"))
        #expect(result.priceCandidates.first?.value == Decimal(string: "17.99"))
    }

    @Test func infersDecimalFromFourDigitOCRToken() async throws {
        let result = PriceParsingService.extract(from: ["Bananas", "1799", "99"])

        #expect(result.price == Decimal(string: "17.99"))
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "17.99") })
    }

    @Test func prefersHigherConfidencePriceCandidateWithinSamePriority() async throws {
        let result = PriceParsingService.extract(
            from: [
                OCRTextObservation(string: "Low confidence 2.99", confidence: 0.12),
                OCRTextObservation(string: "High confidence 4.99", confidence: 0.94)
            ]
        )

        #expect(result.price == Decimal(string: "4.99"))
        #expect(result.confidence == 0.94)
        #expect(result.priceCandidates.first?.sourceText == "High confidence 4.99")
    }

    @Test func normalizesPoundsToKilograms() async throws {
        let normalized = PriceParsingService.normalize(
            price: Decimal(string: "3.99")!,
            unit: .lb,
            quantity: nil
        )

        #expect(normalized?.1 == .kg)
        #expect(normalized?.0 == Decimal(string: "8.7964442610"))
    }

    @Test func draftRequiresExplicitStoreSelection() async throws {
        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"

        #expect(draft.canSave == false)

        draft.storeChainExplicitlySelected = true
        #expect(draft.canSave == true)
    }

    @Test func detectsReceiptLikeText() async throws {
        let text = """
        Calgary Co-op
        Subtotal 12.99
        GST 0.65
        Total 13.64
        Thank you
        """

        #expect(PriceParsingService.looksLikeReceipt(text: text) == true)
    }

}
