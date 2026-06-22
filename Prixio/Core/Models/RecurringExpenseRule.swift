import Foundation
import SwiftData

/// A recurring-expense pattern. Created from a conservative suggestion and then confirmed or
/// dismissed by the user — the app never treats detected recurrence as durable truth on its own.
@Model
final class RecurringExpenseRule {
    var id: UUID
    var createdAt: Date
    /// Normalized key the pattern matches on (merchant name or `category:<id>`).
    var matchKey: String
    var displayLabel: String
    var cadenceRaw: String
    var expectedAmount: Decimal?
    var statusRaw: String
    var lastMatchedAt: Date?

    var cadence: RecurrenceCadence {
        get { RecurrenceCadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    var status: RecurringRuleStatus {
        get { RecurringRuleStatus(rawValue: statusRaw) ?? .suggested }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        matchKey: String,
        displayLabel: String,
        cadence: RecurrenceCadence = .monthly,
        expectedAmount: Decimal? = nil,
        status: RecurringRuleStatus = .suggested,
        lastMatchedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.matchKey = matchKey
        self.displayLabel = displayLabel
        self.cadenceRaw = cadence.rawValue
        self.expectedAmount = expectedAmount
        self.statusRaw = status.rawValue
        self.lastMatchedAt = lastMatchedAt
    }
}
