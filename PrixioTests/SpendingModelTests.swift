import Foundation
import SwiftData
import Testing
@testable import Prixio

@Suite(.serialized)
@MainActor
struct SpendingModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ExpenseEntry.self, IncomeEntry.self, RecurringExpenseRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test
    func persistsExpenseWithTypedCategory() throws {
        let context = try makeContext()
        let expense = ExpenseEntry(
            amount: Decimal(string: "42.50")!,
            category: .utilities,
            merchant: "Hydro One"
        )
        context.insert(expense)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ExpenseEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.category == .utilities)
        #expect(fetched.first?.amount == Decimal(string: "42.50"))
        #expect(fetched.first?.merchant == "Hydro One")
    }

    @Test
    func persistsIncome() throws {
        let context = try makeContext()
        context.insert(IncomeEntry(amount: Decimal(string: "2000")!, label: "Paycheck"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<IncomeEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.label == "Paycheck")
        #expect(fetched.first?.amount == Decimal(string: "2000"))
    }

    @Test
    func persistsRecurringRuleWithTypedCadenceAndStatus() throws {
        let context = try makeContext()
        let rule = RecurringExpenseRule(
            matchKey: "merchant:netflix",
            displayLabel: "Netflix",
            cadence: .monthly,
            expectedAmount: Decimal(string: "15.99")!,
            status: .confirmed
        )
        context.insert(rule)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RecurringExpenseRule>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.cadence == .monthly)
        #expect(fetched.first?.status == .confirmed)
        #expect(fetched.first?.expectedAmount == Decimal(string: "15.99"))
    }

    @Test
    func confirmingRuleTagsMatchingExpensesAndDeleteClearsThem() throws {
        let context = try makeContext()
        let netflix = ExpenseEntry(amount: Decimal(string: "15")!, category: .subscriptions, merchant: "Netflix")
        let other = ExpenseEntry(amount: Decimal(string: "40")!, category: .groceries, merchant: "Grocer")
        context.insert(netflix)
        context.insert(other)
        try context.save()

        let suggestion = RecurringSuggestion(
            matchKey: "merchant:netflix",
            displayLabel: "Netflix",
            cadence: .monthly,
            occurrenceCount: 3,
            averageAmount: Decimal(string: "15")!
        )

        let repository = RecurringExpenseRepository(context: context)
        let rule = try repository.resolve(
            suggestion: suggestion,
            status: .confirmed,
            expenses: [netflix, other]
        )

        // Only the matching expense is tagged with the confirmed rule.
        #expect(netflix.recurringRuleID == rule.id)
        #expect(other.recurringRuleID == nil)

        // Deleting the rule clears the back-link and removes the rule.
        try repository.delete(rule, expenses: [netflix, other])
        #expect(netflix.recurringRuleID == nil)
        #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).isEmpty)
    }

    @Test
    func refreshUpdatesConfirmedRuleExpectedAmountAndLastMatched() throws {
        let context = try makeContext()
        let early = ExpenseEntry(date: Date(timeIntervalSince1970: 1_000_000), amount: Decimal(string: "10")!, category: .subscriptions, merchant: "Spotify")
        context.insert(early)
        try context.save()

        let repository = RecurringExpenseRepository(context: context)
        let rule = try repository.resolve(
            suggestion: RecurringSuggestion(
                matchKey: "merchant:spotify",
                displayLabel: "Spotify",
                cadence: .monthly,
                occurrenceCount: 1,
                averageAmount: Decimal(string: "10")!
            ),
            status: .confirmed,
            expenses: [early]
        )
        #expect(rule.expectedAmount == Decimal(string: "10"))

        // A newer, higher matching expense should pull the expected amount toward the new mean and
        // advance the last-matched date.
        let laterDate = Date(timeIntervalSince1970: 2_000_000)
        let later = ExpenseEntry(date: laterDate, amount: Decimal(string: "20")!, category: .subscriptions, merchant: "Spotify")
        context.insert(later)
        try context.save()

        try repository.refreshConfirmedRules([rule], expenses: [early, later])

        #expect(rule.expectedAmount == Decimal(string: "15")) // mean of 10 and 20
        #expect(rule.lastMatchedAt == laterDate)
    }
}
