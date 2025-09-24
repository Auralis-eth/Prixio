import SwiftUI
import CoreLocation
import SwiftData

struct StoreDetectionView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext

    @State private var candidates: [DetectedCandidate] = []
    @State private var best: DetectedCandidate? = nil
    @State private var isLoading: Bool = true
    @State private var errorText: String? = nil

    var body: some View {
        List {
            if let best {
                Section("Best Match") {
                    CandidateRow(candidate: best)
                        .accessibilityIdentifier("bestCandidateRow")
                }
            }

            Section("All Candidates") {
                if candidates.isEmpty {
                    Text("No candidates found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates, id: \.id) { candidate in
                        CandidateRow(candidate: candidate)
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Detecting nearby store…")
            }
        }
        .navigationTitle("Detect Nearby Store")
        .task { await runDetection() }
        .refreshable { await runDetection(force: true) }
        .alert("Detection Error", isPresented: .constant(errorText != nil), actions: {
            Button("OK", role: .cancel) { errorText = nil }
        }, message: {
            Text(errorText ?? "Unknown error")
        })
    }

    private func runDetection(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        guard let svc = appCoordinator.getService(for: .location) as? LocationService else {
            errorText = "Location service unavailable"
            return
        }
        let result = await svc.detectNearbyStore(using: modelContext)
        self.best = result.best
        self.candidates = result.candidates.sorted { $0.score > $1.score }
    }
}

private struct CandidateRow: View {
    let candidate: DetectedCandidate

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.name)
                    .font(.headline)
                Text(candidate.source.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.0f%%", candidate.score * 100))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView {
        StoreDetectionView()
            .environmentObject(AppCoordinator())
    }
}
