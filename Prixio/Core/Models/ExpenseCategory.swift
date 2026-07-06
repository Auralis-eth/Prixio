import Foundation
import FoundationModels

/// Category for a manual household expense. Intentionally small — enough to separate grocery
/// spending from recurring obligations without becoming full accounting software.
/// `@Generable` so model passes (receipt extraction, the add-expense suggester) can be
/// grammar-constrained to exactly these cases.
@Generable
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case groceries
    case bills
    case utilities
    case rent
    case insurance
    case phoneInternet
    case subscriptions
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groceries:
            return "Groceries"
        case .bills:
            return "Bills"
        case .utilities:
            return "Utilities"
        case .rent:
            return "Rent / Housing"
        case .insurance:
            return "Insurance"
        case .phoneInternet:
            return "Phone / Internet"
        case .subscriptions:
            return "Subscriptions"
        case .other:
            return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .groceries:
            return "cart"
        case .bills:
            return "doc.text"
        case .utilities:
            return "bolt"
        case .rent:
            return "house"
        case .insurance:
            return "shield"
        case .phoneInternet:
            return "wifi"
        case .subscriptions:
            return "repeat"
        case .other:
            return "ellipsis.circle"
        }
    }

    /// Categories that represent recurring obligations grouped as "Bills" in the monthly summary.
    static let billLikeCategories: Set<ExpenseCategory> = [.bills, .utilities, .rent, .insurance, .phoneInternet]
}
