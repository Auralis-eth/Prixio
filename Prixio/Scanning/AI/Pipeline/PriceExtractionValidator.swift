//
//  PriceExtractionValidator.swift
//  Prixio
//
//  Defense-in-depth: the image-AI model proposes structured fields, and this step
//  re-reads the model's OWN structured output (relevantText + priceCandidates) to
//  check it for internal consistency, raising the review state when a field is
//  unsupported by the model's own transcription. It never re-examines the photo —
//  it catches structure/transcription mismatches, not transcription-vs-photo errors.
//
//  Critical: candidate multiplicity is NOT competition. LLMOCRResult is contracted
//  to enumerate every distinct price (sale, regular, member, per-unit, deposit,
//  multi-buy) as a separate candidate, so 2–5 candidates is the normal clean case.
//  Genuine competition is routed to review only via the model's own
//  .multipleCompetingPrices / .priceOwnershipUncertain issues (see mapIssue).
//

import Foundation

enum PriceExtractionValidator {
    static func review(for result: LLMOCRResult) -> OCRReview {
        var issues = result.issues.compactMap(Self.mapIssue)

        // 1. Missing-field checks on the model's own output.
        if result.price == nil { issues.append(.noPriceCandidates) }
        if result.unit == nil { issues.append(.missingUnit) }
        if (result.itemName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingItemName)
        }
        // NOTE: do NOT flag on priceCandidates.count > 1. Multiple candidates is the expected
        // clean case (sale + regular + unit + deposit). Genuine competition arrives only via the
        // model's own .multipleCompetingPrices / .priceOwnershipUncertain issues, mapped above.

        // 2. Scene-level risk. A model can report a clean field set on signage that is inherently
        //    ambiguous, so treat the risky scenes as review signals in their own right rather than
        //    trusting the model to also emit a matching issue. A multi-tag scene carries price/name
        //    ownership risk → require review; an unclear scene → recommend it.
        switch result.scene {
        case .multiTag:
            issues.append(.possibleMultiProductScan)
        case .unclear:
            issues.append(.lowConfidence)
        case .receiptLike:
            issues.append(.receiptCapture)
        case .singleTag, .promoCard, .produceSign:
            break
        }

        // 3. Deterministic cross-check: is the model's chosen PRIMARY price grounded in the
        //    evidence? Candidates are an evidence list, so multiplicity is not a signal; the
        //    risk we guard against is a primary price that appears in neither the model's own
        //    candidates nor the independent scorer re-read.
        let observations = Self.observations(from: result)
        let scorer = PriceCandidateScorer()
        let rescored = scorer.scorePriceCandidates(
            scorer.extractPriceCandidates(from: observations), in: observations
        )
        if let modelPrice = result.price {
            let grounded = result.priceCandidates.contains { $0.value == modelPrice }
                || rescored.contains { $0.value == modelPrice }
            if !grounded { issues.append(.multipleCompetingPrices) }  // primary not in own evidence
        }

        // 4. Unit cross-check against the transcription. When the model dropped the unit but the
        //    parser recovers one, clear the missing-unit flag. When the model chose a unit that the
        //    transcription contradicts, the normalized per-unit price could be materially wrong
        //    (e.g. text says "/lb" but the model returned `.each`) → recommend review.
        let parsedUnit = PriceParsingUnitResolver().detectUnit(in: result.relevantText)
        if result.unit == nil {
            if parsedUnit != nil {
                issues.removeAll { $0 == .missingUnit }
            }
        } else if let parsedUnit, parsedUnit != result.unit {
            issues.append(.missingUnit)
        }

        // 5. Item-name cross-check: a non-empty name that is ungrounded in the model's own
        //    transcription (hallucinated, or lifted from a neighbouring tag) must not pass as clean.
        if let modelName = result.itemName,
           !modelName.trimmingCharacters(in: .whitespaces).isEmpty,
           !Self.itemNameIsGrounded(modelName, in: result.relevantText) {
            issues.append(.missingItemName)
        }

        return OCRReview(
            issues: Array(Set(issues)),
            ambiguityNotes: [],                           // thread model notes here if added to LLMOCRResult
            usedFoundationModel: true
        )
    }

    /// Build source-agnostic observations from the model output for the re-read.
    /// Confidence is 1.0 — the model asserts its transcription; there is no per-line OCR score.
    static func observations(from result: LLMOCRResult) -> [PlainTextObservation] {
        let lines = result.relevantText
            .split(whereSeparator: \.isNewline)
            .map { PlainTextObservation(string: String($0), confidence: 1.0) }
        let candidateLines = result.priceCandidates
            .map { PlainTextObservation(string: $0.sourceText, confidence: 1.0) }
        return lines + candidateLines
    }

    /// A model item name is grounded when at least one of its meaningful word tokens appears in
    /// the model's own transcription. Tokens shorter than three characters are ignored so a bare
    /// brand abbreviation (e.g. "PC") does not trip the check; a name with only such tokens is
    /// treated as grounded rather than flagged.
    static func itemNameIsGrounded(_ name: String, in transcription: String) -> Bool {
        let transcriptionWords = Set(transcription.normalizedWords())
        let nameWords = name.normalizedWords().filter { $0.count >= 3 }
        guard !nameWords.isEmpty else { return true }
        return nameWords.contains { transcriptionWords.contains($0) }
    }

    /// LLMExtractionIssue → OCRReviewIssue. Map only what has a domain equivalent.
    /// Pure value mapping — `nonisolated` so it can be passed to the nonisolated `compactMap`
    /// closure (and stays callable in Swift 6 language mode under main-actor-default isolation).
    nonisolated private static func mapIssue(_ issue: LLMExtractionIssue) -> OCRReviewIssue? {
        switch issue {
        case .multipleCompetingPrices, .priceOwnershipUncertain: return .multipleCompetingPrices
        case .unitAmbiguous: return .missingUnit
        case .noLegibleItemName: return .missingItemName
        case .expiredOrDatedSaleTag, .partiallyObscuredTag, .handwrittenText, .blurOrGlare:
            return .lowConfidence
        }
    }
}
