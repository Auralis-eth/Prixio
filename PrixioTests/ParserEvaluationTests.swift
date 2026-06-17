import Foundation
import Testing
@testable import Prixio

/// End-to-end evaluation of the image-AI Capture pipeline using fixed `LLMOCRResult`
/// fixtures (model availability/sampling are not stable CI inputs — see Migration §8).
/// Each fixture stands in for the structured fields the model emits; the test asserts
/// that PriceDraftBuilder + PriceExtractionValidator produce the expected draft/review.
@MainActor
struct ParserEvaluationTests {
    struct EvaluationCase {
        let name: String
        let result: LLMOCRResult
        let expectedItemName: String
        let expectedPrice: Decimal
        let expectedUnit: UnitType?
        let expectedQuantity: Decimal?
        let expectedReviewState: OCRReviewState
    }

    @Test(.tags(.ocr, .product, .evaluation, .shipGate, .realWorldOCR))
    func fixtureDrivenEvaluationMatchesExpectedDraftOutputs() async throws {
        let cases: [EvaluationCase] = [
            EvaluationCase(
                name: "member promo beverage tag",
                result: .fixture(
                    relevantText: "MBR PRICE\nDr Pepper Zero 12 PK\n2/$11\nRegular 6.49\nplus dep",
                    scene: .promoCard,
                    priceCandidates: [
                        .fixture(label: "MBR", value: Decimal(string: "11")!, quantity: Decimal(2), kind: .member, sourceText: "2/$11"),
                        .fixture(label: "Regular", value: Decimal(string: "6.49")!, kind: .regular, sourceText: "Regular 6.49")
                    ],
                    itemName: "Dr Pepper Zero 12 PK",
                    price: Decimal(string: "11"),
                    unit: .each,
                    quantity: Decimal(2)
                ),
                expectedItemName: "Dr Pepper Zero 12 PK",
                expectedPrice: Decimal(string: "11")!,
                expectedUnit: .each,
                expectedQuantity: Decimal(2),
                expectedReviewState: .clean
            ),
            EvaluationCase(
                name: "deposit heavy beverage tag",
                result: .fixture(
                    relevantText: "Sparkling Water 12 PK\n$5.99\n$1.20 dep\n12 x 355 mL",
                    priceCandidates: [
                        .fixture(value: Decimal(string: "5.99")!, kind: .shelf, sourceText: "$5.99"),
                        .fixture(label: "dep", value: Decimal(string: "1.20")!, kind: .deposit, sourceText: "$1.20 dep")
                    ],
                    itemName: "Sparkling Water 12 PK",
                    price: Decimal(string: "5.99"),
                    unit: .each,
                    quantity: Decimal(12)
                ),
                expectedItemName: "Sparkling Water 12 PK",
                expectedPrice: Decimal(string: "5.99")!,
                expectedUnit: .each,
                expectedQuantity: Decimal(12),
                expectedReviewState: .clean
            ),
            EvaluationCase(
                name: "flyer noise shelf tag",
                result: .fixture(
                    relevantText: "WEEKLY SPECIAL\nOrganic Raspberries\n$3.99 ea\nSAVE 2.00\nValid Fri Sat Sun",
                    scene: .promoCard,
                    priceCandidates: [.fixture(value: Decimal(string: "3.99")!, kind: .shelf, sourceText: "$3.99 ea")],
                    itemName: "Organic Raspberries",
                    price: Decimal(string: "3.99"),
                    unit: .each
                ),
                expectedItemName: "Organic Raspberries",
                expectedPrice: Decimal(string: "3.99")!,
                expectedUnit: .each,
                expectedQuantity: nil,
                expectedReviewState: .clean
            ),
            EvaluationCase(
                name: "side by side products require review",
                result: .fixture(
                    relevantText: "Coke Zero $2.99\nPepsi $3.49",
                    scene: .multiTag,
                    priceCandidates: [
                        .fixture(value: Decimal(string: "2.99")!, sourceText: "Coke Zero $2.99"),
                        .fixture(value: Decimal(string: "3.49")!, sourceText: "Pepsi $3.49")
                    ],
                    itemName: "Coke Zero",
                    price: Decimal(string: "2.99"),
                    unit: .each,
                    issues: [.priceOwnershipUncertain]
                ),
                expectedItemName: "Coke Zero",
                expectedPrice: Decimal(string: "2.99")!,
                expectedUnit: .each,
                expectedQuantity: nil,
                expectedReviewState: .reviewRequired
            )
        ]

        for evaluationCase in cases {
            let draft = PriceDraftBuilder.makeDraft(from: evaluationCase.result, image: nil)
            let comment = Comment(rawValue: evaluationCase.name)

            #expect(draft.itemName == evaluationCase.expectedItemName, comment)
            #expect(draft.parsedPrice == evaluationCase.expectedPrice, comment)
            #expect(draft.selectedUnit == evaluationCase.expectedUnit, comment)
            #expect(draft.quantity == evaluationCase.expectedQuantity, comment)
            #expect(draft.review.state == evaluationCase.expectedReviewState, comment)
        }
    }
}
