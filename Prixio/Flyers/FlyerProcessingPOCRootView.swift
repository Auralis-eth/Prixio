import SwiftUI

struct FlyerProcessingPOCRootView: View {
    @StateObject private var viewModel = FlyerProcessingPOCViewModel()

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
                }

                Section("Alberta Source Catalog") {
                    ForEach(viewModel.results) { result in
                        FlyerDiscoveryResultRow(
                            result: result,
                            acquisition: viewModel.acquisition(for: result.banner)
                        )
                    }
                }
            }
            .navigationTitle("Flyer POC")
        }
    }
}

private struct FlyerDiscoveryResultRow: View {
    let result: FlyerDiscoveryResult
    let acquisition: FlyerAcquiredContent?

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
