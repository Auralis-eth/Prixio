//
//  PriceParsingServiceAmbiguityTests.swift
//  PrixioTests
//
//  Created by Codex on 8/16/25.
//

import Foundation
import Testing
@testable import Prixio

struct PriceParsingServiceAmbiguityTests {
    struct AmbiguityCase {
        let name: String
        let observations: [OCRTextObservation]
        let expectedWeaknesses: Set<PriceParsingService.ExtractionWeakness>
        let shouldEscalate: Bool
    }

    @Test(
        .tags(.ocr, .product),
        arguments: [
            AmbiguityCase(
                name: "clean single product tag stays heuristic",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.92),
                    OCRTextObservation(string: "$1.29 /lb", confidence: 0.91)
                ],
                expectedWeaknesses: [],
                shouldEscalate: false
            ),
            AmbiguityCase(
                name: "missing price escalates",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.91),
                    OCRTextObservation(string: "Great taste /lb", confidence: 0.88)
                ],
                expectedWeaknesses: [.noPriceCandidates],
                shouldEscalate: true
            ),
            AmbiguityCase(
                name: "competing prices escalate",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
                    OCRTextObservation(string: "$3.99", confidence: 0.94),
                    OCRTextObservation(string: "$4.49", confidence: 0.94)
                ],
                expectedWeaknesses: [.missingUnit, .missingQuantity],
                shouldEscalate: true
            ),
            AmbiguityCase(
                name: "single weak line is sparse",
                observations: [
                    OCRTextObservation(string: "$3.99", confidence: 0.66)
                ],
                expectedWeaknesses: [.missingItemName, .missingUnit, .sparseOCR],
                shouldEscalate: true
            ),
            AmbiguityCase(
                name: "multiple products in frame escalate",
                observations: [
                    OCRTextObservation(string: "Coke Zero", confidence: 0.93),
                    OCRTextObservation(string: "$2.99", confidence: 0.91),
                    OCRTextObservation(string: "Pepsi", confidence: 0.92),
                    OCRTextObservation(string: "$3.49", confidence: 0.90)
                ],
                expectedWeaknesses: [.multipleCompetingPrices, .missingUnit, .possibleMultiProductScan],
                shouldEscalate: true
            )
        ]
    )
    @MainActor
    func analyzesAmbiguity(case testCase: AmbiguityCase) async throws {
        let report = PriceParsingService._test_analyzeAmbiguity(testCase.observations)

        #expect(report.shouldUseFoundationModel == testCase.shouldEscalate, Comment(rawValue: testCase.name))
        #expect(Set(report.weaknesses).isSuperset(of: testCase.expectedWeaknesses), Comment(rawValue: testCase.name))
    }

    @Test(.tags(.ocr, .product))
    @MainActor
    func proximityScoringKeepsCloserShelfPriceAsTopCandidate() async throws {
        let observations = [
            OCRTextObservation(string: "Organic Mango", confidence: 0.95),
            OCRTextObservation(string: "$1.49 ea", confidence: 0.89),
            OCRTextObservation(string: "$2.49", confidence: 0.89)
        ]
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(observations)
        let report = PriceParsingService._test_analyzeAmbiguity(observations)

        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "1.49"))
        #expect(report.weaknesses.contains(.multipleCompetingPrices) == false)
        #expect(report.shouldUseFoundationModel == false)
    }

    @Test(.tags(.ocr, .product))
    @MainActor
    func saleMarkersOutrankRegularPriceFallback() async throws {
        let observations = [
            OCRTextObservation(string: "Fresh Blueberries", confidence: 0.95),
            OCRTextObservation(string: "Sale $3.99 ea", confidence: 0.90),
            OCRTextObservation(string: "Regular $4.99 ea", confidence: 0.90)
        ]
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(observations)
        let report = PriceParsingService._test_analyzeAmbiguity(observations)

        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "3.99"))
        #expect(report.weaknesses.contains(.multipleCompetingPrices) == false)
    }

    @Test(.tags(.ocr, .product))
    @MainActor
    func depositFeeLineDoesNotCompeteWithPrimaryShelfPrice() async throws {
        let observations = [
            OCRTextObservation(string: "Sparkling Water", confidence: 0.94),
            OCRTextObservation(string: "$5.99", confidence: 0.91),
            OCRTextObservation(string: "$0.10 deposit", confidence: 0.91)
        ]
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(observations)
        let report = PriceParsingService._test_analyzeAmbiguity(observations)

        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "5.99"))
        #expect(report.weaknesses.contains(.multipleCompetingPrices) == false)
    }

    @Test(.tags(.ocr, .product))
    @MainActor
    func cleanScanProducesHighConfidenceResult() async throws {
        let result = PriceParsingService._test_makeOCRResult([
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.92),
            OCRTextObservation(string: "$1.29 /lb", confidence: 0.91)
        ])

        #expect((result.confidence ?? 0) >= 0.85)
    }

    @Test(.tags(.ocr, .product))
    @MainActor
    func weakSingleLineScanProducesLowConfidenceResult() async throws {
        let result = PriceParsingService._test_makeOCRResult([
            OCRTextObservation(string: "$3.99", confidence: 0.66)
        ])

        #expect((result.confidence ?? 1) <= 0.45)
    }

    @Test(.tags(.ocr, .product))
    @MainActor
    func conflictingScanProducesLowerConfidenceThanCleanScan() async throws {
        let cleanResult = PriceParsingService._test_makeOCRResult([
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.92),
            OCRTextObservation(string: "$1.29 /lb", confidence: 0.91)
        ])
        let conflictingResult = PriceParsingService._test_makeOCRResult([
            OCRTextObservation(string: "Coke Zero", confidence: 0.93),
            OCRTextObservation(string: "$2.99", confidence: 0.91),
            OCRTextObservation(string: "Pepsi", confidence: 0.92),
            OCRTextObservation(string: "$3.49", confidence: 0.90)
        ])

        #expect((conflictingResult.confidence ?? 0) < (cleanResult.confidence ?? 1))
        #expect((conflictingResult.confidence ?? 1) <= 0.65)
    }
}
