import Foundation
import Testing
@testable import Prixio

@MainActor
struct ParserShipGateTests {
    @Test(.tags(.ocr, .product, .shipGate))
    func cleanSingleProductParseStaysHighConfidence() async throws {
        let result = await PriceParsingService.extract(from: [
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.92),
            OCRTextObservation(string: "$1.29 /lb", confidence: 0.91)
        ])

        #expect(result.itemNameHint == "Fresh Bananas")
        #expect(result.price == Decimal(string: "1.29"))
        #expect(result.unit == .lb)
        #expect(result.review.state == .clean)
        #expect((result.confidence ?? 0) >= 0.85)
        #expect(result.review.usedFoundationModel == false)
        #expect(result.parserDecisionReport?.reasons.contains(where: { $0.code == "stable_parse" }) == true)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func memberPromoRealWorldFixtureKeepsWinningMultiBuyPrice() async throws {
        let result = await PriceParsingService.extract(from: [
            OCRTextObservation(string: "MBR PRICE", confidence: 0.79),
            OCRTextObservation(string: "Dr Pepper Zero 12 PK", confidence: 0.88),
            OCRTextObservation(string: "2/$11", confidence: 0.86),
            OCRTextObservation(string: "Regular 6.49", confidence: 0.82),
            OCRTextObservation(string: "plus dep", confidence: 0.75)
        ])

        #expect(result.itemNameHint == "Dr Pepper Zero 12 PK")
        #expect(result.price == Decimal(string: "11"))
        #expect(result.quantity == Decimal(2))
        #expect(result.unit == .each)
        #expect(result.review.state == .clean)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func multiProductScanRequiresReview() async throws {
        let result = await PriceParsingService.extract(from: [
            OCRTextObservation(string: "Coke Zero", confidence: 0.93),
            OCRTextObservation(string: "$2.99", confidence: 0.91),
            OCRTextObservation(string: "Pepsi", confidence: 0.92),
            OCRTextObservation(string: "$3.49", confidence: 0.90)
        ])

        #expect(result.price == Decimal(string: "2.99"))
        #expect(result.review.state == .reviewRequired)
        #expect(result.review.issues.contains(.possibleMultiProductScan))
        #expect(result.review.usedFoundationModel)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func assistedMergeStillRewardsHelpfulAssist() async throws {
        let observations = [
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
            OCRTextObservation(string: "$3.99", confidence: 0.93),
            OCRTextObservation(string: "$2.99", confidence: 0.93)
        ]

        let agreeing = PriceParsingService._test_mergeAssistedExtraction(
            observations: observations,
            assisted: PriceParsingService._test_assistedExtractionResult(
                targetLineIndexes: [0, 2],
                selectedPriceCandidateIndex: 1,
                selectedPriceKind: .sale,
                canonicalItemName: "Fresh Bananas",
                ambiguityNotes: [],
                confidenceBucket: .high
            )
        )
        let weak = PriceParsingService._test_mergeAssistedExtraction(
            observations: observations,
            assisted: PriceParsingService._test_assistedExtractionResult(
                targetLineIndexes: [0, 2],
                selectedPriceCandidateIndex: 1,
                selectedPriceKind: .sale,
                canonicalItemName: "Organic Bananas",
                ambiguityNotes: ["low certainty"],
                confidenceBucket: .low
            )
        )

        #expect((agreeing.confidence ?? 0) > (weak.confidence ?? 0))
        #expect(agreeing.review.usedFoundationModel)
    }

    @Test(.tags(.ocr, .product, .shipGate, .realWorldOCR))
    func compactNumericPLUTrapStaysOnUnitPriceWithoutFM() async throws {
        let result = await PriceParsingService.extract(
            from: CapturedOCRFixtures.bananasStage4Observations()
        )

        #expect(result.itemNameHint == "Bananas Stage 4 PLU 4011")
        #expect(result.price == Decimal(string: "5.45"))
        #expect(result.unit == .kg)
        #expect(result.review.usedFoundationModel == false)
        #expect(result.parserDecisionReport?.reasons.contains(where: { $0.code == "winning_price_kind_unit" }) == true)
    }
}
