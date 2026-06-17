import Foundation
import Testing
@testable import Prixio

@MainActor
struct PriceExtractionValidatorTests {
    @Test(.tags(.ocr, .product, .shipGate))
    func cleanSingleCandidateResultIsClean() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Fresh Bananas\n$1.29 /lb",
            priceCandidates: [.fixture(value: Decimal(string: "1.29")!, kind: .unit, sourceText: "$1.29 /lb")],
            itemName: "Fresh Bananas",
            price: Decimal(string: "1.29"),
            unit: .lb
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.isEmpty)
        #expect(review.state == .clean)
        #expect(review.usedFoundationModel)   // metadata only; does not force review
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func cleanMultiCandidateResultStaysClean() async throws {
        // Enumerating sale + regular + per-unit candidates is the NORMAL clean case —
        // candidate count alone must not be treated as competition (§7.1 fix).
        let result = LLMOCRResult.fixture(
            relevantText: "Honeycrisp Apples\nSale $1.99 /lb\nRegular $2.49 /lb\n$4.39 /kg",
            priceCandidates: [
                .fixture(label: "Sale", value: Decimal(string: "1.99")!, kind: .sale, sourceText: "Sale $1.99 /lb"),
                .fixture(label: "Regular", value: Decimal(string: "2.49")!, kind: .regular, sourceText: "Regular $2.49 /lb"),
                .fixture(label: "per kg", value: Decimal(string: "4.39")!, kind: .unit, sourceText: "$4.39 /kg")
            ],
            itemName: "Honeycrisp Apples",
            price: Decimal(string: "1.99"),
            unit: .lb
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.isEmpty)
        #expect(review.state == .clean)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func missingPriceRequiresReview() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Fresh Bananas",
            itemName: "Fresh Bananas",
            price: nil,
            unit: .lb
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.noPriceCandidates))
        #expect(review.state == .reviewRequired)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func modelReportedCompetingPricesRequireReview() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Coke Zero $2.99\nPepsi $3.49",
            priceCandidates: [
                .fixture(value: Decimal(string: "2.99")!, sourceText: "Coke Zero $2.99"),
                .fixture(value: Decimal(string: "3.49")!, sourceText: "Pepsi $3.49")
            ],
            itemName: "Coke Zero",
            price: Decimal(string: "2.99"),
            unit: .each,
            issues: [.priceOwnershipUncertain]
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.multipleCompetingPrices))
        #expect(review.state == .reviewRequired)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func ungroundedPrimaryPriceRequiresReview() async throws {
        // result.price appears in neither the model candidates nor the scorer re-read.
        let result = LLMOCRResult.fixture(
            relevantText: "Apples\n$3.99 each",
            priceCandidates: [.fixture(value: Decimal(string: "3.99")!, sourceText: "$3.99 each")],
            itemName: "Apples",
            price: Decimal(string: "9.49"),
            unit: .each
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.multipleCompetingPrices))
        #expect(review.state == .reviewRequired)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func modelUnitConflictingWithTranscriptionRecommendsReview() async throws {
        // Model returned `.each`, but the transcription clearly prices per lb. A wrong non-nil
        // unit would otherwise save materially wrong normalized pricing as "clean".
        let result = LLMOCRResult.fixture(
            relevantText: "Gala Apples\n$1.29 /lb",
            priceCandidates: [.fixture(value: Decimal(string: "1.29")!, kind: .unit, sourceText: "$1.29 /lb")],
            itemName: "Gala Apples",
            price: Decimal(string: "1.29"),
            unit: .each
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.missingUnit))
        #expect(review.state == .reviewRecommended)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func hallucinatedItemNameRecommendsReview() async throws {
        // A non-empty name that appears nowhere in the model's own transcription must not pass clean.
        let result = LLMOCRResult.fixture(
            relevantText: "Gala Apples\n$1.29 /lb",
            priceCandidates: [.fixture(value: Decimal(string: "1.29")!, kind: .unit, sourceText: "$1.29 /lb")],
            itemName: "Imported Swiss Cheese",
            price: Decimal(string: "1.29"),
            unit: .lb
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.missingItemName))
        #expect(review.state == .reviewRecommended)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func multiTagSceneRequiresReviewWithoutModelIssue() async throws {
        // The model reported no issue, but a multi-tag scene carries price/name ownership risk.
        let result = LLMOCRResult.fixture(
            relevantText: "Gala Apples\n$1.29 /lb",
            scene: .multiTag,
            priceCandidates: [.fixture(value: Decimal(string: "1.29")!, kind: .unit, sourceText: "$1.29 /lb")],
            itemName: "Gala Apples",
            price: Decimal(string: "1.29"),
            unit: .lb
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.possibleMultiProductScan))
        #expect(review.state == .reviewRequired)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func unclearSceneRecommendsReviewWithoutModelIssue() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Gala Apples\n$1.29 /lb",
            scene: .unclear,
            priceCandidates: [.fixture(value: Decimal(string: "1.29")!, kind: .unit, sourceText: "$1.29 /lb")],
            itemName: "Gala Apples",
            price: Decimal(string: "1.29"),
            unit: .lb
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.lowConfidence))
        #expect(review.state == .reviewRecommended)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func parserRecoveredUnitClearsMissingUnit() async throws {
        // Model dropped the unit, but a unit token is present in its own transcription.
        let result = LLMOCRResult.fixture(
            relevantText: "Fresh Bananas\n$1.29 /lb",
            priceCandidates: [.fixture(value: Decimal(string: "1.29")!, sourceText: "$1.29 /lb")],
            itemName: "Fresh Bananas",
            price: Decimal(string: "1.29"),
            unit: nil
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.missingUnit) == false)
        #expect(review.state == .clean)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func receiptSceneRequiresReview() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Subtotal 12.99\nTax 0.65\nTotal 13.64",
            scene: .receiptLike,
            priceCandidates: [.fixture(value: Decimal(string: "13.64")!, sourceText: "Total 13.64")],
            itemName: "Receipt total",
            price: Decimal(string: "13.64"),
            unit: .each
        )

        let review = PriceExtractionValidator.review(for: result)

        #expect(review.issues.contains(.receiptCapture))
        #expect(review.state == .reviewRequired)
    }
}
