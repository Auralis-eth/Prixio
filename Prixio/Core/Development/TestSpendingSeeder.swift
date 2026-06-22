import Foundation
import SwiftData

#if DEBUG
/// Developer-only seeder for the Spending tab. Inserts several months of marked expenses, income,
/// and grocery receipts so the monthly summary, spend-over-time trend, store share, budget pressure,
/// recurring detection, and spending-anomaly surfaces can be exercised with realistic data. Gated
/// out of release builds.
@MainActor
enum TestSpendingSeeder {
    private static let marker = "Prixio.TestSpendingSeeder.v1"
    private static let incomeLabel = "Test Seed Paycheck"
    private static let monthsBack = 4

    static func seededCount(in context: ModelContext) throws -> Int {
        try fetchSeededExpenses(in: context).count
            + fetchSeededIncome(in: context).count
            + fetchSeededReceipts(in: context).count
    }

    static func insertRecords(into context: ModelContext, now: Date = .now) throws {
        let calendar = Calendar.current
        let currentMonthStart = MonthBucket.start(of: now, calendar: calendar)

        for offset in 0..<monthsBack {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else {
                continue
            }
            let isCurrentMonth = offset == 0

            // Household income.
            context.insert(IncomeEntry(date: day(1, in: monthStart, calendar), amount: 3000, label: incomeLabel))

            // Recurring obligations (consistent monthly -> recurring suggestions).
            context.insert(expense(1500, .rent, "Test Landlord", day(1, in: monthStart, calendar)))
            context.insert(expense(Decimal(1599) / 100, .subscriptions, "Test Netflix", day(5, in: monthStart, calendar)))

            // Utilities: a current-month spike vs a steady baseline -> spending anomaly.
            context.insert(expense(isCurrentMonth ? 400 : 100, .utilities, "Test Hydro", day(10, in: monthStart, calendar)))

            // A manual grocery top-up.
            context.insert(expense(60, .groceries, "Test Corner Store", day(15, in: monthStart, calendar)))

            // Grocery receipts at two stores -> store share + receipt grocery spend.
            context.insert(receipt(85, "Test Mart", day(8, in: monthStart, calendar)))
            context.insert(receipt(45, "Seed Foods", day(20, in: monthStart, calendar)))
        }

        try context.save()
    }

    static func deleteRecords(in context: ModelContext) throws {
        for expense in try fetchSeededExpenses(in: context) {
            context.delete(expense)
        }
        for income in try fetchSeededIncome(in: context) {
            context.delete(income)
        }
        for receipt in try fetchSeededReceipts(in: context) {
            context.delete(receipt)
        }
        try context.save()
    }

    // MARK: - Builders

    private static func expense(
        _ amount: Decimal,
        _ category: ExpenseCategory,
        _ merchant: String,
        _ date: Date
    ) -> ExpenseEntry {
        ExpenseEntry(date: date, amount: amount, category: category, merchant: merchant, note: marker)
    }

    private static func receipt(_ total: Decimal, _ chainName: String, _ date: Date) -> ReceiptCapture {
        ReceiptCapture(
            capturedAt: date,
            purchaseDate: date,
            storeChainNameSnapshot: chainName,
            total: total,
            rawText: marker,
            reviewState: .reviewed
        )
    }

    private static func day(_ day: Int, in monthStart: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
    }

    // MARK: - Fetch

    private static func fetchSeededExpenses(in context: ModelContext) throws -> [ExpenseEntry] {
        let marker = marker
        return try context.fetch(
            FetchDescriptor<ExpenseEntry>(predicate: #Predicate { $0.note == marker })
        )
    }

    private static func fetchSeededIncome(in context: ModelContext) throws -> [IncomeEntry] {
        let incomeLabel = incomeLabel
        return try context.fetch(
            FetchDescriptor<IncomeEntry>(predicate: #Predicate { $0.label == incomeLabel })
        )
    }

    private static func fetchSeededReceipts(in context: ModelContext) throws -> [ReceiptCapture] {
        let marker = marker
        return try context.fetch(
            FetchDescriptor<ReceiptCapture>(predicate: #Predicate { $0.rawText == marker })
        )
    }
}
#endif
