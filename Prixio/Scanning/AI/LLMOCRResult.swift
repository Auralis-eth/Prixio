//
//  LLMOCRResult.swift
//  Prixio
//
//  The structured output produced by the iOS 27 image-AI extraction flow.
//  Relocated out of OCRService.swift as part of the OCR → image-AI migration.
//

import Foundation
import FoundationModels

@Generable
struct LLMOCRResult {
    // 1. Reading pass — first, so every field below conditions on it.
    @Guide(description: "Transcribe only text relevant to product identity and pricing. Skip slogans, barcode digits, and legal fine print.")
    var relevantText: String

    // 2. Scene assessment before extraction.
    @Guide(description: "What kind of signage the source shows.")
    var scene: LLMSceneKind

    // 3. Enumerate all evidence before resolving anything.
    @Guide(description: "Every distinct price present, with its verbatim label context. Include regular, sale, member/loyalty, unit-comparison prices, deposits, and multi-buy offers.", .count(1...8), .maximumCount(10))
    var priceCandidates: [LLMPriceCandidate]

    // 4. Resolution — conditioned on the full candidate list.
    @Guide(description: "The most specific product name legible, e.g. 'Organic Honeycrisp Apples' not 'Apples'. Exclude store brand prefixes unless they are the only identifier. Null if no product name is legible.")
    var itemName: String?

    @Guide(description: "Brand name if distinct from the product name, e.g. 'Compliments', 'PC'. Null otherwise.")
    var brand: String?

    @Guide(description: "The price a shopper pays today for the primary product. If both a sale and regular price appear, the sale price.", .minimum(0))
    var price: Decimal?

    @Guide(description: "Unit the price applies to. Most produce is per lb or per kg; packaged goods are usually each. Null only if genuinely undeterminable.")
    var unit: UnitType?

    @Guide(description: "Quantity the price covers, e.g. 3 for '3 for $5'. Usually 1.", .minimum(0))
    var quantity: Decimal?

    @Guide(description: "Sale expiry date if printed, formatted YYYY-MM-DD. Null if absent.")//,  .pattern(/^\d{4}-\d{2}-\d{2}$/))
    var saleEndsOn: String?

    // 5. Honesty pass — last, after all commitments above.
    @Guide(description: "Every problem that applies to this extraction. Empty only if the tag is clean, complete, and unambiguous.", .maximumCount(10))
    var issues: [LLMExtractionIssue]
}

@Generable
enum LLMSceneKind: String, Codable {
    case singleTag, multiTag, promoCard, produceSign, receiptLike, unclear
}

@Generable
struct LLMPriceCandidate {
    @Guide(description: "Verbatim label or context attached to this price, e.g. 'Club Price', 'was', 'per 100g'. Empty string if unlabeled.")
    var label: String

    @Guide(description: "The price value.", .minimum(0))
    var value: Decimal

    @Guide(description: "Quantity this price covers if a multi-buy, e.g. 2 for '2 for $7'. Null for single-item prices.", .minimum(0))
    var quantity: Decimal?

    var kind: PriceKind

    @Guide(description: "The exact source text this price came from.")
    var sourceText: String
}

@Generable
enum LLMExtractionIssue: String, Codable {
    case multipleCompetingPrices
    case priceOwnershipUncertain   // price may belong to a neighboring product
    case unitAmbiguous
    case noLegibleItemName
    case expiredOrDatedSaleTag
    // Visual-only — image path emits these; merge policy ignores them from the text path.
    case partiallyObscuredTag
    case handwrittenText
    case blurOrGlare
}
