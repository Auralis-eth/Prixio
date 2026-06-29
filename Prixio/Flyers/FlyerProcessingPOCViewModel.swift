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
    @Published private(set) var acquisitionState: RunState = .idle
    @Published private(set) var acquisitions: [FlyerBannerID: FlyerAcquiredContent] = [:]

    private let coordinator: FlyerDiscoveryCoordinator
    private let acquirer: FlyerContentAcquiring
    private let acquisitionLogger: FlyerAcquisitionLogging

    init(
        coordinator: FlyerDiscoveryCoordinator? = nil,
        acquirer: FlyerContentAcquiring? = nil,
        acquisitionLogger: FlyerAcquisitionLogging? = nil,
        initialResults: [FlyerDiscoveryResult]? = nil
    ) {
        let connectors = FlyerSourceConnectorCatalog.albertaConnectors
        self.coordinator = coordinator ?? FlyerDiscoveryCoordinator(connectors: connectors)
        self.acquirer = acquirer ?? FlyerContentAcquisitionRouter()
        self.acquisitionLogger = acquisitionLogger ?? ConsoleFlyerAcquisitionLogger()
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

    /// Content acquisition can run once discovery has produced source candidates.
    var canAcquireContent: Bool {
        runState == .completed && acquisitionState != .loading
    }

    var isAcquiring: Bool {
        acquisitionState == .loading
    }

    var acquisitionSummary: String {
        switch acquisitionState {
        case .idle:
            "Run a flyer check first, then acquire rendered content for every banner."
        case .loading:
            "Rendering flyer pages and reading prices..."
        case .completed:
            acquisitionCompletedSummary
        }
    }

    func acquisition(for banner: FlyerBanner) -> FlyerAcquiredContent? {
        acquisitions[banner.id]
    }

    func checkFlyers() async {
        guard runState != .loading else {
            return
        }

        runState = .loading
        // A fresh discovery pass invalidates any prior acquisition.
        acquisitions = [:]
        acquisitionState = .idle
        let discoveredResults = await coordinator.discoverSources()
        results = discoveredResults.sorted { $0.banner.rank < $1.banner.rank }
        runState = .completed
    }

    /// Acquires real flyer content for every supported banner using its
    /// discovered source URL. Unsupported connectors and banners without a source
    /// URL are recorded explicitly rather than skipped silently.
    func acquireContent() async {
        guard runState == .completed, acquisitionState != .loading else {
            return
        }

        acquisitionState = .loading
        acquisitionLogger.log("phase=run-start banners=\(results.count)")
        var output: [FlyerBannerID: FlyerAcquiredContent] = [:]
        for result in results {
            let content: FlyerAcquiredContent
            switch result.state {
            case .unsupported:
                content = .unsupported(banner: result.banner, reason: result.message)
            default:
                if let url = result.selectedURL {
                    content = await acquirer.acquire(
                        banner: result.banner,
                        from: url,
                        sourceShape: result.sourceShape,
                        storeContext: nil
                    )
                } else {
                    content = .missingSource(banner: result.banner)
                }
            }

            output[result.banner.id] = content
            // Publish progressively so each banner's result appears as it lands.
            acquisitions = output
        }

        let tally = output.values.reduce(into: [FlyerAcquisitionState: Int]()) { counts, content in
            counts[content.state, default: 0] += 1
        }
        acquisitionLogger.log("phase=run-finish total=\(output.count) acquired=\(tally[.acquired, default: 0]) noPrices=\(tally[.acquiredNoPrices, default: 0]) unsupported=\(tally[.unsupported, default: 0]) failed=\(tally[.failed, default: 0])")
        acquisitionState = .completed
    }

    private var completedSummary: String {
        let foundCount = results.filter { $0.state == .found }.count
        let renderedCount = results.filter { $0.state == .needsRenderedExtraction }.count
        let totalCount = results.count
        if renderedCount > 0 {
            return "Found extractable sources for \(foundCount) of \(totalCount) banners; \(renderedCount) need rendered extraction."
        }

        return "Found extractable official sources for \(foundCount) of \(totalCount) banners."
    }

    private var acquisitionCompletedSummary: String {
        let values = acquisitions.values
        let acquiredCount = values.filter { $0.state == .acquired }.count
        let noPriceCount = values.filter { $0.state == .acquiredNoPrices }.count
        let totalCount = values.count
        if noPriceCount > 0 {
            return "Acquired flyer content for \(acquiredCount) of \(totalCount) banners; \(noPriceCount) had no readable prices yet."
        }

        return "Acquired flyer content for \(acquiredCount) of \(totalCount) banners."
    }
}
