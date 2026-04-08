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
        #expect(result.parserDecisionReport?.reasons.contains(where: { $0.category == .ownership && $0.code == "single_tag_scene" }) == true)
        #expect(result.parserDecisionReport?.reasons.contains(where: { $0.category == .candidateKind && $0.code == "winning_price_kind_unit" }) == true)
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
        #expect(result.parserDecisionReport?.reasons.contains(where: { $0.category == .ownership && $0.code == "scene_unclear" }) == true)
        #expect(result.parserDecisionReport?.reasons.contains(where: { $0.category == .review && $0.code == "possibleMultiProductScan" }) == true)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func weakSparseScanCarriesLowConfidenceReviewSignal() async throws {
        let observations = [
            OCRTextObservation(string: "$3.99", confidence: 0.66)
        ]

        let result = await PriceParsingService.extract(from: observations)

        #expect(result.review.issues.contains(.lowConfidence))
        #expect((result.confidence ?? 1) < 0.5)
        #expect(result.parserDecisionReport?.reasons.contains(where: { $0.category == .ocr && $0.code == "sparse_ocr" }) == true)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func promoCardShapeCanStayReviewRecommendedWithoutLowConfidence() async throws {
        let observations = [
            OCRTextObservation(string: "WEEKLY SPECIAL", confidence: 0.73),
            OCRTextObservation(string: "Organic Raspberries", confidence: 0.92),
            OCRTextObservation(string: "$3.99 ea", confidence: 0.90),
            OCRTextObservation(string: "SAVE 2.00", confidence: 0.78),
            OCRTextObservation(string: "Valid Fri Sat Sun", confidence: 0.76)
        ]

        let result = await PriceParsingService.extract(from: observations)

        #expect(result.review.issues.contains(.lowConfidence) == false)
        #expect((result.confidence ?? 0) >= 0.55)
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
        #expect(result.parserDecisionReport?.reasons.contains(where: { $0.category == .review && $0.code == "foundation_model_used" }) == true)
    }
}
