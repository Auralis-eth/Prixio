import SwiftUI

struct ShoppingListItemDetailSheet: View {
    let row: ShoppingListRowData
    let entries: [PriceEntry]
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var compareViewModel = CompareViewModel()

    var body: some View {
        NavigationStack {
            List {
                if comparisonRows.isEmpty {
                    ContentUnavailableView(
                        "No prices yet",
                        systemImage: "basket",
                        description: Text("Scan a few store prices to see the best options for this item.")
                    )
                } else {
                    Section("Best Stores") {
                        ForEach(Array(comparisonRows.prefix(3))) { comparisonRow in
                            StoreRowView(row: comparisonRow)
                        }
                    }
                }
            }
            .navigationTitle(row.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
    }

    private var comparisonRows: [StoreComparisonRow] {
        let unitState = compareViewModel.buildItemComparisonState(
            itemKey: row.itemKey,
            entries: entries,
            mode: .perUnit,
            userLocation: nil
        )

        if !unitState.rows.isEmpty {
            return unitState.rows
        }

        return compareViewModel.buildItemComparisonState(
            itemKey: row.itemKey,
            entries: entries,
            mode: .perPackage,
            userLocation: nil
        ).rows
    }
}
