import Foundation

/// Small calendar helper for grouping spending by calendar month. No equivalent helper existed
/// before the spending features.
enum MonthBucket {
    /// The first instant of the calendar month containing `date`.
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Whether `date` falls in the same calendar month as `month`.
    static func contains(_ date: Date, month: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: month, toGranularity: .month)
    }

    /// A short "June 2026" style label for a month.
    static func displayName(for month: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: month)
    }
}
