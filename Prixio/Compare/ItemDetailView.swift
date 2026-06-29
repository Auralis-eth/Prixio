import CoreLocation
import SwiftData
import SwiftUI

struct ItemDetailView: View {
    let itemKey: String
    let displayName: String
    let userLocation: CLLocation?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PriceEntry.capturedAt, order: .reverse) private var allEntries: [PriceEntry]
    @Query(sort: \FlyerPriceRecord.savedAt, order: .reverse) private var allFlyerRecords: [FlyerPriceRecord]

    /// Entries that satisfy this item. A generic name (e.g. "sour cream") rolls up more-specific
    /// scanned products (e.g. "Daisy Sour Cream") via `ItemKeyNormalizer.matches`. Filtered in memory
    /// because the token-subset match can't be expressed as a SwiftData `#Predicate`.
    private var itemEntries: [PriceEntry] {
        allEntries.filter {
            ItemKeyNormalizer.matches(queryKey: itemKey, entryKey: $0.itemNameNormalized)
        }
    }

    @StateObject private var viewModel = CompareViewModel()
    @State private var mode: CompareDisplayMode = .perUnit
    @State private var comparisonState = CompareViewModel.ItemComparisonState(rows: [], showsMixedUnitFamilyNote: false)
    @State private var flyerRows: [CompareViewModel.FlyerComparisonRow] = []
    @State private var history: ItemPriceHistory?
    @State private var historyScope: PriceHistoryScope = .allStores
    @State private var availableScopes: [PriceHistoryScope] = [.allStores]
    @State private var selectedEntry: PriceEntry?

    /// Set when deleting a saved price entry fails to persist, surfaced as an alert. A silently failed
    /// delete would leave the entry hidden here but still feeding price history, basket estimates, and
    /// comparisons.
    @State private var saveErrorMessage: String?

    init(itemKey: String, displayName: String, userLocation: CLLocation?) {
        self.itemKey = itemKey
        self.displayName = displayName
        self.userLocation = userLocation
    }

    var body: some View {
        List {
            headerSection

            if let history {
                priceHistorySection(history)
            }

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

            if !flyerRows.isEmpty {
                Section {
                    ForEach(flyerRows) { row in
                        FlyerComparisonRowView(row: row)
                    }
                } header: {
                    Label("Flyer prices", systemImage: "newspaper")
                } footer: {
                    Text("Advertised flyer prices saved from a recent flyer check. Region and availability may differ from an in-store scan — treat as a guide, not a confirmed price.")
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: recompute)
        .onChange(of: itemEntries.count) { _, _ in
            recompute()
        }
        .onChange(of: allFlyerRecords.count) { _, _ in
            recompute()
        }
        .onChange(of: mode) { _, _ in
            recompute()
        }
        .onChange(of: historyScope) { _, _ in
            recomputeHistory()
        }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailSheet(
                entry: entry,
                onSave: { fields in
                    save(entry: entry, fields: fields)
                },
                onDelete: {
                    delete(entry: entry)
                }
            )
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            ),
            presenting: saveErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
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

    private func priceHistorySection(_ history: ItemPriceHistory) -> some View {
        Section("Price history") {
            if availableScopes.count > 1 {
                Picker("Stores", selection: $historyScope) {
                    ForEach(availableScopes) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .pickerStyle(.menu)
            }

            if history.anomaly != .insufficientData {
                Label(history.anomaly.displayLabel, systemImage: history.anomaly.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(anomalyTint(history.anomaly))
            }

            HStack(spacing: 12) {
                statTile("Latest", value: history.latest.price)
                statTile("Lowest", value: history.lowest.price)
                statTile("Highest", value: history.highest.price)
            }

            if history.hasUsualBand {
                Text("Usual range \(CurrencyFormatter.shared.display(history.usualLow))–\(CurrencyFormatter.shared.display(history.usualHigh)) · \(history.observationCount) prices")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(history.observationCount) price\(history.observationCount == 1 ? "" : "s") so far — need a few more to flag deals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if history.timeline.count >= 2 {
                ItemHistoryChart(history: history)
            }
        }
    }

    private func statTile(_ title: String, value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.shared.display(value))
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func anomalyTint(_ anomaly: PriceAnomaly) -> Color {
        switch anomaly {
        case .likelySale, .belowUsual:
            return .green
        case .nearUsual, .insufficientData:
            return .secondary
        case .aboveUsual:
            return .orange
        case .unusuallyHigh:
            return .red
        }
    }

    private func recompute() {
        comparisonState = viewModel.buildItemComparisonState(
            itemKey: itemKey,
            entries: itemEntries,
            mode: mode,
            userLocation: userLocation
        )

        flyerRows = viewModel.flyerComparisonRows(itemKey: itemKey, records: allFlyerRecords)

        availableScopes = viewModel.availableHistoryScopes(itemKey: itemKey, entries: itemEntries)
        // Reset to the all-stores view if the previously selected scope no longer has data (e.g. its
        // last entry was deleted), so the picker never points at a vanished store.
        if !availableScopes.contains(historyScope) {
            historyScope = .allStores
        }

        recomputeHistory()

        if mode == .perUnit, comparisonState.rows.isEmpty {
            mode = .perPackage
        }
    }

    private func recomputeHistory() {
        history = viewModel.buildItemHistory(
            itemKey: itemKey,
            displayName: displayName,
            entries: itemEntries,
            mode: mode,
            scope: historyScope
        )
    }

    private func save(entry: PriceEntry, fields: EntryDetailSheet.EditedFields) {
        do {
            try PriceEntryRepository(context: modelContext).update(
                entry,
                itemName: fields.itemName,
                brand: fields.brand,
                priceValue: fields.priceValue,
                unitType: fields.unit,
                storeChainName: fields.storeChainName,
                storeLocationName: fields.storeLocationName
            )
            recompute()
        } catch {
            saveErrorMessage = "Couldn’t save your changes. Please try again."
        }
    }

    private func delete(entry: PriceEntry) {
        do {
            try PriceEntryRepository(context: modelContext).delete(entry)
        } catch {
            saveErrorMessage = "Couldn’t delete this price. Please try again."
        }
    }
}

private struct FlyerComparisonRowView: View {
    let row: CompareViewModel.FlyerComparisonRow

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.bannerName)
                    .font(.headline.weight(.semibold))

                Text(row.productName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label("Flyer price", systemImage: "newspaper")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                    if row.memberOnly {
                        Text("· member")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                if let end = row.saleEndDate {
                    Text("Until \(Self.dateFormatter.string(from: end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(CurrencyFormatter.shared.display(row.price))
                    .font(.headline.weight(.semibold))

                if let regular = row.regularPrice {
                    Text(CurrencyFormatter.shared.display(regular))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
            }
        }
        .padding(.vertical, 8)
    }
}
