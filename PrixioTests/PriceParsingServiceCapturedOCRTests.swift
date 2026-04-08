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
        #expect(snapshot.priceCandidates.first?.kind == .shelf)
        #expect(snapshot.priceCandidates.contains(where: { $0.value == Decimal(string: "5") }))
        #expect(snapshot.priceCandidates.contains(where: { $0.value == Decimal(string: "8.75") }) == false)
        #expect(snapshot.itemNameHint == "Cadbury Chocolate Mini Eggs")
        #expect(snapshot.detectedUnit == .each)
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRSnapshotPinsExactStageOutputs() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(
            CapturedOCRFixtures.cadburyShelfTagObservations()
        )

        #expect(snapshot.spatialGroups.first?.observations.map(\.string) == [
            "AD Exp Mar 04, 2026",
            "1799",
            "$5.00 ea",
            "- SAVE",
            "Cadbury Chocolate Mini",
            "Eggs Easter 875 g",
            "SAVE",
            "THIS WEEK",
            "Qadouro",
            "Mind",
            "Egg$",
            "Miur",
            "\"Eggs",
            "ini"
        ])
        #expect(snapshot.cleanedObservations.map(\.string) == [
            "AD Exp Mar 04, 2026",
            "1799",
            "$5.00 ea",
            "- SAVE",
            "Cadbury Chocolate Mini",
            "Eggs Easter 875 g",
            "THIS WEEK",
            "Qadouro",
            "Mind",
            "Egg$",
            "Miur",
            "\"Eggs"
        ])
        #expect(snapshot.normalizedObservations.map(\.string) == [
            "AD Exp Mar 04, 2026",
            "1799",
            "$5.00 ea",
            "- SAVE",
            "Cadbury Chocolate Mini",
            "Eggs Easter 875 g",
            "THIS WEEK",
            "Qadouro",
            "Mind",
            "Egg$",
            "Miur",
            "\"Eggs"
        ])
        #expect(snapshot.consolidatedObservations.map(\.string) == [
            "AD Exp Mar 04, 2026",
            "1799",
            "$5.00 ea",
            "- SAVE",
            "Cadbury Chocolate Mini",
            "Eggs Easter 875 g",
            "THIS WEEK",
            "Qadouro",
            "Mind",
            "Egg$",
            "Miur",
            "\"Eggs"
        ])
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRPinsExactAmbiguityContract() async throws {
        let report = PriceParsingService._test_analyzeAmbiguity(
            CapturedOCRFixtures.cadburyShelfTagObservations()
        )

        #expect(report.weaknesses == [.possibleMultiProductScan])
        #expect(report.shouldUseFoundationModel)
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRFinalResultStaysOnShelfPrice() async throws {
        let result = await PriceParsingService.extract(
            from: CapturedOCRFixtures.cadburyShelfTagObservations()
        )

        #expect(result.itemNameHint?.contains("Cadbury Chocolate Mini Eggs") == true)
        #expect(result.price == Decimal(string: "17.99"))
        #expect(result.unit == .each)
        #expect(result.review.state == .reviewRequired)
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
        #expect(result.review.state == .reviewRequired)
        #expect(result.review.usedFoundationModel)
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRAssistedMergePinsSupportingLinesContract() async throws {
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

        #expect(result.supportingLines == ["1799", "$5.00 ea"])
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRDirectItemNameResolverStaysClean() async throws {
        let observations = CapturedOCRFixtures.cadburyShelfTagObservations()
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(observations)
        let resolvedName = PriceParsingItemNameResolver().extractItemNameHint(
            from: snapshot.consolidatedObservations,
            priceCandidates: snapshot.priceCandidates
        )

        #expect(resolvedName == "Cadbury Chocolate Mini Eggs")
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedCadburyOCRDirectPriceScorerKeepsTrueCandidateAndRejectsSizeLeak() async throws {
        let observations = PriceParsingService._test_buildHeuristicSnapshot(
            CapturedOCRFixtures.cadburyShelfTagObservations()
        ).consolidatedObservations
        let scorer = PriceCandidateScorer()
        let rawCandidates = scorer.extractPriceCandidates(from: observations)
        let scoredCandidates = scorer.scorePriceCandidates(rawCandidates, in: observations)

        #expect(rawCandidates.contains(where: { $0.value == Decimal(string: "17.99") }))
        #expect(rawCandidates.contains(where: { $0.value == Decimal(string: "8.75") }) == false)
        #expect(scoredCandidates.first?.value == Decimal(string: "17.99"))
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedMiniCucumberOCRSnapshotKeepsOnlyTheProduceTitleAsItemName() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(
            CapturedOCRFixtures.miniCucumberObservations()
        )

        #expect(snapshot.spatialGroups.count == 1)
        #expect(snapshot.cleanedObservations.map(\.string) == [
            "MINI CUCUMBER",
            "Perfect for snacking",
            "High water content helps to keep you",
            "hydrated",
            "$4.00"
        ])
        #expect(snapshot.normalizedObservations.map(\.string) == [
            "MINI CUCUMBER",
            "Perfect for snacking",
            "High water content helps to keep you",
            "hydrated",
            "$4.00"
        ])
        #expect(snapshot.consolidatedObservations.map(\.string) == [
            "MINI CUCUMBER",
            "Perfect for snacking",
            "High water content helps to keep you",
            "hydrated",
            "$4.00"
        ])
        #expect(snapshot.itemNameHint == "MINI CUCUMBER")
        #expect(snapshot.priceCandidates.map(\.value) == [Decimal(4)])
        #expect(snapshot.detectedUnit == nil)
        #expect(snapshot.resolvedQuantity == nil)
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedMiniCucumberOCRFinalResultPinsCurrentReviewContract() async throws {
        let result = await PriceParsingService.extract(
            from: CapturedOCRFixtures.miniCucumberObservations()
        )

        #expect(result.itemNameHint == "MINI CUCUMBER")
        #expect(result.price == Decimal(string: "4"))
        #expect(result.unit == nil)
        #expect(result.quantity == nil)
        #expect(result.review.state == .reviewRecommended)
        #expect(result.review.issues == [.missingUnit, .missingQuantity])
        #expect(result.review.usedFoundationModel == false)
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedBananasStage4OCRUsesUnitBearingPriceInsteadOfPLUFragment() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(
            CapturedOCRFixtures.bananasStage4Observations()
        )
        let result = await PriceParsingService.extract(
            from: CapturedOCRFixtures.bananasStage4Observations()
        )

        #expect(snapshot.consolidatedObservations.map(\.string) == [
            ".99",
            ") 247",
            "545 / Kg",
            "Bananas Stage 4 PLU 4011",
            ".79.-"
        ])
        #expect(snapshot.winningClusterIndex == 0)
        #expect(snapshot.priceCandidates.map(\.value) == [Decimal(string: "5.45")!])
        #expect(snapshot.priceCandidates.first?.kind == .unit)
        #expect(snapshot.itemNameHint == "Bananas Stage 4 PLU 4011")
        #expect(snapshot.detectedUnit == .kg)
        #expect(result.itemNameHint == "Bananas Stage 4 PLU 4011")
        #expect(result.price == Decimal(string: "5.45"))
        #expect(result.unit == .kg)
        #expect(result.quantity == nil)
        #expect(result.review.state == .reviewRecommended)
        #expect(result.review.usedFoundationModel == false)
        #expect(result.supportingLines.contains("545 / Kg"))
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedSparseGrowerOCRPinsSparsePriceCompetitionContract() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(
            CapturedOCRFixtures.sparseGrowerObservations()
        )
        let ambiguity = PriceParsingService._test_analyzeAmbiguity(
            CapturedOCRFixtures.sparseGrowerObservations()
        )
        let result = await PriceParsingService.extract(
            from: CapturedOCRFixtures.sparseGrowerObservations()
        )

        #expect(snapshot.consolidatedObservations.map(\.string) == [
            "1908.0",
            "HGROWER. COM YE",
            "299"
        ])
        #expect(snapshot.priceCandidates.map(\.value) == [
            Decimal(string: "2.99")!,
            Decimal(string: "19.08")!
        ])
        #expect(snapshot.itemNameHint == "HGROWER. COM YE")
        #expect(ambiguity.weaknesses == [.missingUnit, .missingQuantity])
        #expect(ambiguity.shouldUseFoundationModel == false)
        #expect(result.itemNameHint == "HGROWER. COM YE")
        #expect(result.price == Decimal(string: "2.99"))
        #expect(result.unit == nil)
        #expect(result.quantity == nil)
        #expect(result.review.state == .reviewRecommended)
        #expect(result.review.usedFoundationModel == false)
        #expect(result.supportingLines == [
            "1908.0",
            "HGROWER. COM YE",
            "299"
        ])
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func capturedButterShelfOCRPrefersSaltedTagWithRecoverablePrice() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(
            CapturedOCRFixtures.butterShelfCompetingTagObservations()
        )
        let result = await PriceParsingService.extract(
            from: CapturedOCRFixtures.butterShelfCompetingTagObservations()
        )

        #expect(snapshot.cleanedObservations.map(\.string) == [
            "Comp Butter Salted",
            "454 g",
            "599"
        ])
        #expect(snapshot.consolidatedObservations.map(\.string) == [
            "Comp Butter Salted",
            "454 g",
            "599"
        ])
        #expect(snapshot.priceCandidates.map(\.value) == [Decimal(string: "5.99")!])
        #expect(snapshot.itemNameHint == "Comp Butter Salted")
        #expect(snapshot.detectedUnit == .each)
        #expect(snapshot.resolvedQuantity == nil)
        #expect(result.itemNameHint == "Comp Butter Salted")
        #expect(result.price == Decimal(string: "5.99"))
        #expect(result.unit == .each)
        #expect(result.quantity == nil)
        #expect(result.review.state == .clean)
        #expect(result.review.usedFoundationModel == false)
        #expect(result.supportingLines == [
            "Comp Butter Salted",
            "454 g",
            "599"
        ])
    }
}
