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
        let expectedSupportingLines: [String]?
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
                expectedItemName: "Fresh Bananas",
                expectedSupportingLines: ["Fresh Bananas", "$2.99"]
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
                expectedItemName: "Fresh Bananas",
                expectedSupportingLines: ["Fresh Bananas"]
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
                expectedItemName: "Organic Gala Apples",
                expectedSupportingLines: ["ORG GALA 3 LB", "$4.99"]
            ),
            AssistedMergeCase(
                name: "regular candidate can replace heuristic sale pick when model isolates target product",
                observations: [
                    OCRTextObservation(string: "Greek Yogurt", confidence: 0.95),
                    OCRTextObservation(string: "Sale $3.99", confidence: 0.90),
                    OCRTextObservation(string: "Regular $4.49", confidence: 0.90)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [0, 2],
                    selectedPriceCandidateIndex: 1,
                    selectedPriceKind: .regular,
                    canonicalItemName: "Greek Yogurt",
                    ambiguityNotes: [],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "4.49"),
                expectedItemName: "Greek Yogurt",
                expectedSupportingLines: ["Greek Yogurt", "Regular $4.49"]
            ),
            AssistedMergeCase(
                name: "deposit classification does not override primary shelf price",
                observations: [
                    OCRTextObservation(string: "Sparkling Water", confidence: 0.94),
                    OCRTextObservation(string: "$5.99", confidence: 0.91),
                    OCRTextObservation(string: "$0.10 deposit", confidence: 0.91)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [0, 2],
                    selectedPriceCandidateIndex: 1,
                    selectedPriceKind: .deposit,
                    canonicalItemName: "Sparkling Water",
                    ambiguityNotes: ["deposit line"],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "5.99"),
                expectedItemName: "Sparkling Water",
                expectedSupportingLines: ["Sparkling Water", "$0.10 deposit"]
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
                    canonicalItemName: "Organic Bananas",
                    ambiguityNotes: ["low certainty"],
                    confidenceBucket: .low
                ),
                expectedPrice: Decimal(string: "3.99"),
                expectedItemName: "Fresh Bananas",
                expectedSupportingLines: ["Fresh Bananas", "$2.99"]
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
                expectedItemName: "Fresh Bananas",
                expectedSupportingLines: ["Fresh Bananas", "$2.99"]
            ),
            AssistedMergeCase(
                name: "multi product assist can select the second product cluster",
                observations: [
                    OCRTextObservation(string: "Coke Zero", confidence: 0.93),
                    OCRTextObservation(string: "$2.99", confidence: 0.91),
                    OCRTextObservation(string: "Pepsi", confidence: 0.92),
                    OCRTextObservation(string: "$3.49", confidence: 0.90)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [2, 3],
                    selectedPriceCandidateIndex: 1,
                    selectedPriceKind: .sale,
                    canonicalItemName: "Pepsi",
                    ambiguityNotes: ["second product cluster"],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "3.49"),
                expectedItemName: "Pepsi",
                expectedSupportingLines: ["Pepsi", "$3.49"]
            ),
            AssistedMergeCase(
                name: "realistic member-vs-regular tag can isolate the promo price",
                observations: [
                    OCRTextObservation(string: "MBR PRICE", confidence: 0.79),
                    OCRTextObservation(string: "Dr Pepper Zero 12 PK", confidence: 0.88),
                    OCRTextObservation(string: "2/$11", confidence: 0.86),
                    OCRTextObservation(string: "Regular 6.49", confidence: 0.82),
                    OCRTextObservation(string: "plus dep", confidence: 0.75)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [1, 2],
                    selectedPriceCandidateIndex: 0,
                    selectedPriceKind: .sale,
                    canonicalItemName: "Dr Pepper Zero 12 PK",
                    ambiguityNotes: ["member promo"],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "11"),
                expectedItemName: "Dr Pepper Zero 12 PK",
                expectedSupportingLines: ["Dr Pepper Zero 12 PK", "2/$11"]
            ),
            AssistedMergeCase(
                name: "realistic noisy branded name can be repaired without changing the price",
                observations: [
                    OCRTextObservation(string: "C0KE ZER0 SGR", confidence: 0.74),
                    OCRTextObservation(string: "2 L", confidence: 0.79),
                    OCRTextObservation(string: "$2.79 ea", confidence: 0.9)
                ],
                assisted: PriceParsingService._test_assistedExtractionResult(
                    targetLineIndexes: [0, 1, 2],
                    selectedPriceCandidateIndex: 0,
                    selectedPriceKind: .regular,
                    canonicalItemName: "Coke Zero Sugar 2 L",
                    ambiguityNotes: ["ocr repaired brand"],
                    confidenceBucket: .high
                ),
                expectedPrice: Decimal(string: "2.79"),
                expectedItemName: "Coke Zero Sugar 2 L",
                expectedSupportingLines: ["2 L", "$2.79 ea"]
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
        if let expectedSupportingLines = testCase.expectedSupportingLines {
            #expect(result.supportingLines == expectedSupportingLines, Comment(rawValue: testCase.name))
        }
    }

    @Test(.tags(.ocr, .product))
    func normalizesAssistedResponseIntoConstrainedResult() async throws {
        let response = PriceParsingService.AssistedExtractionResponse(
            targetLineIndexes: [3, 1, 3, 99, -1],
            selectedPriceCandidateIndex: 42,
            selectedPriceKind: .sale,
            canonicalItemName: "  Fresh Bananas  ",
            ambiguityNotes: [" first ", "", "second", "third", "fourth"],
            confidenceBucket: .medium
        )

        let result = PriceParsingService._test_makeAssistedExtractionResult(
            from: response,
            lineCount: 4,
            candidateCount: 2
        )

        #expect(result.targetLineIndexes == [1, 3])
        #expect(result.selectedPriceCandidateIndex == nil)
        #expect(result.selectedPriceKind == .unknown)
        #expect(result.canonicalItemName == "Fresh Bananas")
        #expect(result.ambiguityNotes == ["first", "second", "third"])
        #expect(result.confidenceBucket == .medium)
    }

    @Test(.tags(.ocr, .product))
    func assistedPromptStatesResponseContractExplicitly() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
            OCRTextObservation(string: "$3.99", confidence: 0.93),
            OCRTextObservation(string: "$2.99", confidence: 0.93)
        ])
        let ambiguity = PriceParsingService._test_analyzeAmbiguity([
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.94),
            OCRTextObservation(string: "$3.99", confidence: 0.93),
            OCRTextObservation(string: "$2.99", confidence: 0.93)
        ])

        let prompt = PriceParsingService.buildAssistedExtractionPrompt(
            snapshot: snapshot,
            ambiguity: ambiguity
        )

        #expect(prompt.contains("Response contract:"))
        #expect(prompt.contains("`selectedPriceCandidateIndex` must be an existing candidate index or `nil`"))
        #expect(prompt.contains("`targetLineIndexes` must be existing OCR line indexes only"))
        #expect(prompt.contains("Never invent missing values."))
    }

    @Test(.tags(.ocr, .product))
    func agreementAwareConfidenceRewardsHelpfulAssistAndPenalizesWeakOrNoisyAssist() async throws {
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
        let noisy = PriceParsingService._test_mergeAssistedExtraction(
            observations: observations,
            assisted: PriceParsingService._test_assistedExtractionResult(
                targetLineIndexes: [0, 2],
                selectedPriceCandidateIndex: 1,
                selectedPriceKind: .noise,
                canonicalItemName: "Fresh Bananas",
                ambiguityNotes: ["secondary price likely unrelated"],
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

        #expect((agreeing.confidence ?? 0) > (noisy.confidence ?? 0))
        #expect((noisy.confidence ?? 0) > (weak.confidence ?? 0))
    }

    @Test(.tags(.ocr, .product))
    func multiProductAssistKeepsConfidenceBelowCleanAgreement() async throws {
        let cleanAgreement = PriceParsingService._test_mergeAssistedExtraction(
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
            )
        )
        let multiProduct = PriceParsingService._test_mergeAssistedExtraction(
            observations: [
                OCRTextObservation(string: "Coke Zero", confidence: 0.93),
                OCRTextObservation(string: "$2.99", confidence: 0.91),
                OCRTextObservation(string: "Pepsi", confidence: 0.92),
                OCRTextObservation(string: "$3.49", confidence: 0.90)
            ],
            assisted: PriceParsingService._test_assistedExtractionResult(
                targetLineIndexes: [2, 3],
                selectedPriceCandidateIndex: 1,
                selectedPriceKind: .sale,
                canonicalItemName: "Pepsi",
                ambiguityNotes: ["second product cluster"],
                confidenceBucket: .high
            )
        )

        #expect((multiProduct.confidence ?? 1) < (cleanAgreement.confidence ?? 0))
        #expect((multiProduct.confidence ?? 1) <= 0.65)
    }
}
