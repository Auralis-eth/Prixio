//
//  PriceParsingServiceFoundationModelAssistTests.swift
//  PrixioTests
//
//  Created by Codex on 8/16/25.
//

import Foundation
import Testing
@testable import Prixio

struct PriceParsingServiceFoundationModelAssistTests {
    struct AssistedMergeCase {
        let name: String
        let observations: [OCRTextObservation]
        let assisted: PriceParsingService.AssistedExtractionResult
        let expectedPrice: Decimal?
        let expectedItemName: String?
    }

    @Test(
        .tags(.ocr, .product),
        arguments: [
            AssistedMergeCase(
                name: "valid selected candidate overrides heuristic choice",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
                    OCRTextObservation(string: "$3.99", confidence: 0.93),
                    OCRTextObservation(string: "$2.99", confidence: 0.93)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [0, 2],
                    selectedPriceCandidateIndex: 1,
                    selectedPriceKind: .sale,
                    canonicalItemName: "Fresh Bananas",
                    ambiguityNotes: [],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "2.99"),
                expectedItemName: "Fresh Bananas"
            ),
            AssistedMergeCase(
                name: "out of range candidate index is ignored",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
                    OCRTextObservation(string: "$3.99", confidence: 0.93),
                    OCRTextObservation(string: "$2.99", confidence: 0.93)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [0],
                    selectedPriceCandidateIndex: 99,
                    selectedPriceKind: .sale,
                    canonicalItemName: nil,
                    ambiguityNotes: ["candidate out of range"],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "3.99"),
                expectedItemName: "Fresh Bananas"
            ),
            AssistedMergeCase(
                name: "canonical item name repairs weak heuristic name",
                observations: [
                    OCRTextObservation(string: "ORG GALA 3LB", confidence: 0.87),
                    OCRTextObservation(string: "$4.99", confidence: 0.92)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [0, 1],
                    selectedPriceCandidateIndex: 0,
                    selectedPriceKind: .regular,
                    canonicalItemName: "Organic Gala Apples",
                    ambiguityNotes: [],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "4.99"),
                expectedItemName: "Organic Gala Apples"
            ),
            AssistedMergeCase(
                name: "low confidence assist does not override heuristic price",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
                    OCRTextObservation(string: "$3.99", confidence: 0.93),
                    OCRTextObservation(string: "$2.99", confidence: 0.93)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [0, 2],
                    selectedPriceCandidateIndex: 1,
                    selectedPriceKind: .sale,
                    canonicalItemName: "Fresh Bananas",
                    ambiguityNotes: ["low certainty"],
                    confidenceBucket: .low
                ),
                expectedPrice: Decimal(string: "3.99"),
                expectedItemName: "Fresh Bananas"
            ),
            AssistedMergeCase(
                name: "noise candidate classification keeps heuristic price",
                observations: [
                    OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
                    OCRTextObservation(string: "$3.99", confidence: 0.93),
                    OCRTextObservation(string: "$2.99", confidence: 0.93)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [0, 2],
                    selectedPriceCandidateIndex: 1,
                    selectedPriceKind: .noise,
                    canonicalItemName: "Fresh Bananas",
                    ambiguityNotes: ["secondary price likely unrelated"],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "3.99"),
                expectedItemName: "Fresh Bananas"
            )
        ]
    )
    func mergesAssistedExtraction(case testCase: AssistedMergeCase) async throws {
        let result = PriceParsingService._test_mergeAssistedExtraction(
            observations: testCase.observations,
            assisted: testCase.assisted
        )

        #expect(result.price == testCase.expectedPrice, Comment(rawValue: testCase.name))
        #expect(result.itemNameHint == testCase.expectedItemName, Comment(rawValue: testCase.name))
    }
}
