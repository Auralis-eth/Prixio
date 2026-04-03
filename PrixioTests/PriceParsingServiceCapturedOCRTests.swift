import Foundation
import Testing
@testable import Prixio

@MainActor
struct PriceParsingServiceCapturedOCRTests {
    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRSnapshotKeepsTrueShelfPriceEvidence() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(
            CapturedOCRFixtures.cadburyShelfTagObservations()
        )

        #expect(snapshot.cleanedObservations.map(\.string).contains("1799"))
        #expect(snapshot.normalizedObservations.map(\.string).contains("$5.00 ea"))
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "17.99"))
        #expect(snapshot.priceCandidates.contains(where: { $0.value == Decimal(string: "5") }))
        #expect(snapshot.priceCandidates.contains(where: { $0.value == Decimal(string: "8.75") }) == false)
        #expect(snapshot.itemNameHint == "Cadbury Chocolate Mini Eggs")
        #expect(snapshot.detectedUnit == .each)
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRFinalResultStaysOnShelfPrice() async throws {
        let result = await PriceParsingService.extract(
            from: CapturedOCRFixtures.cadburyShelfTagObservations()
        )

        #expect(result.itemNameHint == "Cadbury Chocolate Mini Eggs")
        #expect(result.price == Decimal(string: "17.99"))
        #expect(result.unit == .each)
        #expect(result.review.usedFoundationModel)
        #expect(result.priceCandidates.first?.value == Decimal(string: "17.99"))
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRAssistedMergeDoesNotReplaceWinnerWithSaveAmount() async throws {
        let observations = CapturedOCRFixtures.cadburyShelfTagObservations()
        let result = PriceParsingService._test_mergeAssistedExtraction(
            observations: observations,
            assisted: PriceParsingService._test_assistedExtractionResult(
                targetLineIndexes: [1, 2],
                selectedPriceCandidateIndex: 1,
                selectedPriceKind: .sale,
                canonicalItemName: "Cadbury Chocolate Mini Eggs",
                ambiguityNotes: ["save amount nearby"],
                confidenceBucket: .high
            )
        )

        #expect(result.price == Decimal(string: "17.99"))
        #expect(result.itemNameHint == "Cadbury Chocolate Mini Eggs")
        #expect(result.review.usedFoundationModel)
    }
}
