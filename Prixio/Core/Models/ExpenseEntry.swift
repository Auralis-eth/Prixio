import Foundation
import SwiftData

/// One manual household expense or bill. Kept separate from `PriceEntry` (a trusted item price) and
/// `ReceiptCapture` (a basket) so spending context never pollutes price comparison.
@Model
final class ExpenseEntry {
    var id: UUID
    var createdAt: Date
    /// The date the spending happened (distinct from when it was entered).
    var date: Date
    var amount: Decimal
    var currencyCode: String
    var categoryRaw: String
    var merchant: String?
    var note: String?
    /// Links this expense to a confirmed `RecurringExpenseRule`, when one applies.
    var recurringRuleID: UUID?

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        date: Date = .now,
        amount: Decimal,
        currencyCode: String = AppCurrency.defaultCode,
        category: ExpenseCategory = .other,
        merchant: String? = nil,
        note: String? = nil,
        recurringRuleID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.date = date
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryRaw = category.rawValue
        self.merchant = merchant
        self.note = note
        self.recurringRuleID = recurringRuleID
    }
}
