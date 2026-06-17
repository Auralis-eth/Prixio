import Foundation
import Testing
@testable import Prixio

@MainActor
struct ReceiptCaptureClassifierTests {
    @Test(.tags(.ocr, .product))
    func receiptSceneIsTreatedAsReceipt() async throws {
        let result = LLMOCRResult.fixture(relevantText: "Bananas $1.29", scene: .receiptLike)
        #expect(ReceiptCaptureClassifier.isReceiptOrInvalid(result))
    }

    @Test(.tags(.ocr, .product))
    func receiptMarkerTextIsTreatedAsReceipt() async throws {
        let result = LLMOCRResult.fixture(
            relevantText: "Subtotal 12.99\nTax 1.69\nTotal 14.68\nVisa",
            scene: .unclear
        )
        #expect(ReceiptCaptureClassifier.isReceiptOrInvalid(result))
    }

    @Test(.tags(.ocr, .product))
    func ordinaryShelfTagIsNotReceipt() async throws {
        let result = LLMOCRResult.fixture(relevantText: "Fresh Bananas\n$1.29 /lb", scene: .singleTag)
        #expect(ReceiptCaptureClassifier.isReceiptOrInvalid(result) == false)
    }
}
