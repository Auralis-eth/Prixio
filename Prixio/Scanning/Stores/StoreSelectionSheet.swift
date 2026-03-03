
import CoreLocation
import SwiftUI

struct StoreSelectionSheet: View {
    let nearbyCandidates: [StoreCandidate]
    let currentLocation: CLLocation?
    let selectedChainName: String?
    let selectedLocationName: String
    let onSelectCandidate: (StoreCandidate) -> Void
    let onSelectChain: (String) -> Void
    let onSearch: (String) async -> [StoreCandidate]

    @State private var query = ""
    @State private var searchResults: [StoreCandidate] = []

    var body: some View {
        NavigationStack {
            List {
                if !nearbyCandidates.isEmpty {
                    Section("Detected Nearby") {
                        ForEach(Array(nearbyCandidates.prefix(3))) { candidate in
                            Button {
                                onSelectCandidate(candidate)
                            } label: {
                                StoreCandidateRow(
                                    candidate: candidate,
                                    isSelected: candidate.locationName == selectedLocationName
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Choose Chain") {
                    ForEach(StoreCatalog.commonChains.map(\.name), id: \.self) { chain in
                        Button {
                            onSelectChain(chain)
                        } label: {
                            HStack {
                                Text(chain)
                                Spacer()
                                if selectedChainName == chain {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                    }
                }

                Section("Search") {
                    TextField("Search stores", text: $query)
                        .textInputAutocapitalization(.words)
                        .onSubmit {
                            Task {
                                searchResults = await onSearch(query)
                            }
                        }

                    ForEach(searchResults) { candidate in
                        Button {
                            onSelectCandidate(candidate)
                        } label: {
                            StoreCandidateRow(
                                candidate: candidate,
                                isSelected: candidate.locationName == selectedLocationName
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Store")
        }
    }
}

private struct StoreCandidateRow: View {
    let candidate: StoreCandidate
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.chainName ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                Text(candidate.locationName)
                    .font(.callout)
                if let address = candidate.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let distanceMeters = candidate.distanceMeters {
                    Text(distanceMeters.formatted)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.teal)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

