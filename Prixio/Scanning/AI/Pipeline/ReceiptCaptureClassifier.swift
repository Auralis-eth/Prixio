//
//  ReceiptCaptureClassifier.swift
//  Prixio
//
//  Centralizes the receipt-capture suppression previously inlined in
//  ScanViewModel.processPickedImage. Both the model's scene == .receiptLike
//  signal and the text heuristic are checked in one place.
//

import Foundation

enum ReceiptCaptureClassifier {
    static func isReceiptOrInvalid(_ result: LLMOCRResult) -> Bool {
        if result.scene == .receiptLike { return true }
        return PriceParsingService.looksLikeReceipt(text: result.relevantText)
    }
}
