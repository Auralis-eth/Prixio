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
}
