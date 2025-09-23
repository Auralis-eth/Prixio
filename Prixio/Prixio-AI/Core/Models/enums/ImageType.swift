import Foundation

/// Image type classification
enum ImageType: String, Sendable, CaseIterable, Codable {
    case product = "product"         // Product photo
    case receipt = "receipt"         // Receipt image
    case priceTag = "price_tag"      // Price tag photo
    case storefront = "storefront"   // Store exterior
    case interior = "interior"       // Store interior
    case shelf = "shelf"            // Product on shelf
}
