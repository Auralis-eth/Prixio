//
//  PriceParsingConfidenceResolver.swift
//  Prixio
//

import Foundation

struct PriceParsingConfidenceResolver {
    func analyzeAmbiguity(in snapshot: PriceParsingService.HeuristicExtractionSnapshot) -> PriceParsingService.ExtractionAmbiguityReport {
        var weaknesses: [PriceParsingService.ExtractionWeakness] = []
        let ocrConfidence = ocrEvidenceConfidence(snapshot: snapshot)
        let parseConfidence = parseStructureConfidence(snapshot: snapshot)
        let combinedConfidence = combinedConfidence(
            ocrConfidence: ocrConfidence,
            parseConfidence: parseConfidence
        )

        if snapshot.priceCandidates.isEmpty {
            weaknesses.append(.noPriceCandidates)
        }

        if PriceCandidateScorer().hasCompetingTopCandidates(snapshot.priceCandidates) {
            weaknesses.append(.multipleCompetingPrices)
        }

        if snapshot.itemNameHint?.isEmpty != false {
            weaknesses.append(.missingItemName)
        }

        if snapshot.detectedUnit == nil {
            weaknesses.append(.missingUnit)
        }

        if snapshot.resolvedQuantity == nil && snapshot.detectedUnit != .each {
            weaknesses.append(.missingQuantity)
        }

        if ocrConfidence < 0.45 || parseConfidence < 0.45 || combinedConfidence < 0.5 {
            weaknesses.append(.lowConfidence)
        }

        if snapshot.cleanedObservations.count <= 1 || snapshot.lines.count <= 1 {
            weaknesses.append(.sparseOCR)
        }

        if snapshot.sceneClassification == .multiTag || looksLikeMultiProductScan(snapshot) {
            weaknesses.append(.possibleMultiProductScan)
        }

        return PriceParsingService.ExtractionAmbiguityReport(weaknesses: weaknesses)
    }

    func makeOCRResult(from snapshot: PriceParsingService.HeuristicExtractionSnapshot) -> OCRResult {
        let ambiguity = analyzeAmbiguity(in: snapshot)
        let ocrConfidence = ocrEvidenceConfidence(snapshot: snapshot)
        let parseConfidence = parseStructureConfidence(snapshot: snapshot)
        let combined = combinedConfidence(
            ocrConfidence: ocrConfidence,
            parseConfidence: parseConfidence
        )
        return OCRResult(
            rawText: snapshot.rawText,
            itemNameHint: snapshot.itemNameHint,
            itemNameEvidence: snapshot.itemNameEvidence,
            price: snapshot.priceCandidates.first?.value,
            unit: snapshot.detectedUnit,
            quantity: snapshot.resolvedQuantity,
            confidence: assembleHeuristicConfidence(
                snapshot: snapshot,
                ambiguity: ambiguity,
                ocrConfidence: ocrConfidence,
                parseConfidence: parseConfidence
            ),
            priceCandidates: snapshot.priceCandidates,
            review: OCRReview(ambiguity: ambiguity, usedFoundationModel: false),
            parserDecisionReport: makeDecisionReport(
                snapshot: snapshot,
                ambiguity: ambiguity,
                ocrConfidence: ocrConfidence,
                parseConfidence: parseConfidence,
                combinedConfidence: combined,
                usedFoundationModel: false
            ),
            supportingLines: snapshot.consolidatedObservations.map(\.string)
        )
    }

    func looksLikeMultiProductScan(_ snapshot: PriceParsingService.HeuristicExtractionSnapshot) -> Bool {
        let meaningfulSpatialGroups = snapshot.spatialGroups.filter { group in
            let hasPrice = group.observations.contains { PriceParsingService.containsPriceSignal(in: $0.string) }
            let hasDescription = group.observations.contains { observation in
                isProductDescriptor(observation.string)
            }
            return group.observations.count >= 2 && hasPrice && hasDescription
        }
        if meaningfulSpatialGroups.count >= 2 {
            return true
        }

        let descriptiveLines = snapshot.lines.filter { line in
            isProductDescriptor(line)
        }
        let distinctPriceSources = Set(snapshot.priceCandidates.map(\.sourceText))
        return descriptiveLines.count >= 2 && distinctPriceSources.count >= 2
    }

    func sourceLineIndexes(
        for candidate: PriceCandidate,
        in snapshot: PriceParsingService.HeuristicExtractionSnapshot
    ) -> [Int] {
        sourceLineIndexes(for: candidate, in: snapshot.consolidatedObservations)
    }

    func sourceLineIndexes(
        for candidate: PriceCandidate,
        in observations: [OCRTextObservation]
    ) -> [Int] {
        if !candidate.sourceLineIndexes.isEmpty {
            return candidate.sourceLineIndexes
        }

        return observations.enumerated().compactMap { index, observation in
            let line = observation.string.lowercased()
            let source = candidate.sourceText.lowercased()
            return line.contains(source) || source.contains(line) ? index : nil
        }
    }

    func assembleHeuristicConfidence(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        ambiguity: PriceParsingService.ExtractionAmbiguityReport,
        ocrConfidence: Float,
        parseConfidence: Float
    ) -> Float {
        var confidence = combinedConfidence(
            ocrConfidence: ocrConfidence,
            parseConfidence: parseConfidence
        )

        for weakness in ambiguity.weaknesses {
            confidence -= confidencePenalty(for: weakness)
        }

        return min(0.99, max(0.1, confidence))
    }

    func ocrEvidenceConfidence(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot
    ) -> Float {
        let averageConfidence = PriceParsingService.averageConfidence(in: snapshot.supportedObservations)
            ?? PriceParsingService.averageConfidence(in: snapshot.cleanedObservations)
            ?? snapshot.heuristicConfidence
        var confidence = max(0.1, averageConfidence)

        if snapshot.supportedObservations.count >= 2 && snapshot.lines.count >= 2 {
            confidence += 0.08
        }
        if snapshot.cleanedObservations.count >= 3 {
            confidence += 0.04
        }
        if snapshot.cleanedObservations.count <= 1 || snapshot.lines.count <= 1 {
            confidence -= 0.12
        }

        return min(0.95, max(0.1, confidence))
    }

    func parseStructureConfidence(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot
    ) -> Float {
        var confidence: Float = 0.15

        if !snapshot.priceCandidates.isEmpty {
            confidence += 0.30
        }
        if snapshot.itemNameHint?.isEmpty == false {
            confidence += 0.18
        } else {
            confidence -= 0.08
        }
        if snapshot.detectedUnit != nil {
            confidence += 0.12
        } else {
            confidence -= 0.08
        }
        if snapshot.resolvedQuantity != nil || snapshot.detectedUnit == .each {
            confidence += 0.08
        }
        if let winningClusterIndex = snapshot.winningClusterIndex,
           snapshot.evidenceClusters.indices.contains(winningClusterIndex),
           snapshot.evidenceClusters[winningClusterIndex].role == .productText {
            confidence += 0.08
        }
        if !PriceCandidateScorer().hasCompetingTopCandidates(snapshot.priceCandidates) {
            confidence += 0.05
        }

        switch snapshot.sceneClassification {
        case .singleTag:
            confidence += 0.04
        case .multiTag:
            confidence -= 0.10
        case .promoCard:
            confidence -= 0.05
        case .receiptLike:
            confidence -= 0.12
        case .unclear:
            confidence -= 0.06
        }

        return min(0.95, max(0.1, confidence))
    }

    func combinedConfidence(
        ocrConfidence: Float,
        parseConfidence: Float
    ) -> Float {
        (ocrConfidence * 0.45) + (parseConfidence * 0.55)
    }

    func confidencePenalty(for weakness: PriceParsingService.ExtractionWeakness) -> Float {
        switch weakness {
        case .noPriceCandidates:
            return 0.28
        case .multipleCompetingPrices:
            return 0.18
        case .missingItemName:
            return 0.12
        case .missingUnit:
            return 0.12
        case .missingQuantity:
            return 0.08
        case .lowConfidence:
            return 0.10
        case .sparseOCR:
            return 0.10
        case .possibleMultiProductScan:
            return 0.16
        }
    }

    func makeDecisionReport(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        ambiguity: PriceParsingService.ExtractionAmbiguityReport,
        ocrConfidence: Float,
        parseConfidence: Float,
        combinedConfidence: Float,
        usedFoundationModel: Bool
    ) -> PriceParsingService.ParserDecisionReport {
        PriceParsingService.ParserDecisionReport(
            ocrConfidence: ocrConfidence,
            parseConfidence: parseConfidence,
            combinedConfidence: combinedConfidence,
            sceneClassification: snapshot.sceneClassification,
            winningPriceKind: snapshot.priceCandidates.first?.kind,
            reasons: makeDecisionReasons(
                snapshot: snapshot,
                ambiguity: ambiguity,
                ocrConfidence: ocrConfidence,
                parseConfidence: parseConfidence,
                usedFoundationModel: usedFoundationModel
            )
        )
    }

    func makeDecisionReasons(
        snapshot: PriceParsingService.HeuristicExtractionSnapshot,
        ambiguity: PriceParsingService.ExtractionAmbiguityReport,
        ocrConfidence: Float,
        parseConfidence: Float,
        usedFoundationModel: Bool
    ) -> [PriceParsingService.ParserDecisionReason] {
        var reasons: [PriceParsingService.ParserDecisionReason] = []

        if snapshot.cleanedObservations.count <= 1 || snapshot.lines.count <= 1 {
            reasons.append(.init(
                category: .ocr,
                code: "sparse_ocr",
                detail: "OCR recovered very few usable lines."
            ))
        } else if ocrConfidence >= 0.7 {
            reasons.append(.init(
                category: .ocr,
                code: "usable_ocr_evidence",
                detail: "OCR recovered enough evidence to support parsing."
            ))
        }

        switch snapshot.sceneClassification {
        case .multiTag, .unclear:
            reasons.append(.init(
                category: .ownership,
                code: "scene_\(snapshot.sceneClassification.rawValue)",
                detail: "Scene structure suggests ambiguous ownership between nearby product evidence."
            ))
        case .singleTag:
            reasons.append(.init(
                category: .ownership,
                code: "single_tag_scene",
                detail: "Cluster layout looks like one product tag."
            ))
        case .promoCard, .receiptLike:
            reasons.append(.init(
                category: .ownership,
                code: "scene_\(snapshot.sceneClassification.rawValue)",
                detail: "Scene shape changes how confidently the parser can assign ownership."
            ))
        }

        if let winningKind = snapshot.priceCandidates.first?.kind {
            reasons.append(.init(
                category: .candidateKind,
                code: "winning_price_kind_\(winningKind.rawValue)",
                detail: "The winning price candidate was classified as \(winningKind.rawValue)."
            ))
        }
        if PriceCandidateScorer().hasCompetingTopCandidates(snapshot.priceCandidates) {
            reasons.append(.init(
                category: .candidateKind,
                code: "competing_price_candidates",
                detail: "More than one price candidate remained close enough to compete."
            ))
        }

        for weakness in ambiguity.weaknesses {
            reasons.append(.init(
                category: .review,
                code: weakness.rawValue,
                detail: weaknessDetail(for: weakness)
            ))
        }

        if usedFoundationModel {
            reasons.append(.init(
                category: .review,
                code: "foundation_model_used",
                detail: "Foundation Models were used as a tie-breaker."
            ))
        }

        if parseConfidence >= 0.7 && ambiguity.weaknesses.isEmpty {
            reasons.append(.init(
                category: .review,
                code: "stable_parse",
                detail: "The deterministic parser reached a stable result without review issues."
            ))
        }

        return reasons
    }

    func weaknessDetail(for weakness: PriceParsingService.ExtractionWeakness) -> String {
        switch weakness {
        case .noPriceCandidates:
            return "No reliable price candidate survived parsing."
        case .multipleCompetingPrices:
            return "Multiple price candidates remained close enough to compete."
        case .missingItemName:
            return "The parser could not build a confident item name."
        case .missingUnit:
            return "The parser could not confirm a unit of measure."
        case .missingQuantity:
            return "The parser could not confirm quantity context."
        case .lowConfidence:
            return "Combined OCR and parse confidence stayed low."
        case .sparseOCR:
            return "OCR evidence was too sparse for a stable parse."
        case .possibleMultiProductScan:
            return "The image may contain more than one product."
        }
    }

    func containsPhoneNumber(in text: String) -> Bool {
        text.range(of: #"\d{10,}"#, options: .regularExpression) != nil
    }

    func looksLikeDateLine(_ text: String) -> Bool {
        guard text.range(of: PriceParsingService.monthNamePattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return false
        }

        let hasDay = text.range(of: #"\b([12]?\d|3[01])\b"#, options: .regularExpression) != nil
        let hasYear = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        return hasDay || hasYear
    }

    func isProductDescriptor(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        guard !PriceParsingService.containsPriceSignal(in: trimmed) else {
            return false
        }
        guard !PriceParsingItemNameResolver().looksLikeReceiptFragment(trimmed) else {
            return false
        }
        guard !PriceParsingItemNameResolver().looksLikePromoBanner(trimmed) else {
            return false
        }
        guard trimmed.range(of: PriceParsingService.depositMarkerPattern, options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }
        guard trimmed.range(of: PriceParsingService.regularPriceMarkerPattern, options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }

        let words = trimmed.normalizedWords()
        let descriptiveTokens = words.filter { token in
            token.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
                && !PriceParsingService.itemNameIgnoredTokens.contains(token)
                && !PriceParsingItemNameResolver().isPureUnitToken(token)
        }

        return descriptiveTokens.count >= 1
    }
}
