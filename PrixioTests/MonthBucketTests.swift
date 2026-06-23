import Foundation
import Testing
@testable import Prixio

struct MonthBucketTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) throws -> Date {
        let components = DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return try #require(calendar.date(from: components))
    }

    @Test
    func start_returnsFirstInstantOfMonth_givenMidMonthDate() throws {
        let input = try date(year: 2026, month: 6, day: 19, hour: 23, minute: 45)
        let expected = try date(year: 2026, month: 6, day: 1)

        let start = MonthBucket.start(of: input, calendar: calendar)

        #expect(start == expected)
    }

    @Test
    func contains_returnsTrueAtMonthBoundaries_givenSameCalendarMonth() throws {
        let month = try date(year: 2026, month: 6, day: 1)
        let firstInstant = try date(year: 2026, month: 6, day: 1)
        let lastDay = try date(year: 2026, month: 6, day: 30, hour: 23, minute: 59)

        #expect(MonthBucket.contains(firstInstant, month: month, calendar: calendar))
        #expect(MonthBucket.contains(lastDay, month: month, calendar: calendar))
    }

    @Test
    func contains_returnsFalse_givenAdjacentMonths() throws {
        let month = try date(year: 2026, month: 6, day: 1)
        let previousMonth = try date(year: 2026, month: 5, day: 31, hour: 23, minute: 59)
        let nextMonth = try date(year: 2026, month: 7, day: 1)

        #expect(!MonthBucket.contains(previousMonth, month: month, calendar: calendar))
        #expect(!MonthBucket.contains(nextMonth, month: month, calendar: calendar))
    }

    @Test
    func displayName_includesMonthAndYear_givenFixedMonth() throws {
        let month = try date(year: 2026, month: 6, day: 15)

        let displayName = MonthBucket.displayName(for: month, calendar: calendar)

        // `displayName` renders the month name with the current host locale, so derive the expected
        // localized month name the same way rather than hard-coding "June" (which fails on non-English
        // hosts). This still asserts the correct month is rendered, just host-independently.
        let expectedMonthName: String = {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("MMMM")
            return formatter.string(from: month)
        }()

        #expect(displayName.contains("2026"))
        #expect(displayName.localizedCaseInsensitiveContains(expectedMonthName))
    }
}
