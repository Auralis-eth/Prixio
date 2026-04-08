//
//  PriceParsingServiceAmbiguityTests.swift
//  PrixioTests
//
//  Created by Codex on 8/16/25.
//

import CoreGraphics
import Foundation
import Testing
@testable import Prixio

@MainActor
struct PriceParsingServiceAmbiguityTests {
    struct AmbiguityCase {
        let name: String
        let observations: [OCRTextObservation]
        let expectedSceneClassification: PriceParsingService.SceneClassification
        let expectedWeaknesses: Set<PriceParsingService.ExtractionWeakness>
        let shouldEscalate: Bool
    }

    @Test(
        .tags(.ocr, .product, .shipGate),
        arguments: [
            AmbiguityCase(
                name: "clean single product tag stays heuristic",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.92),
                    OCRTextObservation(string: "$1.29 /lb", confidence: 0.91)
                ],
                expectedSceneClassification: .singleTag,
                expectedWeaknesses: [],
                shouldEscalate: false
            ),
            AmbiguityCase(
                name: "missing price escalates",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.91),
                    OCRTextObservation(string: "Great taste /lb", confidence: 0.88)
                ],
                expectedSceneClassification: .unclear,
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
                expectedSceneClassification: .unclear,
                expectedWeaknesses: [.missingUnit, .missingQuantity],
                shouldEscalate: true
            ),
            AmbiguityCase(
                name: "single weak line is sparse",
                observations: [
                    OCRTextObservation(string: "$3.99", confidence: 0.66)
                ],
                expectedSceneClassification: .unclear,
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
                expectedSceneClassification: .unclear,
                expectedWeaknesses: [.multipleCompetingPrices, .missingUnit, .possibleMultiProductScan],
                shouldEscalate: true
            ),
            AmbiguityCase(
                name: "stable packaged good without unit stays heuristic",
                observations: [
                    OCRTextObservation(string: "Sparkling Water", confidence: 0.94),
                    OCRTextObservation(string: "$5.99", confidence: 0.91),
                    OCRTextObservation(string: "$0.10 deposit", confidence: 0.91)
                ],
                expectedSceneClassification: .singleTag,
                expectedWeaknesses: [.missingUnit, .missingQuantity],
                shouldEscalate: false
            ),
            AmbiguityCase(
                name: "member promo with regular fallback stays heuristic when winner is clear",
                observations: [
                    OCRTextObservation(string: "MBR PRICE", confidence: 0.79),
                    OCRTextObservation(string: "Dr Pepper Zero 12 PK", confidence: 0.88),
                    OCRTextObservation(string: "2/$11", confidence: 0.86),
                    OCRTextObservation(string: "Regular 6.49", confidence: 0.82),
                    OCRTextObservation(string: "plus dep", confidence: 0.75)
                ],
                expectedSceneClassification: .singleTag,
                expectedWeaknesses: [],
                shouldEscalate: false
            ),
            AmbiguityCase(
                name: "flyer style promo noise does not force escalation by itself",
                observations: [
                    OCRTextObservation(string: "WEEKLY SPECIAL", confidence: 0.73),
                    OCRTextObservation(string: "Organic Raspberries", confidence: 0.92),
                    OCRTextObservation(string: "$3.99 ea", confidence: 0.90),
                    OCRTextObservation(string: "SAVE 2.00", confidence: 0.78),
                    OCRTextObservation(string: "Valid Fri Sat Sun", confidence: 0.76)
                ],
                expectedSceneClassification: .promoCard,
                expectedWeaknesses: [],
                shouldEscalate: false
            ),
            AmbiguityCase(
                name: "receipt-like scene is classified conservatively",
                observations: [
                    OCRTextObservation(string: "Subtotal", confidence: 0.91),
                    OCRTextObservation(string: "Tax", confidence: 0.89),
                    OCRTextObservation(string: "Total", confidence: 0.93),
                    OCRTextObservation(string: "Visa", confidence: 0.90)
                ],
                expectedSceneClassification: .receiptLike,
                expectedWeaknesses: [.noPriceCandidates, .missingItemName, .missingUnit],
                shouldEscalate: true
            )
        ]
    )
    func analyzesAmbiguity(case testCase: AmbiguityCase) async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(testCase.observations)
        let report = PriceParsingService._test_analyzeAmbiguity(testCase.observations)

        #expect(snapshot.sceneClassification == testCase.expectedSceneClassification, Comment(rawValue: testCase.name))
        #expect(report.shouldUseFoundationModel == testCase.shouldEscalate, Comment(rawValue: testCase.name))
        #expect(Set(report.weaknesses).isSuperset(of: testCase.expectedWeaknesses), Comment(rawValue: testCase.name))
    }

    @Test(.tags(.ocr, .product))
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

    @Test(.tags(.ocr, .product, .shipGate, .realWorldOCR))
    func shelfTagClusterBeatsPackagingNoiseWhenPriceLivesInSeparateColumn() async throws {
        let observations = [
            OCRTextObservation(
                string: "Cadbury Chocolate Mini",
                confidence: 0.85,
                boundingBox: CGRect(x: 0.35, y: 0.48, width: 0.28, height: 0.03)
            ),
            OCRTextObservation(
                string: "Eggs 875 g",
                confidence: 0.83,
                boundingBox: CGRect(x: 0.35, y: 0.44, width: 0.18, height: 0.03)
            ),
            OCRTextObservation(
                string: "22.99",
                confidence: 0.87,
                boundingBox: CGRect(x: 0.78, y: 0.48, width: 0.10, height: 0.04)
            ),
            OCRTextObservation(
                string: "SAVE THIS WEEK",
                confidence: 0.88,
                boundingBox: CGRect(x: 0.32, y: 0.35, width: 0.20, height: 0.04)
            ),
            OCRTextObservation(
                string: "17.99",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.66, y: 0.34, width: 0.17, height: 0.07)
            ),
            OCRTextObservation(
                string: "Cadbury",
                confidence: 0.96,
                boundingBox: CGRect(x: 0.08, y: 0.76, width: 0.12, height: 0.03)
            ),
            OCRTextObservation(
                string: "Mini Eggs",
                confidence: 0.96,
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.16, height: 0.05)
            ),
            OCRTextObservation(
                string: "8.75",
                confidence: 0.86,
                boundingBox: CGRect(x: 0.12, y: 0.63, width: 0.08, height: 0.04)
            )
        ]
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(observations)

        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "17.99"))
        #expect(snapshot.itemNameHint?.contains("Cadbury Chocolate Mini Eggs") == true)
    }

    @Test(.tags(.ocr, .product))
    func assistedNameFallbackMergesAdjacentDescriptorLines() async throws {
        let observations = [
            OCRTextObservation(string: "Cadbury Chocolate Mini", confidence: 0.9),
            OCRTextObservation(string: "Eggs 875 g", confidence: 0.9),
            OCRTextObservation(string: "$17.99", confidence: 0.9)
        ]
        let assisted = PriceParsingService._test_assistedExtractionResult(
            targetLineIndexes: [0, 1, 2],
            selectedPriceCandidateIndex: nil,
            selectedPriceKind: .unknown,
            canonicalItemName: nil,
            ambiguityNotes: [],
            confidenceBucket: .medium
        )

        let result = PriceParsingService._test_mergeAssistedExtraction(
            observations: observations,
            assisted: assisted
        )

        #expect(result.itemNameHint == "Cadbury Chocolate Mini Eggs")
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func cleanScanProducesHighConfidenceResult() async throws {
        let result = PriceParsingService._test_makeOCRResult([
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.92),
            OCRTextObservation(string: "$1.29 /lb", confidence: 0.91)
        ])

        #expect((result.confidence ?? 0) >= 0.85)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func weakSingleLineScanProducesLowConfidenceResult() async throws {
        let result = PriceParsingService._test_makeOCRResult([
            OCRTextObservation(string: "$3.99", confidence: 0.66)
        ])

        #expect((result.confidence ?? 1) <= 0.45)
    }

    @Test(.tags(.ocr, .product))
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
