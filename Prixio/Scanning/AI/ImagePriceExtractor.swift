//
//  ImagePriceExtractor.swift
//  Prixio
//
//  The iOS 27 image-AI extraction flow. A multimodal SystemLanguageModel reads a
//  photo of grocery signage and returns a structured LLMOCRResult directly.
//  Relocated out of OCRService.swift as part of the OCR → image-AI migration.
//

import FoundationModels
import UIKit

enum ImagePriceExtractionOutcome {
    case success(LLMOCRResult)
    case failure(ImagePriceExtractionFailure)
}

enum ImagePriceExtractionFailure: Sendable, Equatable {
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
            return "Turn on Apple Intelligence to extract prices"
        case .modelNotReady:
            return "Apple Intelligence is still preparing. Try again shortly"
        case .unavailable:
            return "Price extraction is unavailable right now"
        case .generationFailed:
            return "Price extraction failed. Try another photo"
        }
    }
}

protocol PriceImageExtracting {
    func extractPriceInformation(
        from image: UIImage,
        context: ScanPromptContext,
        tools: [any Tool]
    ) async -> ImagePriceExtractionOutcome
}

struct DefaultPriceImageExtractor: PriceImageExtracting {
    func extractPriceInformation(
        from image: UIImage,
        context: ScanPromptContext,
        tools: [any Tool]
    ) async -> ImagePriceExtractionOutcome {
        await image.extractPriceInformation(context: context, tools: tools)
    }
}

extension UIImage {
    /// Extract structured product/pricing fields from a photo of grocery signage.
    ///
    /// Returns a typed outcome so callers can distinguish model availability from
    /// generation failures and present the right recovery message.
    ///
    /// - Parameter tools: Model-callable tools registered on the session so the model
    ///   can normalise unit prices, resolve units/quantities, infer store context, and
    ///   look up item history while extracting. Pass `[]` for a plain extraction.
    func extractPriceInformation(
        context: ScanPromptContext = .none,
        tools: [any Tool] = []
    ) async -> ImagePriceExtractionOutcome {
        switch SystemLanguageModel.default.availability {
        case .available:
            do {
                let prompt = Prompt {
                    "Extract the product and pricing information from this photo of grocery store signage."

                    if let storeName = context.storeName {
                        "The photo was taken at \(storeName)."
                    }

                    if let expectedItem = context.expectedItemName {
                        """
                        The shopper was trying to capture a price for "\(expectedItem)". \
                        Use this only to disambiguate between multiple tags — if the dominant \
                        tag is clearly a different product, extract that product instead.
                        """
                    }

                    Attachment(self)
                        .label("shelf_tag_photo")
                }

                let session = LanguageModelSession(tools: tools, instructions: {
                    """
                    You are a price extraction assistant for a grocery price tracking app. \
                    You analyse photos of shelf tags, price labels, produce signs, and promo \
                    cards from grocery stores and farmers markets, mostly in Canada.

                    Work in this order:
                    1. Transcribe the pricing-relevant text first. Everything else depends on it.
                    2. Classify the scene. A photo may contain several tags; identify whether \
                       one tag clearly dominates.
                    3. List every distinct price as a candidate with its verbatim label before \
                       deciding anything. Regular, sale, member/loyalty, per-unit comparison \
                       prices, deposits, and multi-buy tiers are all separate candidates.
                    4. Only then resolve the primary fields, using your candidate list.
                    5. Finish by reporting every issue that applies. Use the issue flags to \
                       express doubt — never compensate for uncertainty by guessing a value.

                    Resolution rules:
                    - The primary price is what a shopper pays today: sale or member price \
                      beats regular price.
                    - Per-unit comparison prices (e.g. "$1.10 / 100 g") and bottle deposits \
                      are candidates, never the primary price.
                    - For multi-buy deals like "3 for $5", set price 5, quantity 3.
                    - Price ownership matters most. On crowded shelves a price often belongs \
                      to the neighbouring product. Extract from the single dominant tag only, \
                      and if the pairing between name and price is not visually certain, \
                      report priceOwnershipUncertain.
                    - Tags are often bilingual English/French. The French text is the same \
                      product, not a second one. Prefer the English name.
                    - Prefer specificity: "Organic Fuji Apples" over "Apples". But never \
                      invent detail that is not legible — when in doubt, leave a field nil.
                    - Most produce is priced per lb or per kg; packaged goods are usually each.
                    """
                })

                let response = try await session.respond(to: prompt, generating: LLMOCRResult.self)
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
