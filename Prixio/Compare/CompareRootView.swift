import SwiftData
import SwiftUI

struct CompareRootView: View {
    @EnvironmentObject private var navigationModel: AppNavigationModel
    @Query(sort: \PriceEntry.capturedAt, order: .reverse) private var entries: [PriceEntry]
    @Query(sort: \FlyerPriceRecord.savedAt, order: .reverse) private var flyerRecords: [FlyerPriceRecord]

    @StateObject private var viewModel = CompareViewModel()
    @StateObject private var locationManager = LocationManager()
    @State private var searchText = ""

    /// Expired flyer prices are hidden from Compare (they stay in the saved-prices
    /// manager until the deletion sweep), so the empty-state gate must not count them.
    private var activeFlyerRecords: [FlyerPriceRecord] {
        flyerRecords.filter { !$0.isExpired() }
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty && activeFlyerRecords.isEmpty {
                    emptyStateSection
                } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResultsSection
                } else {
                    suggestedSection
                    if !viewModel.recentCaptures.isEmpty {
                        recentCapturesSection
                    }
                    browseSection
                }
            }
            .navigationTitle("Compare")
            .searchable(text: $searchText, prompt: "Find a product...")
        }
        .task {
            locationManager.requestWhenInUseAuthorization()
            recompute()
        }
        .onChange(of: entries.count) { _, _ in
            recompute()
        }
        .onChange(of: flyerRecords.count) { _, _ in
            recompute()
        }
        .onChange(of: searchText) { _, _ in
            recompute()
        }
    }

    private var emptyStateSection: some View {
        Section {
            ContentUnavailableView {
                Label("No prices yet", systemImage: "camera.viewfinder")
            } description: {
                Text("Scan a price tag to start building comparisons.")
            } actions: {
                Button("Scan a price tag") {
                    navigationModel.selectedTab = .scan
                }
            }
        }
    }

    @ViewBuilder
    private var suggestedSection: some View {
        if !viewModel.suggestedCards.isEmpty {
            Section("Suggested Comparisons") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(viewModel.suggestedCards) { card in
                            NavigationLink {
                                ItemDetailView(
                                    itemKey: card.itemKey,
                                    displayName: card.displayName,
                                    userLocation: locationManager.currentLocation
                                )
                            } label: {
                                SuggestedComparisonCard(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
    }

    private var recentCapturesSection: some View {
        Section("Recent Captures") {
            ForEach(Array(viewModel.recentCaptures.prefix(20))) { capture in
                NavigationLink {
                    ItemDetailView(
                        itemKey: capture.itemKey,
                        displayName: capture.displayName,
                        userLocation: locationManager.currentLocation
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(capture.displayName)
                                .font(.headline)
                            Text(capture.storeName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(CurrencyFormatter.shared.display(capture.price))/\(capture.unitLabel)")
                                .font(.subheadline.weight(.semibold))
                            Text(relativeDateLabel(for: capture.capturedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var browseSection: some View {
        Section("Browse") {
            ForEach(viewModel.browseItems) { item in
                NavigationLink {
                    ItemDetailView(
                        itemKey: item.itemKey,
                        displayName: item.displayName,
                        userLocation: locationManager.currentLocation
                    )
                } label: {
                    BrowseItemLabel(item: item)
                }
            }
        }
    }

    private var searchResultsSection: some View {
        Section {
            if viewModel.searchResults.isEmpty {
                ContentUnavailableView(
                    "No matches for \(searchText)",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different product name.")
                )
            } else {
                ForEach(viewModel.searchResults) { item in
                    NavigationLink {
                        ItemDetailView(
                            itemKey: item.itemKey,
                            displayName: item.displayName,
                            userLocation: locationManager.currentLocation
                        )
                    } label: {
                        BrowseItemLabel(item: item)
                    }
                }
            }
        }
    }

    private func recompute() {
        viewModel.recompute(entries: entries, flyerRecords: flyerRecords, query: searchText)
    }

    private func relativeDateLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// A browse/search row label shared by both lists. Flyer-only items (no in-person
/// capture) are labeled "Flyer only" and show their advertised price without a unit.
private struct BrowseItemLabel: View {
    let item: CompareViewModel.BrowseItemRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                if item.isFlyerOnly {
                    Label("Flyer only · \(item.storeCount) banner\(item.storeCount == 1 ? "" : "s")", systemImage: "newspaper")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Text("\(item.storeCount) stores")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let bestPrice = item.bestPrice {
                if let unitLabel = item.bestPriceUnitLabel {
                    Text("\(CurrencyFormatter.shared.display(bestPrice))/\(unitLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.teal)
                } else {
                    Text(CurrencyFormatter.shared.display(bestPrice))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.isFlyerOnly ? .blue : .teal)
                }
            }
        }
    }
}
