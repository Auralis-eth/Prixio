import Foundation
import SwiftData
import Testing
@testable import Prixio

/// Coverage for the spending persistence layer: `ExpenseRepository`, `IncomeRepository`, and the
/// edge cases of `RecurringExpenseRepository` not already exercised by `SpendingModelTests`. Each
/// test builds its own in-memory `ModelContext` so there is no cross-test pollution.
@Suite(.serialized)
@MainActor
struct SpendingRepositoryTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ExpenseEntry.self, IncomeEntry.self, RecurringExpenseRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func date(_ daysFromEpoch: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(daysFromEpoch) * 86_400)
    }

    // MARK: - ExpenseRepository.add

    @Test
    func expenseAdd_persistsTrimmedMerchantAndNote_givenPaddedInput() throws {
        let repository = ExpenseRepository(context: try makeContext())

        let expense = try repository.add(
            amount: Decimal(string: "42.50")!,
            category: .utilities,
            merchant: "  Hydro One  ",
            note: "  monthly  ",
            date: .now
        )

        #expect(expense.merchant == "Hydro One")
        #expect(expense.note == "monthly")
        #expect(expense.category == .utilities)
        #expect(expense.amount == Decimal(string: "42.50"))
    }

    @Test
    func expenseAdd_storesNil_givenWhitespaceOnlyMerchantAndNote() throws {
        let repository = ExpenseRepository(context: try makeContext())

        let expense = try repository.add(
            amount: Decimal(string: "10")!,
            category: .other,
            merchant: "   ",
            note: "",
            date: .now
        )

        #expect(expense.merchant == nil)
        #expect(expense.note == nil)
    }

    @Test
    func expenseAdd_storesNil_givenNilMerchantAndNote() throws {
        let repository = ExpenseRepository(context: try makeContext())

        let expense = try repository.add(
            amount: Decimal(string: "10")!,
            category: .other,
            merchant: nil,
            note: nil,
            date: .now
        )

        #expect(expense.merchant == nil)
        #expect(expense.note == nil)
    }

    // MARK: - ExpenseRepository.fetchAll / delete

    @Test
    func expenseFetchAll_returnsNewestFirst_givenMixedDates() throws {
        let repository = ExpenseRepository(context: try makeContext())
        try repository.add(amount: 1, category: .other, merchant: nil, note: nil, date: date(10))
        try repository.add(amount: 2, category: .other, merchant: nil, note: nil, date: date(30))
        try repository.add(amount: 3, category: .other, merchant: nil, note: nil, date: date(20))

        let all = try repository.fetchAll()

        #expect(all.map(\.date) == [date(30), date(20), date(10)])
    }

    @Test
    func expenseFetchAll_isEmpty_givenNoExpenses() throws {
        let repository = ExpenseRepository(context: try makeContext())
        #expect(try repository.fetchAll().isEmpty)
    }

    @Test
    func expenseDelete_removesEntry() throws {
        let repository = ExpenseRepository(context: try makeContext())
        let expense = try repository.add(amount: 5, category: .other, merchant: nil, note: nil, date: .now)

        try repository.delete(expense)

        #expect(try repository.fetchAll().isEmpty)
    }

    // MARK: - IncomeRepository.add

    @Test
    func incomeAdd_persistsTrimmedLabel_givenPaddedLabel() throws {
        let repository = IncomeRepository(context: try makeContext())

        let income = try repository.add(amount: Decimal(string: "2000")!, label: "  Paycheck  ", date: .now)

        #expect(income.label == "Paycheck")
        #expect(income.amount == Decimal(string: "2000"))
    }

    @Test
    func incomeAdd_fallsBackToDefaultLabel_givenEmptyLabel() throws {
        let repository = IncomeRepository(context: try makeContext())

        let blank = try repository.add(amount: 1, label: "   ", date: .now)

        #expect(blank.label == "Income")
    }

    @Test
    func incomeFetchAll_returnsNewestFirst_givenMixedDates() throws {
        let repository = IncomeRepository(context: try makeContext())
        try repository.add(amount: 1, label: "A", date: date(5))
        try repository.add(amount: 2, label: "B", date: date(15))

        let all = try repository.fetchAll()

        #expect(all.map(\.date) == [date(15), date(5)])
    }

    @Test
    func incomeDelete_removesEntry() throws {
        let repository = IncomeRepository(context: try makeContext())
        let income = try repository.add(amount: 1, label: "Pay", date: .now)

        try repository.delete(income)

        #expect(try repository.fetchAll().isEmpty)
    }

    // MARK: - RecurringExpenseRepository edge cases

    @Test
    func recurringResolve_doesNotTagExpenses_givenDismissedStatus() throws {
        let context = try makeContext()
        let netflix = ExpenseEntry(amount: Decimal(string: "15")!, category: .subscriptions, merchant: "Netflix")
        context.insert(netflix)
        try context.save()

        let repository = RecurringExpenseRepository(context: context)
        let rule = try repository.resolve(
            suggestion: RecurringSuggestion(
                matchKey: "merchant:netflix",
                displayLabel: "Netflix",
                cadence: .monthly,
                occurrenceCount: 3,
                averageAmount: Decimal(string: "15")!
            ),
            status: .dismissed,
            expenses: [netflix]
        )

        // A dismissed rule suppresses suggestions but must never tag historical expenses, and it
        // does not record a last-matched date.
        #expect(rule.status == .dismissed)
        #expect(rule.lastMatchedAt == nil)
        #expect(netflix.recurringRuleID == nil)
    }

    @Test
    func recurringRefresh_skipsRuleWithoutMatchingExpenses() throws {
        let context = try makeContext()
        let repository = RecurringExpenseRepository(context: context)
        let rule = RecurringExpenseRule(
            matchKey: "merchant:spotify",
            displayLabel: "Spotify",
            cadence: .monthly,
            expectedAmount: Decimal(string: "10")!,
            status: .confirmed,
            lastMatchedAt: date(1)
        )
        context.insert(rule)
        try context.save()

        // No expense matches the rule's key — the figure must stay frozen, not collapse to zero.
        try repository.refreshConfirmedRules([rule], expenses: [])

        #expect(rule.expectedAmount == Decimal(string: "10"))
        #expect(rule.lastMatchedAt == date(1))
    }

    @Test
    func recurringRefresh_skipsNonConfirmedRules() throws {
        let context = try makeContext()
        let repository = RecurringExpenseRepository(context: context)
        let suggested = RecurringExpenseRule(
            matchKey: "merchant:spotify",
            displayLabel: "Spotify",
            expectedAmount: Decimal(string: "10")!,
            status: .suggested
        )
        context.insert(suggested)
        try context.save()
        let match = ExpenseEntry(amount: Decimal(string: "99")!, category: .subscriptions, merchant: "Spotify")

        // Only confirmed rules track reality; a still-suggested rule is left untouched.
        try repository.refreshConfirmedRules([suggested], expenses: [match])

        #expect(suggested.expectedAmount == Decimal(string: "10"))
    }

    @Test
    func recurringDelete_clearsOnlyMatchingBackLinks() throws {
        let context = try makeContext()
        let repository = RecurringExpenseRepository(context: context)
        let rule = RecurringExpenseRule(matchKey: "merchant:netflix", displayLabel: "Netflix", status: .confirmed)
        context.insert(rule)
        try context.save()

        let tagged = ExpenseEntry(amount: 15, category: .subscriptions, merchant: "Netflix", recurringRuleID: rule.id)
        let untagged = ExpenseEntry(amount: 40, category: .groceries, merchant: "Grocer", recurringRuleID: UUID())
        let untaggedOriginalID = untagged.recurringRuleID

        try repository.delete(rule, expenses: [tagged, untagged])

        #expect(tagged.recurringRuleID == nil)
        #expect(untagged.recurringRuleID == untaggedOriginalID) // unrelated link preserved
        #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).isEmpty)
    }

    @Test
    func recurringFetchAll_returnsNewestFirst_givenMixedCreatedAt() throws {
        let context = try makeContext()
        let repository = RecurringExpenseRepository(context: context)
        context.insert(RecurringExpenseRule(createdAt: date(1), matchKey: "a", displayLabel: "A"))
        context.insert(RecurringExpenseRule(createdAt: date(3), matchKey: "b", displayLabel: "B"))
        context.insert(RecurringExpenseRule(createdAt: date(2), matchKey: "c", displayLabel: "C"))
        try context.save()

        let all = try repository.fetchAll()

        #expect(all.map(\.matchKey) == ["b", "c", "a"])
    }
}
