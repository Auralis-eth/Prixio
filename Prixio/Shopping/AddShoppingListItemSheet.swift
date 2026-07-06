import SwiftUI

struct AddShoppingListItemSheet: View {
    struct KnownItemSuggestion: Identifiable {
        let itemKey: String
        let displayName: String

        var id: String {
            itemKey
        }
    }

    let suggestions: [KnownItemSuggestion]
    let onAdd: (_ displayName: String, _ brand: String?, _ quantityNote: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemName = ""
    @State private var brand = ""
    @State private var quantityNote = ""
    /// Whether the current field values came from the entry parser's split (drives
    /// the caption under the item field).
    @State private var entrySplitApplied = false
    @FocusState private var isItemNameFocused: Bool

    private let entryParser: any ShoppingListEntryParsing = ShoppingListEntryParser()

    var body: some View {
        NavigationStack {
            List {
                Section("Item") {
                    TextField("Add an item", text: $itemName)
                        .textInputAutocapitalization(.words)
                        .focused($isItemNameFocused)
                    if entrySplitApplied {
                        Text("Split into item, brand, and quantity — adjust anything that's wrong.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Brand") {
                    TextField("Optional, e.g. PC, Compliments", text: $brand)
                        .textInputAutocapitalization(.words)
                }

                Section("Quantity Note") {
                    TextField("Optional, e.g. 2 kg", text: $quantityNote)
                        .textInputAutocapitalization(.never)
                }

                if !filteredSuggestions.isEmpty {
                    Section("Known Items") {
                        ForEach(filteredSuggestions) { suggestion in
                            Button(suggestion.displayName) {
                                itemName = suggestion.displayName
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let trimmedQuantity = quantityNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAdd(
                            itemName.trimmingCharacters(in: .whitespacesAndNewlines),
                            trimmedBrand.isEmpty ? nil : trimmedBrand,
                            trimmedQuantity.isEmpty ? nil : trimmedQuantity
                        )
                        dismiss()
                    }
                    .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .accessibilityIdentifier("addItemSheet")
        .onAppear {
            isItemNameFocused = true
        }
        // Re-runs (cancelling the previous pass) on every keystroke; the sleep
        // debounces so only a typing pause reaches the parser. The split only ever
        // fills *empty* brand/quantity fields — anything the user typed there stays —
        // and the result lands in the visible form, so tapping Add confirms it.
        .task(id: itemName) {
            guard brand.isEmpty, quantityNote.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            guard let parsed = await entryParser.parse(itemName) else { return }
            guard brand.isEmpty, quantityNote.isEmpty else { return }
            itemName = parsed.itemName.localizedCapitalized
            brand = parsed.brand ?? ""
            quantityNote = parsed.quantityNote ?? ""
            entrySplitApplied = true
        }
    }

    private var filteredSuggestions: [KnownItemSuggestion] {
        let normalizedQuery = ItemKeyNormalizer.normalize(itemName)
        guard !normalizedQuery.isEmpty else {
            return Array(suggestions.prefix(8))
        }

        return suggestions.filter { suggestion in
            suggestion.itemKey.contains(normalizedQuery) ||
            suggestion.displayName.lowercased().contains(normalizedQuery)
        }
        .prefix(8)
        .map { $0 }
    }
}
