//
//  PriceParsingServiceDataSanitation.swift
//  PrixioTests
//
//  Created by Daniel Bell on 3/7/26.
//

import Foundation
import Testing
@testable import Prixio

extension Tag {
    @Tag static var ocr: Self
    @Tag static var product: Self
    @Tag static var shipGate: Self
    @Tag static var evaluation: Self
    @Tag static var realWorldOCR: Self
}

@MainActor
struct PriceParsingServiceDataSanitation {
    @Test(.tags(.ocr, .product))
    func compactPriceObservationKeepsAlternateHypotheses() async throws {
        let observation = OCRTextObservation(
            string: "299",
            confidence: 0.81,
            alternateStrings: ["2.99", "$2.99", "299"]
        )

        #expect(observation.alternateStrings == ["2.99", "$2.99"])
        #expect(observation.allCandidateStrings == ["299", "2.99", "$2.99"])
        #expect(observation.likelyCompactPriceAlternates == ["299"])
    }

    @Test(.tags(.ocr, .product))
    func nonPriceObservationDoesNotNeedAlternateCompactPriceCandidates() async throws {
        let observation = OCRTextObservation(
            string: "Fresh Bananas",
            confidence: 0.93,
            alternateStrings: ["Fresh Bononos"]
        )

        #expect(observation.allCandidateStrings == ["Fresh Bananas", "Fresh Bononos"])
        #expect(observation.likelyCompactPriceAlternates.isEmpty)
    }

    @Test(.tags(.ocr, .product))
    func normalizesCommaDecimalPriceLineIntoCanonicalCurrency() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Fresh Bananas", confidence: 0.93),
            OCRTextObservation(string: "1,29/lb", confidence: 0.88)
        ])

        #expect(snapshot.normalizedObservations.map(\.string).contains("$1.29 /lb"))
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "1.29"))
    }

    @Test(.tags(.ocr, .product))
    func normalizesSplitPriceTokensBeforeExtraction() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Organic Avocado", confidence: 0.94),
            OCRTextObservation(string: "1 29 /lb", confidence: 0.72)
        ])

        #expect(snapshot.normalizedObservations.map(\.string).contains("$1.29 /lb"))
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "1.29"))
    }

    @Test(.tags(.ocr, .product))
    func normalizesMergedPriceAndEachTokenIntoParseableLine() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Blueberries", confidence: 0.95),
            OCRTextObservation(string: "S299ea", confidence: 0.69)
        ])

        #expect(snapshot.normalizedObservations.map(\.string).contains("$2.99 ea"))
        #expect(snapshot.detectedUnit == .each)
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "2.99"))
    }

    @Test(.tags(.ocr, .product))
    func mixedUnitLabelPrefersFirstDirectRateUnit() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Fresh Salmon", confidence: 0.94),
            OCRTextObservation(string: "$1.29 /lb $2.84 /kg", confidence: 0.89)
        ])

        #expect(snapshot.detectedUnit == .lb)
        #expect(snapshot.resolvedQuantity == Decimal(1))
    }

    @Test(.tags(.ocr, .product))
    func splitPricePerPhraseAcrossLinesStillDetectsUnit() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Price", confidence: 0.81),
            OCRTextObservation(string: "per", confidence: 0.78),
            OCRTextObservation(string: "lb", confidence: 0.82),
            OCRTextObservation(string: "$1.29", confidence: 0.92)
        ])

        #expect(snapshot.detectedUnit == .lb)
        #expect(snapshot.resolvedQuantity == Decimal(1))
    }

    @Test(.tags(.ocr, .product))
    func multiPackSignalDefaultsToEachInsteadOfLiter() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Sparkling Water", confidence: 0.95),
            OCRTextObservation(string: "$5.99", confidence: 0.91),
            OCRTextObservation(string: "12 x 355 mL", confidence: 0.88)
        ])

        #expect(snapshot.detectedUnit == .each)
        #expect(snapshot.resolvedQuantity == Decimal(12))
    }

    @Test(.tags(.ocr, .product))
    func countPackSignalDefaultsToEach() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Granola Bars", confidence: 0.94),
            OCRTextObservation(string: "$4.49", confidence: 0.89),
            OCRTextObservation(string: "6 pk", confidence: 0.83)
        ])

        #expect(snapshot.detectedUnit == .each)
    }

    @Test(.tags(.ocr, .product))
    func itemNameKeepsBrandAndSizeMarkersWhenTheyShareOneLine() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Coca Cola Zero Sugar 2L", confidence: 0.95),
            OCRTextObservation(string: "$2.99", confidence: 0.91)
        ])

        #expect(snapshot.itemNameHint == "Coca Cola Zero Sugar 2 L")
    }

    @Test(.tags(.ocr, .product))
    func itemNamePrefersBrandedLineOverPromoOnlyLine() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Member Deal", confidence: 0.84),
            OCRTextObservation(string: "7UP Zero Sugar 2L", confidence: 0.93),
            OCRTextObservation(string: "$2.49", confidence: 0.90)
        ])

        #expect(snapshot.itemNameHint == "7UP Zero Sugar 2 L")
    }

    @Test(.tags(.ocr, .product))
    func itemNameDoesNotCollapseToShortUnitLikeLine() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Organic Strawberries 454g", confidence: 0.94),
            OCRTextObservation(string: "per lb", confidence: 0.78),
            OCRTextObservation(string: "$4.99", confidence: 0.89)
        ])

        #expect(snapshot.itemNameHint == "Organic Strawberries 454g")
    }

    @Test(.tags(.ocr, .product))
    func multiBuyCandidateKeepsItsQuantity() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Tortilla Chips", confidence: 0.94),
            OCRTextObservation(string: "2/$5", confidence: 0.91)
        ])

        #expect(snapshot.priceCandidates.first?.quantity == Decimal(2))
        #expect(snapshot.resolvedQuantity == Decimal(2))
    }

    @Test(.tags(.ocr, .product))
    func bogoPromoInfersQuantityFromNearbyLine() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Potato Chips", confidence: 0.93),
            OCRTextObservation(string: "Buy One Get One Free", confidence: 0.82),
            OCRTextObservation(string: "$5.99", confidence: 0.90)
        ])

        #expect(snapshot.resolvedQuantity == Decimal(2))
    }

    @Test(.tags(.ocr, .product))
    func multiPackNotationInfersEachQuantity() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Sparkling Water", confidence: 0.95),
            OCRTextObservation(string: "12 x 355 mL", confidence: 0.88),
            OCRTextObservation(string: "$5.99", confidence: 0.91)
        ])

        #expect(snapshot.detectedUnit == .each)
        #expect(snapshot.resolvedQuantity == Decimal(12))
    }

    @Test(.tags(.ocr, .product))
    func countPackNotationInfersEachQuantity() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Granola Bars", confidence: 0.94),
            OCRTextObservation(string: "6 pk", confidence: 0.83),
            OCRTextObservation(string: "$4.49", confidence: 0.89)
        ])

        #expect(snapshot.detectedUnit == .each)
        #expect(snapshot.resolvedQuantity == Decimal(6))
    }

    @Test(.tags(.ocr, .product, .shipGate, .evaluation, .realWorldOCR))
    func memberPromoTagPreservesMultiBuyPriceAndCanonicalProductLine() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "MBR PRICE", confidence: 0.79),
            OCRTextObservation(string: "Dr Pepper Zero 12 PK", confidence: 0.88),
            OCRTextObservation(string: "2/$11", confidence: 0.86),
            OCRTextObservation(string: "Regular 6.49", confidence: 0.82),
            OCRTextObservation(string: "plus dep", confidence: 0.75)
        ])

        #expect(snapshot.itemNameHint == "Dr Pepper Zero 12 PK")
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "11"))
        #expect(snapshot.priceCandidates.first?.quantity == Decimal(2))
        #expect(snapshot.resolvedQuantity == Decimal(2))
        #expect(snapshot.detectedUnit == .each)
    }

    @Test(.tags(.ocr, .product, .shipGate, .evaluation, .realWorldOCR))
    func depositHeavyBeverageTagKeepsPrimaryShelfPrice() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "Sparkling Water 12 PK", confidence: 0.93),
            OCRTextObservation(string: "$5.99", confidence: 0.91),
            OCRTextObservation(string: "$1.20 dep", confidence: 0.84),
            OCRTextObservation(string: "12 x 355 mL", confidence: 0.88)
        ])

        #expect(snapshot.itemNameHint == "Sparkling Water 12 PK")
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "5.99"))
        #expect(snapshot.detectedUnit == .each)
        #expect(snapshot.resolvedQuantity == Decimal(12))
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func noisyBrandedShelfTagRepairsProductNameWithoutDroppingPrice() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "C0KE ZER0 SGR", confidence: 0.74),
            OCRTextObservation(string: "2 L", confidence: 0.79),
            OCRTextObservation(string: "$2.79 ea", confidence: 0.90)
        ])

        #expect(snapshot.itemNameHint == "C0KE ZER0 SGR")
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "2.79"))
        #expect(snapshot.detectedUnit == .each)
    }

    @Test(.tags(.ocr, .product, .shipGate, .evaluation, .realWorldOCR))
    func flyerStyleNoiseDoesNotDisplaceActualShelfTagEvidence() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "WEEKLY SPECIAL", confidence: 0.73),
            OCRTextObservation(string: "Organic Raspberries", confidence: 0.92),
            OCRTextObservation(string: "$3.99 ea", confidence: 0.90),
            OCRTextObservation(string: "SAVE 2.00", confidence: 0.78),
            OCRTextObservation(string: "Valid Fri Sat Sun", confidence: 0.76)
        ])

        #expect(snapshot.itemNameHint == "Organic Raspberries")
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "3.99"))
        #expect(snapshot.detectedUnit == .each)
    }

    @Test(.tags(.ocr, .product, .shipGate, .evaluation, .realWorldOCR))
    func stackedSaleTagKeepsWinningSalePriceOverFallbackAndSaveBanner() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "BUY 2 SAVE 1.00", confidence: 0.76),
            OCRTextObservation(string: "Honeycrisp Apples", confidence: 0.93),
            OCRTextObservation(string: "Sale $1.99 /lb", confidence: 0.91),
            OCRTextObservation(string: "Regular $2.49 /lb", confidence: 0.88),
            OCRTextObservation(string: "Valid thru Tuesday", confidence: 0.74)
        ])

        #expect(snapshot.itemNameHint == "Honeycrisp Apples")
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "1.99"))
        #expect(snapshot.detectedUnit == .lb)
        #expect(snapshot.resolvedQuantity == Decimal(1))
    }

    @Test(.tags(.ocr, .product))
    func removeObviousNoisePreservesStandaloneImpliedPriceInShelfTagContext() async throws {
        let cleaned = PriceParsingService.removeObviousNoise(from: [
            OCRTextObservation(string: "1799", confidence: 1.0),
            OCRTextObservation(string: "$5.00 ea", confidence: 1.0),
            OCRTextObservation(string: "Cadbury Chocolate Mini", confidence: 1.0),
            OCRTextObservation(string: "Eggs Easter 875 g", confidence: 1.0)
        ])

        #expect(cleaned.map(\.string).contains("1799"))
    }

    @Test(.tags(.ocr, .product))
    func impliedCurrencyFilteringRejectsExplicitSizeContext() async throws {
        let candidates = PriceCandidateScorer().extractInlinePriceCandidates(
            from: OCRTextObservation(string: "Eggs Easter 875 g", confidence: 1.0)
        )

        #expect(candidates.isEmpty)
    }

    @Test(.tags(.ocr, .product))
    func saveAdjacentPenaltyAppliesOnlyWhenStandaloneSaveMarkerIsNearby() async throws {
        let scorer = PriceCandidateScorer()
        let penalty = scorer.nearbySavePenalty(
            candidate: PriceCandidate(
                label: "$5.00",
                value: Decimal(string: "5")!,
                quantity: nil,
                priority: 3,
                sourceText: "$5.00 ea",
                confidence: 1.0
            ),
            sourceLineIndexes: [1],
            observations: [
                OCRTextObservation(string: "- SAVE", confidence: 1.0),
                OCRTextObservation(string: "$5.00 ea", confidence: 1.0),
                OCRTextObservation(string: "1799", confidence: 1.0)
            ]
        )
        let noPenalty = scorer.nearbySavePenalty(
            candidate: PriceCandidate(
                label: "$5.00",
                value: Decimal(string: "5")!,
                quantity: nil,
                priority: 3,
                sourceText: "$5.00 ea",
                confidence: 1.0
            ),
            sourceLineIndexes: [1],
            observations: [
                OCRTextObservation(string: "Organic Raspberries", confidence: 1.0),
                OCRTextObservation(string: "$5.00 ea", confidence: 1.0),
                OCRTextObservation(string: "Member Price", confidence: 1.0)
            ]
        )

        #expect(penalty > 0)
        #expect(noPenalty == 0)
    }

    @Test(.tags(.ocr, .product))
    func saveAdjacentPenaltyDoesNotDisplaceNormalEachPriceWithoutSaveBanner() async throws {
        let observations = [
            OCRTextObservation(string: "Organic Raspberries", confidence: 0.93),
            OCRTextObservation(string: "$5.00 ea", confidence: 0.93),
            OCRTextObservation(string: "Member Price", confidence: 0.79)
        ]
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot(observations)

        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "5"))
    }

    @Test(.tags(.ocr, .product))
    func itemNameIgnoresDescriptiveProduceCardCopyBelowTheTitle() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            OCRTextObservation(string: "MINI CUCUMBER", confidence: 1.0),
            OCRTextObservation(string: "Perfect for snacking", confidence: 1.0),
            OCRTextObservation(string: "High water content helps to keep you", confidence: 1.0),
            OCRTextObservation(string: "hydrated", confidence: 1.0),
            OCRTextObservation(string: "$4.00", confidence: 1.0)
        ])

        #expect(snapshot.itemNameHint == "MINI CUCUMBER")
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "4"))
    }
}
