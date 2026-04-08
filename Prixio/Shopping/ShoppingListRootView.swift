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
                            TripOptimizerCard(recommendation: viewModel.tripRecommendation)
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
                onAdd: { displayName, quantityNote in
                    addItem(displayName: displayName, quantityNote: quantityNote)
                }
            )
        }
        .sheet(item: $selectedRow) { row in
            ShoppingListItemDetailSheet(
                row: row,
                entries: entries,
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
    }

    private var activeList: ShoppingList? {
        lists.first { !$0.isArchived }
    }

    private var emptyStateSection: some View {
        Section {
            ContentUnavailableView {
                Label("No items yet", systemImage: "checklist")
            } description: {
                Text("Add your first item or jump back into Scan while you shop.")
            } actions: {
                Button("Add your first item") {
                    isShowingAddSheet = true
                }

                Button("Scan items as you shop") {
                    navigationModel.selectedTab = .scan
                }
            }
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

    private func recompute() {
        let items = (activeList?.items ?? []).sorted { $0.createdAt < $1.createdAt }
        viewModel.recompute(items: items, entries: entries, userLocation: nil)
    }

    private func addItem(displayName: String, quantityNote: String?) {
        guard let activeList else {
            return
        }

        try? ShoppingListRepository(context: modelContext).addItem(
            to: activeList,
            displayName: displayName,
            quantityNote: quantityNote
        )
        recompute()
    }

    private func toggleDone(for row: ShoppingListRowData) {
        guard let item = activeList?.items.first(where: { $0.id == row.itemID }) else {
            return
        }

        let newValue = !item.isDone
        _ = try? ShoppingListRepository(context: modelContext).setDone(newValue, for: item)
        recompute()

        if newValue && row.shouldNudgeForFreshness {
            scanNudgeRow = row
        }
    }

    private func deleteRow(_ row: ShoppingListRowData) {
        guard let item = activeList?.items.first(where: { $0.id == row.itemID }) else {
            return
        }

        _ = try? ShoppingListRepository(context: modelContext).deleteItem(item)
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
