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
                    TextField("Merchant (optional)", text: $merchant)
                    TextField("Note (optional)", text: $note)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
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
