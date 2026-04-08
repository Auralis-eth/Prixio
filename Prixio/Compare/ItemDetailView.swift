import CoreLocation
import SwiftData
import SwiftUI

struct ItemDetailView: View {
    let itemKey: String
    let displayName: String
    let userLocation: CLLocation?

    @Environment(\.modelContext) private var modelContext
    @Query private var itemEntries: [PriceEntry]

    @StateObject private var viewModel = CompareViewModel()
    @State private var mode: CompareDisplayMode = .perUnit
    @State private var comparisonState = CompareViewModel.ItemComparisonState(rows: [], showsMixedUnitFamilyNote: false)
    @State private var selectedEntry: PriceEntry?

    init(itemKey: String, displayName: String, userLocation: CLLocation?) {
        self.itemKey = itemKey
        self.displayName = displayName
        self.userLocation = userLocation
        _itemEntries = Query(
            filter: #Predicate<PriceEntry> { entry in
                entry.itemNameNormalized == itemKey
            },
            sort: \PriceEntry.capturedAt,
            order: .reverse
        )
    }

    var body: some View {
        List {
            headerSection

            if comparisonState.showsMixedUnitFamilyNote {
                Section {
                    Text("Some entries use different unit families. Showing the dominant family first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Stores") {
                if comparisonState.rows.isEmpty {
                    ContentUnavailableView(
                        "No Comparable Prices",
                        systemImage: "basket",
                        description: Text("Switch modes or scan another price for this item.")
                    )
                } else {
                    ForEach(comparisonState.rows) { row in
                        Button {
                            selectedEntry = itemEntries.first { $0.id == row.bestEntryID }
                        } label: {
                            StoreRowView(row: row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: recompute)
        .onChange(of: itemEntries.count) { _, _ in
            recompute()
        }
        .onChange(of: mode) { _, _ in
            recompute()
        }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailSheet(entry: entry) {
                delete(entry: entry)
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Display mode", selection: $mode) {
                    Text("Per unit").tag(CompareDisplayMode.perUnit)
                    Text("Per package").tag(CompareDisplayMode.perPackage)
                }
                .pickerStyle(.segmented)

                Text("\(itemEntries.count) captures tracked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func recompute() {
        comparisonState = viewModel.buildItemComparisonState(
            itemKey: itemKey,
            entries: itemEntries,
            mode: mode,
            userLocation: userLocation
        )

        if mode == .perUnit, comparisonState.rows.isEmpty {
            mode = .perPackage
        }
    }

    private func delete(entry: PriceEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }
}
