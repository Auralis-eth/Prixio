//
//  PriceParsingServiceSpatialGroupingTests.swift
//  PrixioTests
//
//  Created by Codex on 8/16/25.
//

import CoreGraphics
import Foundation
import Testing
@testable import Prixio

struct PriceParsingServiceSpatialGroupingTests {
    @Test(.tags(.ocr, .product))
    func snapshotFocusesOnStrongestSpatialGroup() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            observation("Organic Bananas", confidence: 0.94, x: 0.05, y: 0.78, width: 0.28, height: 0.08),
            observation("$1.29 /lb", confidence: 0.93, x: 0.05, y: 0.67, width: 0.22, height: 0.08),
            observation("Club Size", confidence: 0.88, x: 0.06, y: 0.57, width: 0.18, height: 0.07),
            observation("Pepsi Zero", confidence: 0.92, x: 0.60, y: 0.78, width: 0.22, height: 0.08),
            observation("$3.49", confidence: 0.91, x: 0.61, y: 0.67, width: 0.15, height: 0.08)
        ])

        let supportingLines = Set(snapshot.consolidatedObservations.map(\.string))

        #expect(supportingLines.contains("Organic Bananas"))
        #expect(supportingLines.contains("$1.29 /lb"))
        #expect(snapshot.rawText.contains("Pepsi Zero") == false)
        #expect(snapshot.spatialGroups.count == 2)
    }

    @Test(.tags(.ocr, .product))
    func ambiguityStillFlagsSideBySideProductsAfterSpatialFocus() async throws {
        let report = PriceParsingService._test_analyzeAmbiguity([
            observation("Coke Zero", confidence: 0.93, x: 0.05, y: 0.78, width: 0.20, height: 0.08),
            observation("$2.99", confidence: 0.91, x: 0.06, y: 0.67, width: 0.15, height: 0.08),
            observation("Pepsi", confidence: 0.92, x: 0.60, y: 0.78, width: 0.18, height: 0.08),
            observation("$3.49", confidence: 0.90, x: 0.61, y: 0.67, width: 0.15, height: 0.08)
        ])

        #expect(report.weaknesses.contains(.possibleMultiProductScan))
        #expect(report.shouldUseFoundationModel)
    }

    @Test(.tags(.ocr, .product))
    func sparseFallbackKeepsImpliedPriceWhenNoiseFilteringDropsIt() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            observation("Fresh Basil", confidence: 0.92, x: 0.08, y: 0.76, width: 0.26, height: 0.08),
            observation("399", confidence: 0.58, x: 0.09, y: 0.66, width: 0.11, height: 0.07)
        ])

        #expect(snapshot.cleanedObservations.map(\.string).contains("399"))
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "3.99"))
        #expect(snapshot.lines.contains("Fresh Basil"))
    }

    @Test(.tags(.ocr, .product))
    func sparseFallbackPreservesDescriptionAndPriceEvidence() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            observation("Organic Avocado", confidence: 0.94, x: 0.08, y: 0.77, width: 0.30, height: 0.08),
            observation("249", confidence: 0.61, x: 0.09, y: 0.67, width: 0.10, height: 0.07)
        ])

        let supportingLines = Set(snapshot.consolidatedObservations.map(\.string))

        #expect(supportingLines.contains("Organic Avocado"))
        #expect(supportingLines.contains("249"))
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "2.49"))
    }

    @Test(.tags(.ocr, .product))
    func healthyFocusedGroupDoesNotFallbackToNeighboringProduct() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            observation("Organic Bananas", confidence: 0.94, x: 0.05, y: 0.78, width: 0.28, height: 0.08),
            observation("$1.29 /lb", confidence: 0.93, x: 0.05, y: 0.67, width: 0.22, height: 0.08),
            observation("Pepsi Zero", confidence: 0.92, x: 0.60, y: 0.78, width: 0.22, height: 0.08),
            observation("$3.49", confidence: 0.91, x: 0.61, y: 0.67, width: 0.15, height: 0.08)
        ])

        let supportingLines = Set(snapshot.consolidatedObservations.map(\.string))

        #expect(supportingLines.contains("Organic Bananas"))
        #expect(supportingLines.contains("$1.29 /lb"))
        #expect(supportingLines.contains("Pepsi Zero") == false)
        #expect(snapshot.priceCandidates.first?.value == Decimal(string: "1.29"))
    }

    private func observation(
        _ string: String,
        confidence: Float,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> OCRTextObservation {
        OCRTextObservation(
            string: string,
            confidence: confidence,
            boundingBox: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}
