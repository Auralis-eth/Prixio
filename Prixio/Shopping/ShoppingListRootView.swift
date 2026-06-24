import SwiftData
import SwiftUI

struct ShoppingListRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationModel: AppNavigationModel
    @Query(sort: \ShoppingList.updatedAt, order: .reverse) private var lists: [ShoppingList]
    @Query(sort: \PriceEntry.capturedAt, order: .reverse) private var entries: [PriceEntry]

    @StateObject private var viewModel = ShoppingListViewModel()
    @State private var isShowingAddSheet = false
    @State private var isShowingCompleted = false
    @State private var selectedRow: ShoppingListRowData?
    @State private var scanNudgeRow: ShoppingListRowData?

    /// Set when a list mutation fails to persist, surfaced as an alert so an add/toggle/delete that
    /// didn't actually save can't look like it worked.
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let activeList {
                    if activeList.items.isEmpty {
                        emptyStateSection
                    } else if viewModel.activeRows.isEmpty && !viewModel.completedRows.isEmpty {
                        completedOnlySection
                    } else {
                        Section {
                            TripOptimizerCard(
                                recommendation: viewModel.tripRecommendation,
                                basket: viewModel.basketEstimate
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        }

                        Section("Checklist") {
                            ForEach(viewModel.activeRows) { row in
                                ShoppingListRowView(
                                    row: row,
                                    onToggleDone: {
                                        toggleDone(for: row)
                                    },
                                    onOpenDetail: {
                                        selectedRow = row
                                    }
                                )
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        deleteRow(row)
                                    }
                                }
                            }
                        }

                        completedSection
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Shopping List")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            _ = try? ShoppingListRepository(context: modelContext).fetchOrCreateDefaultList()
            recompute()
        }
        .onChange(of: entries.count) { _, _ in
            recompute()
        }
        .onChange(of: lists.count) { _, _ in
            recompute()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddShoppingListItemSheet(
                suggestions: knownItemSuggestions,
                onAdd: { displayName, brand, quantityNote in
                    addItem(displayName: displayName, brand: brand, quantityNote: quantityNote)
                }
            )
        }
        .sheet(item: $selectedRow) { row in
            ShoppingListItemDetailSheet(
                row: row,
                entries: entries,
                onScanNow: {
                    launchScan(for: row)
                },
                onDelete: {
                    deleteRow(row)
                }
            )
        }
        .sheet(item: $scanNudgeRow) { row in
            ScanNudgeSheet(
                itemName: row.displayName,
                onScanNow: {
                    launchScan(for: row)
                    scanNudgeRow = nil
                },
                onDismiss: {
                    scanNudgeRow = nil
                }
            )
        }
        .alert(
            "Couldn’t Save",
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

    private var activeList: ShoppingList? {
        lists.first {
            !$0.isArchived && $0.name == ShoppingListRepository.defaultListName
        } ?? lists.first { !$0.isArchived }
    }

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "checklist")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text("No items yet")
                    .font(.headline)

                Text("Add your first item or jump back into Scan while you shop.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Button("Add your first item") {
                        showAddItemSheet()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("shoppingEmptyAddItemButton")

                    Button("Scan items as you shop") {
                        startScanningFromEmptyState()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("shoppingEmptyScanButton")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private var completedOnlySection: some View {
        Section {
            ContentUnavailableView(
                "All done! Great trip.",
                systemImage: "checkmark.circle",
                description: Text("You’ve completed every item on this list.")
            )
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if !viewModel.completedRows.isEmpty {
            Section {
                DisclosureGroup(
                    "Completed (\(viewModel.completedRows.count))",
                    isExpanded: $isShowingCompleted
                ) {
                    ForEach(viewModel.completedRows) { row in
                        ShoppingListRowView(
                            row: row,
                            onToggleDone: {
                                toggleDone(for: row)
                            },
                            onOpenDetail: {
                                selectedRow = row
                            }
                        )
                    }
                }
            }
        }
    }

    private var knownItemSuggestions: [AddShoppingListItemSheet.KnownItemSuggestion] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard !seen.contains(entry.itemNameNormalized) else {
                return nil
            }
            seen.insert(entry.itemNameNormalized)
            return AddShoppingListItemSheet.KnownItemSuggestion(
                itemKey: entry.itemNameNormalized,
                displayName: entry.itemNameRaw
            )
        }
    }

    private func showAddItemSheet() {
        // Stay on the Shopping tab; a defensive no-op that guards against any stray navigation.
        navigationModel.selectedTab = .shopping
        isShowingAddSheet = true
    }

    private func startScanningFromEmptyState() {
        // Clear any stale modal state before navigating so the add sheet cannot survive into the
        // next visit to this tab, regardless of how the tap was routed.
        isShowingAddSheet = false
        navigationModel.selectedTab = .scan
    }

    private func recompute() {
        let items = (activeList?.items ?? []).sorted { $0.createdAt < $1.createdAt }
        viewModel.recompute(items: items, entries: entries, userLocation: nil)
    }

    private func addItem(displayName: String, brand: String?, quantityNote: String?) {
        guard let activeList else {
            return
        }

        do {
            _ = try ShoppingListRepository(context: modelContext).addItem(
                to: activeList,
                displayName: displayName,
                brand: brand,
                quantityNote: quantityNote
            )
        } catch {
            saveErrorMessage = "Couldn’t add this item. Please try again."
        }
        recompute()
    }

    private func toggleDone(for row: ShoppingListRowData) {
        guard let item = activeList?.items.first(where: { $0.id == row.itemID }) else {
            return
        }

        let newValue = !item.isDone
        do {
            try ShoppingListRepository(context: modelContext).setDone(newValue, for: item)
        } catch {
            saveErrorMessage = "Couldn’t update this item. Please try again."
            recompute()
            return
        }
        recompute()

        if newValue && row.shouldNudgeForFreshness {
            scanNudgeRow = row
        }
    }

    private func deleteRow(_ row: ShoppingListRowData) {
        guard let item = activeList?.items.first(where: { $0.id == row.itemID }) else {
            return
        }

        do {
            try ShoppingListRepository(context: modelContext).deleteItem(item)
        } catch {
            saveErrorMessage = "Couldn’t delete this item. Please try again."
        }
        recompute()
    }

    private func launchScan(for row: ShoppingListRowData) {
        navigationModel.launchScan(
            itemName: row.displayName,
            preferredChainName: preferredChainName(for: row)
        )
    }

    private func preferredChainName(for row: ShoppingListRowData) -> String? {
        if let bestStoreName = row.bestStoreName {
            return bestStoreName
        }

        switch viewModel.tripRecommendation {
        case .strongWinner(_, let chainName, _, _, _):
            return chainName
        case .splitTrip(_, let primaryChainName, _, _, _, _, _):
            return primaryChainName
        case .insufficientData:
            return nil
        }
    }
}
