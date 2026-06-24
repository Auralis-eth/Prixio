//
//  PriceDraftBuilder.swift
//  Prixio
//
//  App code, not model code. Maps the image-AI model result into a PriceEntryDraft
//  with consistent defaults, LLMPriceCandidate → PriceCandidate conversion (priority
//  follows list order, confidence 1.0, no source-line indexes), and the review state
//  produced by PriceExtractionValidator. Store fields are applied separately by
//  ScanViewModel.applyInferredStore after receipt classification.
//

import UIKit

enum PriceDraftBuilder {
    static func makeDraft(from result: LLMOCRResult, image: UIImage?) -> PriceEntryDraft {
        var draft = PriceEntryDraft()
        draft.ocrText = result.relevantText
        draft.priceText = result.price.map(CurrencyFormatter.shared.string) ?? ""
        let parsedUnit = PriceParsingUnitResolver().detectUnit(in: result.relevantText)
        // Recover a dropped unit, but fail closed when the model contradicts printed unit text.
        // A wrong non-nil unit would make normalized pricing materially incorrect.
        if let resultUnit = result.unit, let parsedUnit, resultUnit != parsedUnit {
            draft.selectedUnit = nil
        } else {
            draft.selectedUnit = result.unit ?? parsedUnit
        }
        draft.quantity = result.quantity
        draft.itemName = result.itemName ?? ""
        draft.brand = result.brand ?? ""
        draft.priceCandidates = result.priceCandidates.enumerated().map { index, candidate in
            PriceCandidate(
                label: candidate.label,
                value: candidate.value,
                quantity: candidate.quantity,
                priority: index,
                sourceText: candidate.sourceText,
                kind: candidate.kind,
                sourceLineIndexes: [],
                confidence: 1.0
            )
        }
        draft.review = PriceExtractionValidator.review(for: result)
        draft.confidence = nil        // no numeric OCR confidence exists in the image-AI path
        if let image { draft.imageData = image.jpegData(compressionQuality: 0.8) }
        return draft
    }
}
