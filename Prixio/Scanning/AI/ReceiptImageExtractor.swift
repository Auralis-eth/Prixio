//
//  ReceiptImageExtractor.swift
//  Prixio
//
//  Foundation Models image analysis for receipts. A multimodal SystemLanguageModel
//  reads a photo (or rendered PDF page) of a grocery receipt and returns a structured
//  LLMReceiptResult directly. Parallels DefaultPriceImageExtractor for single tags.
//

import FoundationModels
import UIKit

enum ReceiptExtractionOutcome {
    case success(LLMReceiptResult)
    case failure(ReceiptExtractionFailure)
}

enum ReceiptExtractionFailure: Sendable, Equatable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable
    case generationFailed

    var userMessage: String {
        switch self {
        case .deviceNotEligible:
            return "Apple Intelligence is not supported on this device"
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence to read receipts"
        case .modelNotReady:
            return "Apple Intelligence is still preparing. Try again shortly"
        case .unavailable:
            return "Receipt reading is unavailable right now"
        case .generationFailed:
            return "Could not read this receipt. You can still review it manually"
        }
    }
}

protocol ReceiptImageExtracting {
    func extractReceipt(from image: UIImage) async -> ReceiptExtractionOutcome
}

struct DefaultReceiptImageExtractor: ReceiptImageExtracting {
    func extractReceipt(from image: UIImage) async -> ReceiptExtractionOutcome {
        switch SystemLanguageModel.default.availability {
        case .available:
            do {
                let prompt = Prompt {
                    "Extract the store, date, totals, and every purchased line item from this photo of a grocery store receipt."

                    Attachment(image)
                        .label("receipt_photo")
                }

                let session = LanguageModelSession(instructions: {
                    """
                    You are a receipt extraction assistant for a grocery price tracking app. \
                    You analyse photos of store receipts, mostly from Canada.

                    Work in this order:
                    1. Read the header: store/merchant name and the purchase date.
                    2. Read every purchased line item in printed order. Capture the verbatim \
                       line text, then resolve a clean product name, price, and quantity where \
                       you are confident. Skip summary rows (subtotal, tax, total, change, \
                       payment, loyalty points).
                    3. Read the money summary: subtotal, tax, discounts/savings, deposits, and \
                       the final total.
                    4. Finish by reporting every issue that applies.

                    Rules:
                    - A receipt is a basket, not a single price. List each purchased item once.
                    - Discounts and deposits are positive amounts in their own fields, not negative \
                      line items, when the receipt summarises them.
                    - Never invent a name or price. If a line is unreadable, keep its raw text, \
                      leave the uncertain fields null, and set lowConfidence to true.
                    - Most receipt lines are priced "each"; only use weight units when the line \
                      clearly shows a per-weight price.
                    - If the photo is not a receipt, set the notAReceipt issue.
                    """
                })

                let response = try await session.respond(to: prompt, generating: LLMReceiptResult.self)
                return .success(response.content)
            } catch {
                return .failure(.generationFailed)
            }
        case .unavailable(.deviceNotEligible):
            return .failure(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .failure(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            return .failure(.modelNotReady)
        case .unavailable:
            return .failure(.unavailable)
        }
    }
}
