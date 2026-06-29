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
    @Published private(set) var extractionState: RunState = .idle
    @Published private(set) var extractions: [FlyerBannerID: FlyerExtractionResult] = [:]

    private let coordinator: FlyerDiscoveryCoordinator
    private let acquirer: FlyerContentAcquiring
    private let acquisitionLogger: FlyerAcquisitionLogging
    private let extractor: FlyerPriceExtractor
    private let extractionLogger: FlyerAcquisitionLogging

    init(
        coordinator: FlyerDiscoveryCoordinator? = nil,
        acquirer: FlyerContentAcquiring? = nil,
        acquisitionLogger: FlyerAcquisitionLogging? = nil,
        extractor: FlyerPriceExtractor = FlyerPriceExtractor(),
        extractionLogger: FlyerAcquisitionLogging? = nil,
        initialResults: [FlyerDiscoveryResult]? = nil
    ) {
        let connectors = FlyerSourceConnectorCatalog.albertaConnectors
        self.coordinator = coordinator ?? FlyerDiscoveryCoordinator(connectors: connectors)
        self.acquirer = acquirer ?? FlyerContentAcquisitionRouter()
        self.acquisitionLogger = acquisitionLogger ?? ConsoleFlyerAcquisitionLogger()
        self.extractor = extractor
        self.extractionLogger = extractionLogger ?? ConsoleFlyerExtractionLogger()
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
        // A fresh discovery pass invalidates any prior acquisition and extraction.
        acquisitions = [:]
        acquisitionState = .idle
        extractions = [:]
        extractionState = .idle
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
        // Re-acquiring invalidates any prior extraction.
        extractions = [:]
        extractionState = .idle
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

    /// Extraction can run once acquisition has produced content.
    var canExtractContent: Bool {
        acquisitionState == .completed && extractionState != .loading
    }

    var isExtracting: Bool {
        extractionState == .loading
    }

    var extractionSummary: String {
        switch extractionState {
        case .idle:
            "Acquire flyer content first, then extract price candidates from it."
        case .loading:
            "Extracting price candidates from acquired flyer content..."
        case .completed:
            extractionCompletedSummary
        }
    }

    func extraction(for banner: FlyerBanner) -> FlyerExtractionResult? {
        extractions[banner.id]
    }

    /// Extracts structured `FlyerPriceCandidate`s from every banner whose acquired
    /// content carries a payload. Banners that acquired no prices are still run
    /// (their payload may yield a few candidates) so the gap is visible rather than
    /// silently skipped.
    func extractContent() async {
        guard acquisitionState == .completed, extractionState != .loading else {
            return
        }

        extractionState = .loading
        extractionLogger.log("phase=run-start banners=\(acquisitions.count)")
        var output: [FlyerBannerID: FlyerExtractionResult] = [:]
        // Extract in the discovery rank order so the log/UI read consistently.
        for result in results {
            guard let content = acquisitions[result.banner.id] else { continue }
            let label = FlyerAcquisitionLogLabel.make(for: content.banner)
            let extraction = extractor.extract(from: content)
            extractionLogger.log("banner=\(label) method=\(content.acquisitionMethod?.rawValue ?? "none") state=\(content.state.rawValue) candidates=\(extraction.candidateCount)")
            output[result.banner.id] = extraction
            // Publish progressively so each banner's candidates appear as they land.
            extractions = output
        }

        let totalCandidates = output.values.reduce(0) { $0 + $1.candidateCount }
        let bannersWithCandidates = output.values.filter { $0.candidateCount > 0 }.count
        extractionLogger.log("phase=run-finish banners=\(output.count) withCandidates=\(bannersWithCandidates) totalCandidates=\(totalCandidates)")
        extractionState = .completed
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

    private var extractionCompletedSummary: String {
        let values = extractions.values
        let totalCandidates = values.reduce(0) { $0 + $1.candidateCount }
        let bannersWithCandidates = values.filter { $0.candidateCount > 0 }.count
        let totalBanners = values.count
        return "Extracted \(totalCandidates) price candidate\(totalCandidates == 1 ? "" : "s") from \(bannersWithCandidates) of \(totalBanners) banners."
    }
}

/// Console logging for the extraction layer, emitting a `[FlyerExtraction]` trail
/// that correlates with the `[FlyerDiscovery]` and `[FlyerAcquisition]` trails.
struct ConsoleFlyerExtractionLogger: FlyerAcquisitionLogging {
    func log(_ message: String) {
        print("[FlyerExtraction] \(message)")
    }
}
