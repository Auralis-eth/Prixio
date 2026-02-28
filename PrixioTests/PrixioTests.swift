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
        let result = PriceParsingService.extract(from: "Yellow Onions\n2/$5\nProduct of Canada")

        #expect(result.itemNameHint == "Yellow Onions")
        #expect(result.price == Decimal(string: "5"))
        #expect(result.quantity == Decimal(string: "2"))
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
