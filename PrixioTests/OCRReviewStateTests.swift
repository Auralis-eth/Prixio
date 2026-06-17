import Foundation
import Testing
@testable import Prixio

@MainActor
struct OCRReviewStateTests {
    @Test(.tags(.ocr, .product, .shipGate))
    func emptyIssuesAreCleanEvenWhenFoundationModelWasUsed() async throws {
        let review = OCRReview(issues: [], ambiguityNotes: [], usedFoundationModel: true)

        // The image-AI path always sets usedFoundationModel = true. That flag is
        // metadata only — it must NOT by itself force a review state (§3.3).
        #expect(review.state == .clean)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func nonSevereIssueIsReviewRecommended() async throws {
        let review = OCRReview(issues: [.missingUnit], ambiguityNotes: [], usedFoundationModel: true)

        #expect(review.state == .reviewRecommended)
        #expect(review.requiresExplicitSaveConfirmation == false)
    }

    @Test(.tags(.ocr, .product, .shipGate))
    func severeIssueIsReviewRequired() async throws {
        for issue: OCRReviewIssue in [.noPriceCandidates, .multipleCompetingPrices, .possibleMultiProductScan] {
            let review = OCRReview(issues: [issue], ambiguityNotes: [], usedFoundationModel: true)
            #expect(review.state == .reviewRequired)
            #expect(review.requiresExplicitSaveConfirmation)
        }
    }
}
