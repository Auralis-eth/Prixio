//
//  OCRResult.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

enum OCRReviewIssue: String, Codable, CaseIterable, Sendable, Identifiable {
    case noPriceCandidates
    case multipleCompetingPrices
    case missingItemName
    case missingUnit
    case missingQuantity
    case lowConfidence
    case sparseOCR
    case possibleMultiProductScan

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .noPriceCandidates:
            return "No price found"
        case .multipleCompetingPrices:
            return "Competing prices"
        case .missingItemName:
            return "Item name weak"
        case .missingUnit:
            return "Unit missing"
        case .missingQuantity:
            return "Quantity missing"
        case .lowConfidence:
            return "Low confidence"
        case .sparseOCR:
            return "Sparse OCR"
        case .possibleMultiProductScan:
            return "Multiple products"
        }
    }

    var detail: String {
        switch self {
        case .noPriceCandidates:
            return "No reliable shelf price was extracted from this scan."
        case .multipleCompetingPrices:
            return "Several price lines are competing for the same scan."
        case .missingItemName:
            return "The item name still looks weak and should be checked."
        case .missingUnit:
            return "The unit of measure could not be confirmed."
        case .missingQuantity:
            return "Quantity context could not be confirmed from the tag."
        case .lowConfidence:
            return "The parser confidence stayed low after OCR cleanup."
        case .sparseOCR:
            return "OCR recovered very little usable evidence from the image."
        case .possibleMultiProductScan:
            return "This image may contain more than one product tag."
        }
    }
}

enum OCRReviewState: String, Codable, Sendable {
    case clean
    case reviewRecommended
    case reviewRequired
}

struct OCRReview: Codable, Equatable, Sendable {
    var issues: [OCRReviewIssue] = []
    var ambiguityNotes: [String] = []
    var usedFoundationModel = false

    static let clean = OCRReview()

    var state: OCRReviewState {
        let severeIssues: Set<OCRReviewIssue> = [
            .noPriceCandidates,
            .multipleCompetingPrices,
            .possibleMultiProductScan
        ]
        if !severeIssues.isDisjoint(with: issues) {
            return .reviewRequired
        }
        if !issues.isEmpty || usedFoundationModel {
            return .reviewRecommended
        }
        return .clean
    }

    var requiresExplicitSaveConfirmation: Bool {
        state == .reviewRequired
    }

    var title: String {
        switch state {
        case .clean:
            return "Scan looks solid"
        case .reviewRecommended:
            return usedFoundationModel ? "Review assisted scan" : "Review suggested details"
        case .reviewRequired:
            return "Review required before saving"
        }
    }

    var summary: String {
        if let primaryIssue = prioritizedIssues.first {
            return primaryIssue.detail
        }
        if usedFoundationModel {
            return "Foundation Models helped isolate the likely product. Confirm the fields before saving."
        }
        return "The parser found a consistent price, item, and unit from this tag."
    }

    var detailNotes: [String] {
        var notes = prioritizedIssues.map(\.detail)
        for note in ambiguityNotes where !notes.contains(note) {
            notes.append(note)
        }
        return Array(notes.prefix(3))
    }

    private var prioritizedIssues: [OCRReviewIssue] {
        let priority: [OCRReviewIssue] = [
            .possibleMultiProductScan,
            .multipleCompetingPrices,
            .noPriceCandidates,
            .lowConfidence,
            .sparseOCR,
            .missingItemName,
            .missingUnit,
            .missingQuantity
        ]
        return priority.filter { issues.contains($0) }
    }
}

struct OCRQualityReport: Codable, Equatable, Sendable {
    let selectedVariant: String
    let attemptedFallback: Bool
    let observationCount: Int
    let priceSignalCount: Int
    let descriptorCount: Int
    let averageConfidence: Float
    let confidenceSpread: Float
    let selectedVariantScore: Float
}

struct OCRResult {
    var rawText: String
    var itemNameHint: String?
    var itemNameEvidence: String? = nil
    var price: Decimal?
    var unit: UnitType?
    var quantity: Decimal?
    var confidence: Float?
    var priceCandidates: [PriceCandidate]
    var review: OCRReview = .clean
    var ocrQualityReport: OCRQualityReport? = nil
    var parserDecisionReport: PriceParsingService.ParserDecisionReport? = nil
    /// Evidence for the selected parse result. Deterministic inputs may pin this exactly,
    /// while live OCR or model-assisted paths should only rely on stable invariants.
    let supportingLines: [String]
}

extension OCRReviewIssue {
    @MainActor
    init?(weakness: PriceParsingService.ExtractionWeakness) {
        switch weakness {
        case .noPriceCandidates:
            self = .noPriceCandidates
        case .multipleCompetingPrices:
            self = .multipleCompetingPrices
        case .missingItemName:
            self = .missingItemName
        case .missingUnit:
            self = .missingUnit
        case .missingQuantity:
            self = .missingQuantity
        case .lowConfidence:
            self = .lowConfidence
        case .sparseOCR:
            self = .sparseOCR
        case .possibleMultiProductScan:
            self = .possibleMultiProductScan
        }
    }
}

extension OCRReview {
    @MainActor
    init(
        ambiguity: PriceParsingService.ExtractionAmbiguityReport,
        usedFoundationModel: Bool,
        ambiguityNotes: [String] = []
    ) {
        let mappedIssues = ambiguity.weaknesses.compactMap(OCRReviewIssue.init)
        self.issues = Array(NSOrderedSet(array: mappedIssues)) as? [OCRReviewIssue] ?? mappedIssues
        self.ambiguityNotes = ambiguityNotes
        self.usedFoundationModel = usedFoundationModel
    }
}
