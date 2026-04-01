import Foundation
import Testing
@testable import Prixio

@MainActor
struct OCRReviewStateTests {
    @Test(.tags(.ocr, .product, .shipGate))
    func cleanHeuristicParseProducesCleanReviewState() async throws {
        let observations = [
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.92),
            OCRTextObservation(string: "$1.29 /lb", confidence: 0.91)
        ]

        let result = await PriceParsingService.extract(from: observations)

        #expect(result.review.state == .clean)
        #expect(result.review.usedFoundationModel == false)
        #expect(result.review.issues.isEmpty)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func multiProductScanProducesRequiredReviewState() async throws {
        let observations = [
            OCRTextObservation(string: "Coke Zero", confidence: 0.93),
            OCRTextObservation(string: "$2.99", confidence: 0.91),
            OCRTextObservation(string: "Pepsi", confidence: 0.92),
            OCRTextObservation(string: "$3.49", confidence: 0.90)
        ]

        let result = await PriceParsingService.extract(from: observations)

        #expect(result.review.state == .reviewRequired)
        #expect(result.review.issues.contains(.possibleMultiProductScan))
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func assistedMergeMarksResultAsFoundationModelReview() async throws {
        let observations = [
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
            OCRTextObservation(string: "$3.99", confidence: 0.93),
            OCRTextObservation(string: "$2.99", confidence: 0.93)
        ]
        let assisted = PriceParsingService._test_assistedExtractionResult(
            targetLineIndexes: [0, 2],
            selectedPriceCandidateIndex: 1,
            selectedPriceKind: .sale,
            canonicalItemName: "Fresh Bananas",
            ambiguityNotes: ["two nearby prices"],
            confidenceBucket: .high
        )

        let result = PriceParsingService._test_mergeAssistedExtraction(
            observations: observations,
            assisted: assisted
        )

        #expect(result.review.usedFoundationModel)
        #expect(result.review.state == .reviewRequired)
        #expect(result.review.ambiguityNotes == ["two nearby prices"])
    }
}
