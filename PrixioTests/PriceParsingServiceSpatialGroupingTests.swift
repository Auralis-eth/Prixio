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

@MainActor
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
        #expect(snapshot.evidenceClusters.count == 2)
        #expect(snapshot.winningClusterIndex == 0)
        #expect(snapshot.evidenceClusters[safe: 0]?.role == .primaryProduct)
        #expect(snapshot.evidenceClusters[safe: 1]?.role == .secondaryProduct)
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
        #expect(snapshot.evidenceClusters[safe: snapshot.winningClusterIndex ?? -1]?.itemNameHint == "Organic Bananas")
    }

    @Test(.tags(.ocr, .product))
    func sideBySideMemberTagsStillReadAsCompetingProducts() async throws {
        let report = PriceParsingService._test_analyzeAmbiguity([
            observation("MBR PRICE", confidence: 0.80, x: 0.05, y: 0.82, width: 0.16, height: 0.06),
            observation("Coke Zero 12 PK", confidence: 0.93, x: 0.05, y: 0.74, width: 0.26, height: 0.08),
            observation("2/$11", confidence: 0.89, x: 0.06, y: 0.64, width: 0.14, height: 0.08),
            observation("MBR PRICE", confidence: 0.79, x: 0.58, y: 0.82, width: 0.16, height: 0.06),
            observation("Pepsi Zero 12 PK", confidence: 0.92, x: 0.58, y: 0.74, width: 0.24, height: 0.08),
            observation("2/$12", confidence: 0.88, x: 0.60, y: 0.64, width: 0.14, height: 0.08)
        ])

        #expect(report.weaknesses.contains(.possibleMultiProductScan))
        #expect(report.shouldUseFoundationModel)
    }

    @Test(.tags(.ocr, .product))
    func promoOnlyClusterIsNotChosenAsWinningProductCluster() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            observation("SAVE THIS WEEK", confidence: 0.90, x: 0.05, y: 0.86, width: 0.24, height: 0.06),
            observation("Valid Fri Sat Sun", confidence: 0.88, x: 0.05, y: 0.79, width: 0.30, height: 0.06),
            observation("Organic Bananas", confidence: 0.95, x: 0.48, y: 0.78, width: 0.26, height: 0.08),
            observation("$1.29 /lb", confidence: 0.93, x: 0.49, y: 0.67, width: 0.18, height: 0.08)
        ])

        #expect(snapshot.evidenceClusters.count == 2)
        #expect(snapshot.evidenceClusters.contains(where: {
            $0.role != .primaryProduct && $0.itemNameHint == nil && $0.priceCandidates.isEmpty
        }))
        #expect(snapshot.winningClusterIndex != nil)
        #expect(snapshot.evidenceClusters[safe: snapshot.winningClusterIndex ?? -1]?.itemNameHint == "Organic Bananas")
        #expect(snapshot.evidenceClusters[safe: snapshot.winningClusterIndex ?? -1]?.role == .primaryProduct)
    }

    @Test(.tags(.ocr, .product))
    func finalItemNamePrefersWinningClusterOverNeighboringProductText() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            observation("Organic Bananas", confidence: 0.95, x: 0.05, y: 0.80, width: 0.28, height: 0.08),
            observation("$1.29 /lb", confidence: 0.94, x: 0.06, y: 0.69, width: 0.20, height: 0.08),
            observation("Pepsi Zero 12 PK", confidence: 0.93, x: 0.60, y: 0.80, width: 0.26, height: 0.08),
            observation("$3.49", confidence: 0.92, x: 0.61, y: 0.69, width: 0.14, height: 0.08)
        ])

        #expect(snapshot.itemNameHint == "Organic Bananas")
        #expect(snapshot.evidenceClusters[safe: snapshot.winningClusterIndex ?? -1]?.itemNameHint == "Organic Bananas")
        #expect(snapshot.evidenceClusters[safe: 1]?.itemNameHint == "Pepsi Zero 12 PK")
    }

    @Test(.tags(.ocr, .product))
    func finalItemNameIgnoresPromoCopyWhenWinningClusterHasRealProductName() async throws {
        let snapshot = PriceParsingService._test_buildHeuristicSnapshot([
            observation("SAVE THIS WEEK", confidence: 0.90, x: 0.05, y: 0.84, width: 0.24, height: 0.06),
            observation("Valid Fri Sat Sun", confidence: 0.88, x: 0.05, y: 0.77, width: 0.30, height: 0.06),
            observation("Fresh Blueberries", confidence: 0.95, x: 0.48, y: 0.80, width: 0.26, height: 0.08),
            observation("Sale $3.99 ea", confidence: 0.93, x: 0.49, y: 0.69, width: 0.18, height: 0.08)
        ])

        #expect(snapshot.itemNameHint == "Fresh Blueberries")
        #expect(snapshot.evidenceClusters.contains(where: {
            $0.role != .primaryProduct && $0.itemNameHint == nil && $0.priceCandidates.isEmpty
        }))
        #expect(snapshot.evidenceClusters[safe: snapshot.winningClusterIndex ?? -1]?.itemNameHint == "Fresh Blueberries")
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
