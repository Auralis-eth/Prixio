import Foundation

/// Product category
enum ProductCategory: String, Sendable, CaseIterable, Codable {
    case produce = "produce"
    case meat = "meat"
    case dairy = "dairy"
    case bakery = "bakery"
    case pantry = "pantry"
    case beverages = "beverages"
    case frozen = "frozen"
    case personal = "personal_care"
    case household = "household"
    case health = "health"
    case baby = "baby"
    case pet = "pet"
    case other = "other"
}
