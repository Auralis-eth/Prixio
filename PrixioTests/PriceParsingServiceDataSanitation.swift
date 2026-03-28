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
}

struct PriceParsingServiceDataSanitation {
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
        #expect(snapshot.resolvedQuantity == nil)
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
}
