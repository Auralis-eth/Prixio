import Foundation
@testable import Prixio

/// Source-agnostic text fixtures (post OCR → image-AI migration). Bounding boxes
/// are gone; the surviving scorers/resolvers only read `.string` / `.confidence`.
enum CapturedOCRFixtures {
    static func observations(_ lines: [(String, Float)]) -> [PlainTextObservation] {
        lines.map { PlainTextObservation(string: $0.0, confidence: $0.1) }
    }
}

// MARK: - LLMOCRResult fixtures (replace OCR fixtures for result-level tests)

extension LLMOCRResult {
    static func fixture(
        relevantText: String = "",
        scene: LLMSceneKind = .singleTag,
        priceCandidates: [LLMPriceCandidate] = [],
        itemName: String? = nil,
        brand: String? = nil,
        price: Decimal? = nil,
        unit: UnitType? = nil,
        quantity: Decimal? = nil,
        saleEndsOn: String? = nil,
        issues: [LLMExtractionIssue] = []
    ) -> LLMOCRResult {
        LLMOCRResult(
            relevantText: relevantText,
            scene: scene,
            priceCandidates: priceCandidates,
            itemName: itemName,
            brand: brand,
            price: price,
            unit: unit,
            quantity: quantity,
            saleEndsOn: saleEndsOn,
            issues: issues
        )
    }
}

extension LLMPriceCandidate {
    static func fixture(
        label: String = "",
        value: Decimal,
        quantity: Decimal? = nil,
        kind: PriceKind = .shelf,
        sourceText: String = ""
    ) -> LLMPriceCandidate {
        LLMPriceCandidate(
            label: label,
            value: value,
            quantity: quantity,
            kind: kind,
            sourceText: sourceText.isEmpty ? label : sourceText
        )
    }
}
