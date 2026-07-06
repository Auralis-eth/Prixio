import SwiftUI

/// Intentionally simple manual-expense entry. The goal is fast capture for household context, not
/// full accounting.
struct AddExpenseSheet: View {
    let onAdd: (_ amount: Decimal, _ category: ExpenseCategory, _ merchant: String?, _ note: String?, _ date: Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Decimal = 0
    @State private var category: ExpenseCategory = .groceries
    @State private var merchant: String = ""
    @State private var note: String = ""
    @State private var date: Date = .now
    /// Once the user picks a category themselves, suggestions stop entirely — a
    /// manual choice is never overridden.
    @State private var userPickedCategory = false
    /// Whether the current selection came from the suggester (drives the caption).
    @State private var suggestionApplied = false
    /// Distinguishes the suggester's programmatic picker write from a user pick in
    /// `onChange(of: category)`.
    @State private var applyingSuggestion = false

    private let categorySuggester: any ExpenseCategorySuggesting = ExpenseCategorySuggester()

    private var canSave: Bool {
        amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                    if suggestionApplied {
                        Text("Category suggested from the merchant — adjust if it's wrong.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Merchant (optional)", text: $merchant)
                    TextField("Note (optional)", text: $note)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: category) {
                if applyingSuggestion {
                    applyingSuggestion = false
                } else {
                    userPickedCategory = true
                    suggestionApplied = false
                }
            }
            // Re-runs (cancelling the previous pass) on every merchant keystroke;
            // the sleep debounces so only a typing pause reaches the suggester.
            .task(id: merchant) {
                guard !userPickedCategory, !merchant.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                let trimmedNote = note.trimmingCharacters(in: .whitespaces)
                guard let suggestion = await categorySuggester.suggestCategory(
                    merchant: merchant,
                    note: trimmedNote.isEmpty ? nil : trimmedNote
                ) else { return }
                // Re-check: the user may have picked while the model was thinking.
                guard !userPickedCategory, suggestion != category else { return }
                applyingSuggestion = true
                category = suggestion
                suggestionApplied = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onAdd(
                            amount,
                            category,
                            merchant.isEmpty ? nil : merchant,
                            note.isEmpty ? nil : note,
                            date
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
