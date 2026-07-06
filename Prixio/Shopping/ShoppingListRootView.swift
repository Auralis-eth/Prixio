import SwiftData
import SwiftUI

struct ShoppingListRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationModel: AppNavigationModel
    @Query(sort: \ShoppingList.updatedAt, order: .reverse) private var lists: [ShoppingList]
    @Query(sort: \PriceEntry.capturedAt, order: .reverse) private var entries: [PriceEntry]
    @Query(sort: \FlyerPriceRecord.savedAt, order: .reverse) private var flyerRecords: [FlyerPriceRecord]
    @Query(sort: \ReceiptCapture.capturedAt, order: .reverse) private var receipts: [ReceiptCapture]
    @Query private var restockRules: [RestockRule]

    @StateObject private var viewModel = ShoppingListViewModel()
    @State private var isShowingAddSheet = false
    @State private var isShowingFlyerCheck = false
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
                                basket: viewModel.basketEstimate,
                                explanation: viewModel.tripExplanation
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        }

                        // Advisory only: flyer deals never change the basket totals.
                        // Tapping it opens the Check Flyers sheet for the full review.
                        if let advisory = viewModel.flyerAdvisory {
                            Section {
                                Button {
                                    isShowingFlyerCheck = true
                                } label: {
                                    Label {
                                        Text(advisory.message)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "newspaper")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            } footer: {
                                Text("Advertised flyer prices — not included in estimates and may differ in store.")
                            }
                        }

                        buyAheadSection

                        restockSection

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

                        suggestionSection

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
                        isShowingFlyerCheck = true
                    } label: {
                        Image(systemName: "newspaper")
                    }
                    .accessibilityLabel("Check Flyers")
                    .accessibilityIdentifier("shoppingCheckFlyersButton")
                }
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
        // Content fingerprint, not count: a receipt flipping to "reviewed" or a rule
        // flipping to "dismissed" changes no counts but must refresh the restock
        // section (same reasoning as `flyerRecordsFingerprint`).
        .onChange(of: restockInputsFingerprint) { _, _ in
            recompute()
        }
        .onChange(of: lists.count) { _, _ in
            recompute()
        }
        // Content fingerprint, not count: an in-place record edit (idempotent re-save
        // with a new price or sale window) must refresh the advisory too.
        .onChange(of: flyerRecordsFingerprint) { _, _ in
            recompute()
        }
        // Recompute when the next flyer deal expires while the view is open, so the
        // advisory can't keep advertising a sale that has ended. Re-arms itself: the
        // recompute re-evaluates body, which recomputes the next boundary.
        .task(id: nextFlyerExpiry) {
            guard let nextFlyerExpiry else { return }
            let interval = nextFlyerExpiry.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            guard !Task.isCancelled else { return }
            recompute()
        }
        .sheet(isPresented: $isShowingFlyerCheck, onDismiss: recompute) {
            FlyerCheckView(activeItemCount: viewModel.activeRows.count)
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

    /// Hash of every field the flyer advisory reads, so `onChange` fires on in-place
    /// edits (same record count) and not just inserts/deletes.
    private var flyerRecordsFingerprint: Int {
        var hasher = Hasher()
        for record in flyerRecords {
            hasher.combine(record.dealKey)
            hasher.combine(record.priceValue)
            hasher.combine(record.saleEndDate)
            hasher.combine(record.fetchedAt)
        }
        return hasher.finalize()
    }

    /// Hash of every restock-relevant field, so `onChange` fires when a receipt is
    /// reviewed or a rule's status/override changes in place, not just on inserts.
    private var restockInputsFingerprint: Int {
        var hasher = Hasher()
        for receipt in receipts {
            hasher.combine(receipt.id)
            hasher.combine(receipt.reviewStateRaw)
            hasher.combine(receipt.lineItems.count)
        }
        for rule in restockRules {
            hasher.combine(rule.itemKey)
            hasher.combine(rule.statusRaw)
            hasher.combine(rule.overrideIntervalDays)
        }
        return hasher.finalize()
    }

    /// The next moment a currently-active flyer record expires, or nil when none will.
    /// Recomputing at each body evaluation keeps the expiry task aimed at the soonest
    /// upcoming boundary (recompute() always republishes, so body re-evaluates and the
    /// task re-arms after each fire).
    private var nextFlyerExpiry: Date? {
        let now = Date.now
        return flyerRecords.map(\.expiresAt).filter { $0 > now }.min()
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

    /// Buy-ahead advisories from `BuyAheadAdvisor`: the sale on an upcoming need ends
    /// before the household would naturally restock. Advisory pricing only —
    /// adding puts the item on the list, nothing is bought or totalled.
    @ViewBuilder
    private var buyAheadSection: some View {
        if !viewModel.buyAheadAdvisories.isEmpty {
            Section {
                ForEach(viewModel.buyAheadAdvisories) { advisory in
                    HStack(spacing: 12) {
                        Label {
                            Text(advisory.message)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundStyle(.orange)
                        }
                        Spacer(minLength: 8)
                        Button("Add") {
                            addItem(
                                displayName: advisory.displayName,
                                brand: nil,
                                quantityNote: nil
                            )
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Buy ahead")
            } footer: {
                Text("The sale ends before you'd usually restock. Advertised flyer prices — may differ in store.")
            }
        }
    }

    /// Restock nudges from `ConsumptionCadenceEngine`: items the household buys on a
    /// rhythm (per reviewed receipts) that are due or overdue and not on the list.
    /// Add with one tap, or swipe to stop suggesting the item permanently
    /// (a dismissed `RestockRule`). Never added automatically.
    @ViewBuilder
    private var restockSection: some View {
        if !viewModel.restockSuggestions.isEmpty {
            Section {
                ForEach(viewModel.restockSuggestions, id: \.cadence.itemKey) { suggestion in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.cadence.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(restockDetailText(for: suggestion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Add") {
                            addItem(
                                displayName: suggestion.cadence.displayName,
                                brand: nil,
                                quantityNote: nil
                            )
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Don’t Suggest") {
                            dismissRestockSuggestion(suggestion)
                        }
                        .tint(.gray)
                    }
                }
            } header: {
                Text("Probably running low")
            } footer: {
                Text("Based on your receipts — how often you actually buy these. Swipe to stop suggesting an item.")
            }
        }
    }

    private func restockDetailText(for suggestion: ConsumptionCadenceEngine.RestockSuggestion) -> String {
        let interval = Int(suggestion.cadence.medianIntervalDays.rounded())
        let sinceLast = Calendar.current.dateComponents(
            [.day],
            from: suggestion.cadence.lastPurchasedAt,
            to: Calendar.current.startOfDay(for: .now)
        ).day ?? 0

        let lead: String
        switch suggestion.urgency {
        case .probablyOut:
            lead = "Probably out"
        case .dueSoon(let daysRemaining):
            lead = daysRemaining <= 0 ? "Due now" : "Due in \(daysRemaining)d"
        case .stocked:
            lead = "Stocked"
        }
        return "\(lead) · about every \(interval) days · last bought \(sinceLast) days ago"
    }

    private func dismissRestockSuggestion(_ suggestion: ConsumptionCadenceEngine.RestockSuggestion) {
        do {
            try RestockRuleRepository(context: modelContext).dismiss(
                itemKey: suggestion.cadence.itemKey,
                displayName: suggestion.cadence.displayName
            )
        } catch {
            saveErrorMessage = "Couldn’t dismiss this suggestion. Please try again."
        }
        recompute()
    }

    /// Habit nudges from `ListAdditionSuggestionEngine`: add with one tap, or swipe
    /// to dismiss for the session. Never added automatically.
    @ViewBuilder
    private var suggestionSection: some View {
        if !viewModel.listAdditionSuggestions.isEmpty {
            Section {
                ForEach(viewModel.listAdditionSuggestions) { suggestion in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You usually buy \(suggestion.displayName)")
                                .font(.subheadline.weight(.medium))
                            Text("About every \(suggestion.medianIntervalDays) days · last captured \(suggestion.daysSinceLastPurchase) days ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Add") {
                            addItem(displayName: suggestion.displayName, brand: nil, quantityNote: nil)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Dismiss") {
                            viewModel.dismissListAdditionSuggestion(suggestion)
                        }
                        .tint(.gray)
                    }
                }
            } header: {
                Text("Suggested")
            } footer: {
                Text("Based on how regularly you've captured prices for these items.")
            }
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
        viewModel.recompute(
            items: items,
            entries: entries,
            flyerRecords: flyerRecords,
            receipts: receipts,
            restockRules: restockRules,
            userLocation: nil
        )
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
