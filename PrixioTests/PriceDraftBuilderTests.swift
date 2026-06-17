import Foundation
import Testing
@testable import Prixio

@MainActor
struct PriceDraftBuilderTests {
    @Test(.tags(.ocr, .product))
    func copiesModelFieldsIntoDraft() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Fresh Bananas\n$1.29 /lb",
            priceCandidates: [.fixture(value: Decimal(string: "1.29")!, kind: .unit, sourceText: "$1.29 /lb")],
            itemName: "Fresh Bananas",
            price: Decimal(string: "1.29"),
            unit: .lb,
            quantity: Decimal(1)
        )

        let draft = PriceDraftBuilder.makeDraft(from: result, image: nil)

        #expect(draft.itemName == "Fresh Bananas")
        #expect(draft.parsedPrice == Decimal(string: "1.29"))
        #expect(draft.selectedUnit == .lb)
        #expect(draft.quantity == Decimal(1))
        #expect(draft.ocrText == "Fresh Bananas\n$1.29 /lb")
        #expect(draft.confidence == nil)
        #expect(draft.imageData == nil)
        #expect(draft.review.state == .clean)
    }

    @Test(.tags(.ocr, .product))
    func mapsCandidatesPreservingOrderWithDefaultedMetadata() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Apples\nSale $1.99\nRegular $2.49",
            priceCandidates: [
                .fixture(label: "Sale", value: Decimal(string: "1.99")!, kind: .sale, sourceText: "Sale $1.99"),
                .fixture(label: "Regular", value: Decimal(string: "2.49")!, kind: .regular, sourceText: "Regular $2.49")
            ],
            itemName: "Apples",
            price: Decimal(string: "1.99"),
            unit: .each
        )

        let draft = PriceDraftBuilder.makeDraft(from: result, image: nil)

        #expect(draft.priceCandidates.count == 2)
        #expect(draft.priceCandidates[0].priority == 0)
        #expect(draft.priceCandidates[1].priority == 1)
        #expect(draft.priceCandidates.allSatisfy { $0.confidence == 1.0 })
        #expect(draft.priceCandidates.allSatisfy { $0.sourceLineIndexes.isEmpty })
        #expect(draft.priceCandidates[0].kind == .sale)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func clearsSelectedUnitWhenModelContradictsTranscription() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Gala Apples\n$1.29 /lb",
            priceCandidates: [.fixture(value: Decimal(string: "1.29")!, kind: .unit, sourceText: "$1.29 /lb")],
            itemName: "Gala Apples",
            price: Decimal(string: "1.29"),
            unit: .each
        )

        let draft = PriceDraftBuilder.makeDraft(from: result, image: nil)

        #expect(draft.selectedUnit == nil)
        #expect(draft.review.issues.contains(.missingUnit))
    }
}
