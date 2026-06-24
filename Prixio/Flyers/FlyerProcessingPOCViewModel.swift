import Combine
import Foundation

@MainActor
final class FlyerProcessingPOCViewModel: ObservableObject {
    enum RunState: Equatable {
        case idle
        case loading
        case completed
    }

    @Published private(set) var runState: RunState = .idle
    @Published private(set) var results: [FlyerDiscoveryResult]

    private let coordinator: FlyerDiscoveryCoordinator

    init(
        coordinator: FlyerDiscoveryCoordinator? = nil,
        initialResults: [FlyerDiscoveryResult]? = nil
    ) {
        let connectors = FlyerSourceConnectorCatalog.albertaConnectors
        self.coordinator = coordinator ?? FlyerDiscoveryCoordinator(connectors: connectors)
        self.results = (initialResults ?? connectors.map {
            FlyerDiscoveryResult(
                banner: $0.banner,
                state: .failed,
                selectedURL: nil,
                method: nil,
                message: "Not checked yet."
            )
        }).sorted { $0.banner.rank < $1.banner.rank }
    }

    var statusSummary: String {
        switch runState {
        case .idle:
            "Ready to check official Alberta flyer sources."
        case .loading:
            "Checking official retailer flyer sources..."
        case .completed:
            completedSummary
        }
    }

    var isChecking: Bool {
        runState == .loading
    }

    func checkFlyers() async {
        guard runState != .loading else {
            return
        }

        runState = .loading
        let discoveredResults = await coordinator.discoverSources()
        results = discoveredResults.sorted { $0.banner.rank < $1.banner.rank }
        runState = .completed
    }

    private var completedSummary: String {
        let foundCount = results.filter { $0.state == .found }.count
        let totalCount = results.count
        return "Found official sources for \(foundCount) of \(totalCount) banners."
    }
}
