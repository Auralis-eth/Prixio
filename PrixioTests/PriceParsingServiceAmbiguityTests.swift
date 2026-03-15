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
                expectedWeaknesses: [.multipleCompetingPrices, .missingUnit],
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
    func analyzesAmbiguity(case testCase: AmbiguityCase) async throws {
        let report = PriceParsingService._test_analyzeAmbiguity(testCase.observations)

        #expect(report.shouldUseFoundationModel == testCase.shouldEscalate, Comment(rawValue: testCase.name))
        #expect(Set(report.weaknesses).isSuperset(of: testCase.expectedWeaknesses), Comment(rawValue: testCase.name))
    }
}
