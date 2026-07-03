import SwiftData
import SwiftUI

/// The Shopping List's "Check Flyers" sheet: runs the flyer pipeline against the
/// user's active list items and presents matched deals (and similar alternatives)
/// for review. Saving a deal stores it as a labeled flyer price — it never changes
/// basket totals or trusted capture history.
struct FlyerCheckView: View {
    /// Active (not-done) items on the user's list; the check is gated on having some,
    /// so the product surface never falls back to the POC sample list.
    let activeItemCount: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FlyerCheckViewModel()

    var body: some View {
        NavigationStack {
            List {
                if activeItemCount == 0 {
                    emptyListSection
                } else if viewModel.isRunningFullCheck {
                    progressSection
                } else if viewModel.matchState == .completed {
                    resultsSections
                }

                Section {
                    NavigationLink {
                        SavedFlyerPricesView()
                    } label: {
                        Label("Manage saved flyer prices", systemImage: "tray.full")
                    }
                }
            }
            .navigationTitle("Check Flyers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.runFullCheck(context: modelContext)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRunningFullCheck || activeItemCount == 0)
                    .accessibilityLabel("Check again")
                }
            }
            .task {
                viewModel.loadSavedDealKeys(context: modelContext)
                guard activeItemCount > 0, viewModel.matchState != .completed else { return }
                await viewModel.runFullCheck(context: modelContext)
            }
        }
    }

    private var emptyListSection: some View {
        Section {
            ContentUnavailableView(
                "Nothing to check yet",
                systemImage: "checklist",
                description: Text("Add items to your shopping list, then check flyers for deals on them.")
            )
        }
    }

    private var progressSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(viewModel.fullCheckPhaseDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } footer: {
            Text("Checking retailer flyers can take a moment. Not every store publishes a readable flyer.")
        }
    }

    @ViewBuilder
    private var resultsSections: some View {
        let reviewable = viewModel.reviewableItems
        if reviewable.isEmpty {
            Section {
                ContentUnavailableView(
                    "No flyer deals found",
                    systemImage: "newspaper",
                    description: Text("None of this week's readable flyers advertised items on your list. Coverage varies by retailer.")
                )
            }
        } else {
            Section {
                ForEach(reviewable) { item in
                    FlyerCheckItemRow(
                        item: item,
                        alternatives: viewModel.alternatives(forItemKey: item.itemKey),
                        isSaved: { viewModel.isDealSaved($0) },
                        onSaveMatch: { viewModel.saveDeal($0, forItemKey: item.itemKey, context: modelContext) },
                        onSaveAlternative: { viewModel.saveDeal($0, forItemKey: nil, context: modelContext) }
                    )
                }
            } header: {
                Text("Deals for your list")
            } footer: {
                Text("Advertised prices from retailer flyers (\(FlyerStoreContext.defaultAlberta.label)). Availability and in-store prices may differ. Saved deals appear in Compare labeled as flyer prices.")
            }

            let unmatched = viewModel.matches.count - reviewable.count
            if unmatched > 0 {
                Section {
                    Label("No deals found for \(unmatched) other item\(unmatched == 1 ? "" : "s").", systemImage: "minus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One list item's review block: its direct deals, then similar alternatives.
private struct FlyerCheckItemRow: View {
    let item: ShoppingItemFlyerMatches
    let alternatives: ShoppingItemFlyerAlternatives?
    let isSaved: (FlyerDeal) -> Bool
    let onSaveMatch: (FlyerDeal) -> Void
    let onSaveAlternative: (FlyerDeal) -> Void

    /// Cap deals shown inline so a generic item ("milk") that matches many products
    /// doesn't flood the row.
    private let previewLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.displayName.capitalized)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if let best = item.bestDeal {
                    Text("best \(CurrencyFormatter.shared.display(best.candidate.price))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            ForEach(Array(item.deals.prefix(previewLimit))) { deal in
                FlyerCheckDealLine(deal: deal, isSaved: isSaved(deal)) { onSaveMatch(deal) }
            }
            if item.deals.count > previewLimit {
                Text("+ \(item.deals.count - previewLimit) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let alternatives, !alternatives.alternatives.isEmpty {
                Text(item.hasDeals ? "Similar, for less" : "No exact match — similar deals")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(alternatives.alternatives) { deal in
                    FlyerCheckDealLine(deal: deal, isSaved: isSaved(deal)) { onSaveAlternative(deal) }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct FlyerCheckDealLine: View {
    let deal: FlyerDeal
    let isSaved: Bool
    let onSave: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(deal.banner.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                    .lineLimit(1)
                Text(deal.candidate.productName)
                    .font(.caption2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(CurrencyFormatter.shared.display(deal.candidate.price))
                    .font(.caption2.weight(.medium))
                Button(action: onSave) {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(isSaved ? .green : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
                .accessibilityLabel(isSaved ? "Saved" : "Save deal")
            }
            if let provenance = provenanceLine {
                Text(provenance)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Provenance + sale context, for at-a-glance review.
    private var provenanceLine: String? {
        var parts: [String] = []
        if let regular = deal.candidate.regularPrice {
            parts.append("reg \(CurrencyFormatter.shared.display(regular))")
        }
        if let size = deal.candidate.packageSize { parts.append(size) }
        if deal.candidate.memberOnly { parts.append("member") }
        if let end = deal.candidate.saleEndDate {
            parts.append("until \(Self.dateFormatter.string(from: end))")
        }
        parts.append("conf \(Int(deal.candidate.confidence * 100))%")
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
