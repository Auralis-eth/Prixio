import Foundation
import SwiftData

/// One household income declaration. Household-level only for the first version — per-person income
/// is an open product question (see PriceCaptureAndIntelligence.md).
@Model
final class IncomeEntry {
    var id: UUID
    var createdAt: Date
    /// The date the income applies to (e.g. a deposit date).
    var date: Date
    var amount: Decimal
    var currencyCode: String
    var label: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        date: Date = .now,
        amount: Decimal,
        currencyCode: String = AppCurrency.defaultCode,
        label: String = "Income"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.date = date
        self.amount = amount
        self.currencyCode = currencyCode
        self.label = label
    }
}
