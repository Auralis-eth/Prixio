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

                        Text("Check official Alberta flyer sources on demand, then use the results as the entry point for future product-price extraction.")
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
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text("Official retailer sources only. Brave Search is used only as a fallback when configured.")
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
                }

                Section("Alberta Source Catalog") {
                    ForEach(viewModel.results) { result in
                        FlyerDiscoveryResultRow(result: result)
                    }
                }
            }
            .navigationTitle("Flyer POC")
        }
    }
}

private struct FlyerDiscoveryResultRow: View {
    let result: FlyerDiscoveryResult

    var body: some View {
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
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch result.state {
        case .found:
            "checkmark.circle.fill"
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
        case .fallbackUnavailable:
            .orange
        case .unsupported:
            .secondary
        case .failed:
            .red
        }
    }
}
