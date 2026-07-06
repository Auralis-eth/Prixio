import Foundation
import SwiftData

/// A user decision about restock suggestions for one item key. Mirrors the
/// `RecurringExpenseRule` lifecycle: `ConsumptionCadenceEngine` only ever *suggests*;
/// a rule records the user's confirm/dismiss so detected cadence is never treated as
/// durable truth on its own. A dismissed rule permanently suppresses the item ("we
/// don't buy this on a schedule"); a confirmed rule can carry a corrected interval
/// that replaces the inferred one.
@Model
final class RestockRule {
    var id: UUID
    var createdAt: Date
    /// Exact normalized item key (`ReceiptLineItem.itemNameNormalized`) the rule
    /// applies to — the same key the cadence engine groups by.
    var itemKey: String
    var displayName: String
    var statusRaw: String
    /// User-corrected repurchase interval in days, replacing the inferred one when set.
    var overrideIntervalDays: Double?
    var lastSuggestedAt: Date?

    var status: RecurringRuleStatus {
        get { RecurringRuleStatus(rawValue: statusRaw) ?? .suggested }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        itemKey: String,
        displayName: String,
        status: RecurringRuleStatus = .suggested,
        overrideIntervalDays: Double? = nil,
        lastSuggestedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.itemKey = itemKey
        self.displayName = displayName
        self.statusRaw = status.rawValue
        self.overrideIntervalDays = overrideIntervalDays
        self.lastSuggestedAt = lastSuggestedAt
    }
}
