//
//  ScanReview.swift
//  Prixio
//
//  Prixio's review model for a price extraction. Relocated out of OCRResult.swift
//  as part of the OCR → image-AI migration. The image-AI path always records
//  usedFoundationModel = true for audit, so that flag is metadata only — it must
//  NOT by itself force a review state (see PriceExtractionValidator).
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
    case receiptCapture

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
        case .receiptCapture:
            return "Receipt captured"
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
            return "The extraction confidence stayed low for this scan."
        case .sparseOCR:
            return "Very little usable evidence was recovered from the image."
        case .possibleMultiProductScan:
            return "This image may contain more than one product tag."
        case .receiptCapture:
            return "Receipts are not supported for price capture. Retake a shelf tag or product sign."
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
            .possibleMultiProductScan,
            .receiptCapture
        ]
        if !severeIssues.isDisjoint(with: issues) {
            return .reviewRequired
        }
        // usedFoundationModel is metadata for the image-AI path, not a review trigger.
        // Only real issues drive review; an empty issue set is clean.
        if !issues.isEmpty {
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
        return "The scan produced a consistent price, item, and unit from this tag."
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
            .receiptCapture,
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
