import Foundation
import Testing
@testable import Prixio

@MainActor
struct ParserEvaluationTests {
    struct EvaluationCase {
        let name: String
        let observations: [OCRTextObservation]
        let expectedItemName: String
        let expectedPrice: Decimal
        let expectedUnit: UnitType?
        let expectedQuantity: Decimal?
        let expectedReviewState: OCRReviewState
        let expectsFoundationModel: Bool
    }

    @Test(.tags(.ocr, .product, .evaluation, .shipGate, .realWorldOCR))
    func realWorldFixtureEvaluationReportsSummaryAndMatchesExpectedOutputs() async throws {
        let cases = [
            EvaluationCase(
                name: "member promo beverage tag",
                observations: [
                    OCRTextObservation(string: "MBR PRICE", confidence: 0.79),
                    OCRTextObservation(string: "Dr Pepper Zero 12 PK", confidence: 0.88),
                    OCRTextObservation(string: "2/$11", confidence: 0.86),
                    OCRTextObservation(string: "Regular 6.49", confidence: 0.82),
                    OCRTextObservation(string: "plus dep", confidence: 0.75)
                ],
                expectedItemName: "Dr Pepper Zero 12 PK",
                expectedPrice: Decimal(string: "11")!,
                expectedUnit: .each,
                expectedQuantity: Decimal(2),
                expectedReviewState: .clean,
                expectsFoundationModel: false
            ),
            EvaluationCase(
                name: "deposit heavy beverage tag",
                observations: [
                    OCRTextObservation(string: "Sparkling Water 12 PK", confidence: 0.93),
                    OCRTextObservation(string: "$5.99", confidence: 0.91),
                    OCRTextObservation(string: "$1.20 dep", confidence: 0.84),
                    OCRTextObservation(string: "12 x 355 mL", confidence: 0.88)
                ],
                expectedItemName: "Sparkling Water 12 PK",
                expectedPrice: Decimal(string: "5.99")!,
                expectedUnit: .each,
                expectedQuantity: Decimal(12),
                expectedReviewState: .reviewRequired,
                expectsFoundationModel: true
            ),
            EvaluationCase(
                name: "flyer noise shelf tag",
                observations: [
                    OCRTextObservation(string: "WEEKLY SPECIAL", confidence: 0.73),
                    OCRTextObservation(string: "Organic Raspberries", confidence: 0.92),
                    OCRTextObservation(string: "$3.99 ea", confidence: 0.90),
                    OCRTextObservation(string: "SAVE 2.00", confidence: 0.78),
                    OCRTextObservation(string: "Valid Fri Sat Sun", confidence: 0.76)
                ],
                expectedItemName: "Organic Raspberries",
                expectedPrice: Decimal(string: "3.99")!,
                expectedUnit: .each,
                expectedQuantity: nil,
                expectedReviewState: .clean,
                expectsFoundationModel: false
            ),
            EvaluationCase(
                name: "side by side products still require review",
                observations: [
                    OCRTextObservation(string: "Coke Zero", confidence: 0.93),
                    OCRTextObservation(string: "$2.99", confidence: 0.91),
                    OCRTextObservation(string: "Pepsi", confidence: 0.92),
                    OCRTextObservation(string: "$3.49", confidence: 0.90)
                ],
                expectedItemName: "Coke Zero",
                expectedPrice: Decimal(string: "2.99")!,
                expectedUnit: nil,
                expectedQuantity: nil,
                expectedReviewState: .reviewRequired,
                expectsFoundationModel: true
            )
        ]

        var matchedPriceCount = 0
        var matchedUnitCount = 0
        var matchedQuantityCount = 0
        var matchedItemCount = 0
        var matchedReviewStateCount = 0
        var foundationModelCount = 0

        for evaluationCase in cases {
            let result = await PriceParsingService.extract(from: evaluationCase.observations)

            if result.price == evaluationCase.expectedPrice { matchedPriceCount += 1 }
            if result.unit == evaluationCase.expectedUnit { matchedUnitCount += 1 }
            if result.quantity == evaluationCase.expectedQuantity { matchedQuantityCount += 1 }
            if result.itemNameHint == evaluationCase.expectedItemName { matchedItemCount += 1 }
            if result.review.state == evaluationCase.expectedReviewState { matchedReviewStateCount += 1 }
            if result.review.usedFoundationModel { foundationModelCount += 1 }

            #expect(result.itemNameHint == evaluationCase.expectedItemName, Comment(rawValue: evaluationCase.name))
            #expect(result.price == evaluationCase.expectedPrice, Comment(rawValue: evaluationCase.name))
            #expect(result.unit == evaluationCase.expectedUnit, Comment(rawValue: evaluationCase.name))
            #expect(result.quantity == evaluationCase.expectedQuantity, Comment(rawValue: evaluationCase.name))
            #expect(result.review.state == evaluationCase.expectedReviewState, Comment(rawValue: evaluationCase.name))
            #expect(result.review.usedFoundationModel == evaluationCase.expectsFoundationModel, Comment(rawValue: evaluationCase.name))
        }

        let total = cases.count
        print(
            """
            Parser evaluation summary:
            - fixtures: \(total)
            - matched price: \(matchedPriceCount)/\(total)
            - matched unit: \(matchedUnitCount)/\(total)
            - matched quantity: \(matchedQuantityCount)/\(total)
            - matched item name: \(matchedItemCount)/\(total)
            - matched review state: \(matchedReviewStateCount)/\(total)
            - FM-assisted cases observed: \(foundationModelCount)
            """
        )
    }
}
