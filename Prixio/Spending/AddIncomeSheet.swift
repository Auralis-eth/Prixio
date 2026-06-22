import SwiftUI

/// Optional household income declaration. Household-level only for the first version.
struct AddIncomeSheet: View {
    let onAdd: (_ amount: Decimal, _ label: String, _ date: Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Decimal = 0
    @State private var label: String = ""
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
                    TextField("Label (e.g. Paycheck)", text: $label)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onAdd(amount, label, date)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
