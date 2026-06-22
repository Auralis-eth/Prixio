import Foundation

/// How often a recurring expense repeats. Used both for detection (classifying observed intervals)
/// and for display on confirmed rules.
enum RecurrenceCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly:
            return "Looks weekly"
        case .biweekly:
            return "Looks biweekly"
        case .monthly:
            return "Looks monthly"
        }
    }

    /// Approximate number of days between occurrences, used to classify observed intervals.
    var approximateDays: Double {
        switch self {
        case .weekly:
            return 7
        case .biweekly:
            return 14
        case .monthly:
            return 30
        }
    }
}

/// Lifecycle of a recurring-expense rule. A rule starts life as a `suggested` pattern the user can
/// `confirmed` or `dismissed`; dismissed rules suppress future suggestions for the same pattern.
enum RecurringRuleStatus: String, Codable, CaseIterable, Sendable {
    case suggested
    case confirmed
    case dismissed
}
