import SwiftUI
import SwiftData

struct FlyerProcessingPOCRootView: View {
    @StateObject private var viewModel = FlyerProcessingPOCViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Manual flyer processing POC", systemImage: "newspaper")
                            .font(.headline)

                        Text("Check official Alberta flyer sources on demand, then acquire rendered flyer content for product-price extraction.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await viewModel.checkFlyers()
                            }
                        } label: {
                            if viewModel.isChecking {
                                Label("Checking Flyers", systemImage: "arrow.clockwise")
                            } else {
                                Label("Check Flyers", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isChecking)
                        .accessibilityIdentifier("flyerPOCCheckFlyersButton")

                        Button {
                            Task {
                                await viewModel.acquireContent()
                            }
                        } label: {
                            if viewModel.isAcquiring {
                                Label("Acquiring Content", systemImage: "square.and.arrow.down")
                            } else {
                                Label("Acquire Flyer Content", systemImage: "square.and.arrow.down")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canAcquireContent)
                        .accessibilityIdentifier("flyerPOCAcquireContentButton")

                        Button {
                            Task {
                                await viewModel.extractContent()
                            }
                        } label: {
                            if viewModel.isExtracting {
                                Label("Extracting Candidates", systemImage: "list.bullet.rectangle")
                            } else {
                                Label("Extract Price Candidates", systemImage: "list.bullet.rectangle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canExtractContent)
                        .accessibilityIdentifier("flyerPOCExtractCandidatesButton")

                        Button {
                            viewModel.matchDeals(context: modelContext)
                        } label: {
                            Label("Find Deals for My List", systemImage: "cart.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canMatchDeals)
                        .accessibilityIdentifier("flyerPOCMatchDealsButton")
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text("Official retailer sources only. Brave Search is used only as a fallback when configured. Content is rendered on device with WebKit.")
                }

                Section("POC Status") {
                    HStack(spacing: 12) {
                        if viewModel.isChecking {
                            ProgressView()
                        } else {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }

                        Text(viewModel.statusSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    HStack(spacing: 12) {
                        if viewModel.isAcquiring {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(.secondary)
                        }

                        Text(viewModel.acquisitionSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    HStack(spacing: 12) {
                        if viewModel.isExtracting {
                            ProgressView()
                        } else {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundStyle(.secondary)
                        }

                        Text(viewModel.extractionSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    HStack(spacing: 12) {
                        Image(systemName: "cart")
                            .foregroundStyle(.secondary)

                        Text(viewModel.matchSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                Section("Pipeline Summary") {
                    ForEach(viewModel.pipelineSummary) { stage in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: stage.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stage.stage)
                                    .font(.caption.weight(.semibold))
                                Text(stage.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !viewModel.matchedItemsWithDeals.isEmpty {
                    Section {
                        ForEach(viewModel.matchedItemsWithDeals) { item in
                            FlyerDealMatchRow(
                                item: item,
                                isSaved: { viewModel.isDealSaved($0) },
                                onSave: { viewModel.saveDeal($0, forItemKey: item.itemKey, context: modelContext) }
                            )
                        }
                    } header: {
                        Text(viewModel.matchedAgainstRealList ? "Your List Deals" : "Sample List Deals")
                    } footer: {
                        Text(viewModel.matchedAgainstRealList
                             ? "Matched against your shopping list. Tap + to save a deal as a flyer price."
                             : "Your shopping list is empty, so a sample list was used. Tap + to save a deal as a flyer price.")
                    }
                }

                Section("Alberta Source Catalog") {
                    ForEach(viewModel.results) { result in
                        FlyerDiscoveryResultRow(
                            result: result,
                            acquisition: viewModel.acquisition(for: result.banner),
                            extraction: viewModel.extraction(for: result.banner)
                        )
                    }
                }
            }
            .navigationTitle("Flyer POC")
            .task {
                viewModel.loadSavedDealKeys(context: modelContext)
            }
        }
    }
}

private struct FlyerDiscoveryResultRow: View {
    let result: FlyerDiscoveryResult
    let acquisition: FlyerAcquiredContent?
    let extraction: FlyerExtractionResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary

            if !result.attempts.isEmpty || !result.attemptedQueries.isEmpty {
                DisclosureGroup("Diagnostics (\(result.attempts.count) attempts)") {
                    FlyerDiscoveryDiagnosticsView(result: result)
                }
                .font(.caption)
            }

            if let acquisition {
                FlyerAcquisitionRow(acquisition: acquisition)
            }

            if let extraction {
                FlyerExtractionRowView(extraction: extraction)
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(result.banner.rank)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.banner.name)
                        .font(.headline)

                    Text(result.banner.parentType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Label(result.state.label, systemImage: statusIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)

            Text(result.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let selectedURL = result.selectedURL {
                LabeledContent("Source") {
                    Text(selectedURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let method = result.method {
                LabeledContent("Method", value: method.rawValue)
                    .font(.caption)
            }

            if let sourceShape = result.sourceShape {
                LabeledContent("Source shape", value: sourceShape.label)
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch result.state {
        case .found:
            "checkmark.circle.fill"
        case .needsRenderedExtraction:
            "curlybraces.square"
        case .fallbackUnavailable:
            "key.slash"
        case .unsupported:
            "minus.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch result.state {
        case .found:
            .green
        case .needsRenderedExtraction:
            .blue
        case .fallbackUnavailable:
            .orange
        case .unsupported:
            .secondary
        case .failed:
            .red
        }
    }
}

private struct FlyerDiscoveryDiagnosticsView: View {
    let result: FlyerDiscoveryResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !result.attemptedQueries.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search queries")
                        .font(.caption.weight(.semibold))
                    ForEach(Array(result.attemptedQueries.enumerated()), id: \.offset) { _, query in
                        Text("• \(query)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(Array(result.attempts.enumerated()), id: \.offset) { _, attempt in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(attempt.method.rawValue) — \(attempt.outcome.label)")
                        .font(.caption2.weight(.semibold))
                    Text(attempt.attemptedURL.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let finalURL = attempt.finalURL, finalURL != attempt.attemptedURL {
                        Text("→ \(finalURL.absoluteString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(metaLine(for: attempt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(attempt.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func metaLine(for attempt: FlyerDiscoveryAttempt) -> String {
        var parts: [String] = []
        if let status = attempt.statusCode {
            parts.append("HTTP \(status)")
        }
        if let mime = attempt.mimeType {
            parts.append(mime)
        }
        if let bytes = attempt.byteCount {
            parts.append("\(bytes) bytes")
        }
        if let shape = attempt.sourceShape {
            parts.append(shape.label)
        }
        return parts.isEmpty ? "No response" : parts.joined(separator: " · ")
    }
}

private struct FlyerAcquisitionRow: View {
    let acquisition: FlyerAcquiredContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Content: \(acquisition.state.label)", systemImage: statusIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)

            if let method = acquisition.acquisitionMethod {
                Text("\(method.label) · \(acquisition.priceTokenCount) prices · \(acquisition.payloadByteCount) bytes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(acquisition.message)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let snippet = acquisition.renderedTextSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch acquisition.state {
        case .acquired:
            "tray.and.arrow.down.fill"
        case .acquiredNoPrices:
            "tray"
        case .unsupported:
            "minus.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch acquisition.state {
        case .acquired:
            .green
        case .acquiredNoPrices:
            .orange
        case .unsupported:
            .secondary
        case .failed:
            .red
        }
    }
}

private struct FlyerExtractionRowView: View {
    let extraction: FlyerExtractionResult

    /// Cap on candidates shown inline so a 120-item banner doesn't flood the list.
    private let previewLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Candidates: \(extraction.candidateCount)", systemImage: extraction.candidateCount > 0 ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(extraction.candidateCount > 0 ? Color.green : .orange)

            if extraction.candidateCount > 0 {
                DisclosureGroup("Sample candidates") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(extraction.candidates.prefix(previewLimit))) { candidate in
                            FlyerCandidateLine(candidate: candidate)
                        }
                        if extraction.candidateCount > previewLimit {
                            Text("+ \(extraction.candidateCount - previewLimit) more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 2)
                }
                .font(.caption)
            } else {
                Text(extraction.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

private struct FlyerDealMatchRow: View {
    let item: ShoppingItemFlyerMatches
    let isSaved: (FlyerDeal) -> Bool
    let onSave: (FlyerDeal) -> Void

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
                FlyerDealLine(deal: deal, isSaved: isSaved(deal)) { onSave(deal) }
            }
            if item.deals.count > previewLimit {
                Text("+ \(item.deals.count - previewLimit) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct FlyerDealLine: View {
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

private struct FlyerCandidateLine: View {
    let candidate: FlyerPriceCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(candidate.productName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(CurrencyFormatter.shared.display(candidate.price))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 6) {
                Text(candidate.priceKind.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let regular = candidate.regularPrice {
                    Text("reg \(CurrencyFormatter.shared.display(regular))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let size = candidate.packageSize {
                    Text("· \(size)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if candidate.memberOnly {
                    Text("· member")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
