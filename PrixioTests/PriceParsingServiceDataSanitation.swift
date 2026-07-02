//
//  PriceParsingServiceDataSanitation.swift
//  PrixioTests
//
//  Created by Daniel Bell on 3/7/26.
//
//  After the OCR → image-AI migration the snapshot/normalization pipeline is gone.
//  What remains here are the pure PriceCandidateScorer tests, retyped onto
//  `PlainTextObservation` (the surviving scorers read only string/confidence).
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
    @Tag static var simulatorCrash: Self
}

@MainActor
struct PriceParsingServiceScorerTests {
    @Test(.tags(.ocr, .product))
    func typedPriceKindsSeparateRegularFromSaveAndDeposit() async throws {
        let scorer = PriceCandidateScorer()
        let observations: [any TextObservation] = [
            PlainTextObservation(string: "Regular 6.49", confidence: 0.88),
            PlainTextObservation(string: "- SAVE", confidence: 0.84),
            PlainTextObservation(string: "$5.00 ea", confidence: 0.89),
            PlainTextObservation(string: "plus dep", confidence: 0.83),
            PlainTextObservation(string: "$0.10 deposit", confidence: 0.81)
        ]
        let candidates = scorer.scorePriceCandidates(
            scorer.extractPriceCandidates(from: observations),
            in: observations
        )

        #expect(candidates.contains(where: { $0.kind == .regular && $0.value == Decimal(string: "6.49") }))
        #expect(candidates.contains(where: { $0.kind == .save && $0.value == Decimal(string: "5") }))
        #expect(candidates.contains(where: { $0.kind == .deposit && $0.value == Decimal(string: "0.10") }))
    }

    @Test(.tags(.ocr, .product))
    func standaloneShelfPriceIsTypedAsShelfCandidate() async throws {
        let scorer = PriceCandidateScorer()
        let observations: [any TextObservation] = [
            PlainTextObservation(string: "Cadbury Chocolate Mini Eggs", confidence: 0.91),
            PlainTextObservation(string: "1799", confidence: 0.93)
        ]
        let candidates = scorer.scorePriceCandidates(
            scorer.extractPriceCandidates(from: observations),
            in: observations
        )

        #expect(candidates.first?.kind == .shelf)
        #expect(candidates.first?.value == Decimal(string: "17.99"))
    }

    @Test(.tags(.ocr, .product))
    func impliedCurrencyFilteringRejectsExplicitSizeContext() async throws {
        let candidates = PriceCandidateScorer().extractInlinePriceCandidates(
            from: PlainTextObservation(string: "Eggs Easter 875 g", confidence: 1.0)
        )

        #expect(candidates.isEmpty)
    }

    @Test(.tags(.ocr, .product))
    func saveAdjacentPenaltyAppliesOnlyWhenStandaloneSaveMarkerIsNearby() async throws {
        let scorer = PriceCandidateScorer()
        let candidate = PriceCandidate(
            label: "$5.00",
            value: Decimal(string: "5")!,
            quantity: nil,
            priority: 3,
            sourceText: "$5.00 ea",
            kind: .unit,
            sourceLineIndexes: [1],
            confidence: 1.0
        )
        let penalty = scorer.nearbySavePenalty(
            candidate: candidate,
            sourceLineIndexes: [1],
            observations: [
                PlainTextObservation(string: "- SAVE", confidence: 1.0),
                PlainTextObservation(string: "$5.00 ea", confidence: 1.0),
                PlainTextObservation(string: "1799", confidence: 1.0)
            ]
        )
        let noPenalty = scorer.nearbySavePenalty(
            candidate: candidate,
            sourceLineIndexes: [1],
            observations: [
                PlainTextObservation(string: "Organic Raspberries", confidence: 1.0),
                PlainTextObservation(string: "$5.00 ea", confidence: 1.0),
                PlainTextObservation(string: "Member Price", confidence: 1.0)
            ]
        )

        #expect(penalty > 0)
        #expect(noPenalty == 0)
    }
}
