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
    @FocusState private var isItemNameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Item") {
                    TextField("Add an item", text: $itemName)
                        .textInputAutocapitalization(.words)
                        .focused($isItemNameFocused)
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
