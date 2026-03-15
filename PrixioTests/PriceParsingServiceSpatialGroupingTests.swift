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
