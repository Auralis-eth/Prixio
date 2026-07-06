import Combine
import Foundation
import SwiftData

/// Drives the flyer pipeline (discovery → acquisition → extraction → deal matching →
/// review/save) behind the Shopping List's "Check Flyers" sheet. Each stage can still
/// run individually (the pipeline tests exercise them stage by stage); the product
/// surface runs them in sequence via `runFullCheck`.
@MainActor
final class FlyerCheckViewModel: ObservableObject {
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
    @Published private(set) var matchState: RunState = .idle
    @Published private(set) var matches: [ShoppingItemFlyerMatches] = []
    /// Similar-but-different deal suggestions per list item, computed alongside
    /// `matches` (see `FlyerAlternativeFinder`).
    @Published private(set) var alternatives: [ShoppingItemFlyerAlternatives] = []
    /// Whether the last match ran against the user's real shopping list or fell back
    /// to the built-in sample list (empty list).
    @Published private(set) var matchedAgainstRealList = false
    /// `dealKey`s already saved to the flyer price store, for marking review rows.
    @Published private(set) var savedDealKeys: Set<String> = []
    /// Whether `runFullCheck` is mid-flight (drives the Check Flyers sheet's progress UI).
    @Published private(set) var isRunningFullCheck = false

    /// Bumped whenever match results are rebuilt or invalidated, so the post-publish
    /// enrichment refinement can tell when its results have gone stale.
    private var matchGeneration = 0

    private let coordinator: FlyerDiscoveryCoordinator
    private let acquirer: FlyerContentAcquiring
    private let acquisitionLogger: FlyerAcquisitionLogging
    private let extractor: FlyerPriceExtractor
    private let extractionLogger: FlyerAcquisitionLogging
    private let dealMatcher = FlyerDealMatcher()
    private let alternativeFinder = FlyerAlternativeFinder()
    private let matchLogger: FlyerAcquisitionLogging
    /// Model-backed extraction for harvested-text payloads; the deterministic
    /// extractor's result stands whenever this returns nil (gated/unavailable/failed).
    private let textCandidateExtractor: any FlyerTextCandidateExtracting
    /// Name enrichment between extraction and matching (FlyerOutstandingWork item 4).
    private let nameEnricher: any FlyerNameEnriching

    /// A stand-in shopping list used as a fallback when the user's real list has no
    /// active items: matching is demonstrated against a fixed set of common Alberta
    /// grocery items. Product surfaces should gate on a non-empty list instead.
    static let sampleQueries: [FlyerDealMatcher.Query] = [
        "milk", "eggs", "butter", "bread", "bananas", "chicken breast",
        "ground beef", "coffee", "cheese", "apples", "potatoes", "yogurt"
    ].map { FlyerDealMatcher.Query(itemKey: ItemKeyNormalizer.normalize($0), displayName: $0) }

    /// Acquisition methods whose payload is harvested text — the ones worth routing
    /// through the on-device model instead of the line-pairing heuristic.
    static let modelTextMethods: Set<FlyerAcquisitionMethod> = [.staticHTML, .renderedHTML, .imageOCR]

    init(
        coordinator: FlyerDiscoveryCoordinator? = nil,
        acquirer: FlyerContentAcquiring? = nil,
        acquisitionLogger: FlyerAcquisitionLogging? = nil,
        extractor: FlyerPriceExtractor = FlyerPriceExtractor(),
        extractionLogger: FlyerAcquisitionLogging? = nil,
        textCandidateExtractor: (any FlyerTextCandidateExtracting)? = nil,
        nameEnricher: (any FlyerNameEnriching)? = nil,
        initialResults: [FlyerDiscoveryResult]? = nil
    ) {
        self.textCandidateExtractor = textCandidateExtractor ?? FoundationModelsFlyerTextExtractor()
        self.nameEnricher = nameEnricher ?? FlyerNameEnricher()
        let connectors = FlyerSourceConnectorCatalog.albertaConnectors
        self.coordinator = coordinator ?? FlyerDiscoveryCoordinator(connectors: connectors)
        self.acquirer = acquirer ?? FlyerContentAcquisitionRouter()
        self.acquisitionLogger = acquisitionLogger ?? ConsoleFlyerAcquisitionLogger()
        self.extractor = extractor
        self.extractionLogger = extractionLogger ?? ConsoleFlyerExtractionLogger()
        self.matchLogger = ConsoleFlyerMatchLogger()
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
        invalidateMatches()
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
        invalidateMatches()
        acquisitionLogger.log("phase=run-start banners=\(results.count)")
        var output: [FlyerBannerID: FlyerAcquiredContent] = [:]

        // Banners with no network work (unsupported / no source URL) resolve up front.
        // The rest fetch concurrently: each acquire is independent network I/O, so a
        // task group overlaps all of them (run time ≈ the slowest banner, not the sum)
        // while still publishing each result as it lands.
        let acquirer = self.acquirer
        await withTaskGroup(of: (FlyerBannerID, FlyerAcquiredContent).self) { group in
            for result in results {
                switch result.state {
                case .unsupported:
                    output[result.banner.id] = .unsupported(banner: result.banner, reason: result.message)
                default:
                    guard let url = result.selectedURL else {
                        output[result.banner.id] = .missingSource(banner: result.banner)
                        continue
                    }
                    let banner = result.banner
                    let shape = result.sourceShape
                    group.addTask {
                        let content = await acquirer.acquire(
                            banner: banner,
                            from: url,
                            sourceShape: shape,
                            storeContext: nil
                        )
                        return (banner.id, content)
                    }
                }
            }
            // Publish the synchronously-resolved banners immediately, then each fetched
            // banner as its task completes.
            acquisitions = output
            for await (id, content) in group {
                output[id] = content
                acquisitions = output
            }
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
        // Re-extracting invalidates any prior deal matching.
        invalidateMatches()
        extractionLogger.log("phase=run-start banners=\(acquisitions.count)")
        var output: [FlyerBannerID: FlyerExtractionResult] = [:]
        // Extract in the discovery rank order so the log/UI read consistently.
        for result in results {
            guard let content = acquisitions[result.banner.id] else { continue }
            let label = FlyerAcquisitionLogLabel.make(for: content.banner)
            var extraction = extractor.extract(from: content)
            // Harvested-text payloads go through the on-device model when it's
            // available — it reads context the line-pairing heuristic can't. The
            // deterministic result stands when the model is gated or comes back empty.
            if let method = content.acquisitionMethod, Self.modelTextMethods.contains(method),
               let payload = content.extractionPayload, !payload.isEmpty,
               let modelCandidates = await textCandidateExtractor.extractCandidates(fromText: payload),
               !modelCandidates.isEmpty {
                extractionLogger.log("banner=\(label) phase=model-text deterministic=\(extraction.candidateCount) model=\(modelCandidates.count)")
                extraction = FlyerExtractionResult(
                    banner: extraction.banner,
                    sourceURL: extraction.sourceURL,
                    fetchedAt: extraction.fetchedAt,
                    method: extraction.method,
                    candidates: modelCandidates,
                    message: "Extracted \(modelCandidates.count) price candidate\(modelCandidates.count == 1 ? "" : "s") via on-device model."
                )
            }
            extractionLogger.log("banner=\(label) method=\(content.acquisitionMethod?.rawValue ?? "none") state=\(content.state.rawValue) candidates=\(extraction.candidateCount)")
            // Diagnostic: a captured-JSON banner that extracts nothing has a schema the
            // generic walker doesn't recognize (e.g. Co-op). Log a bounded payload
            // sample so the next device run reveals its item shape.
            if extraction.candidateCount == 0,
               content.acquisitionMethod == .endpointJSON,
               let payload = content.extractionPayload, !payload.isEmpty {
                let sample = payload.replacingOccurrences(of: "\n", with: " ").prefix(400)
                extractionLogger.log("banner=\(label) phase=zero-candidate-sample bytes=\(payload.utf8.count) sample=\(sample)")
            }
            output[result.banner.id] = extraction
            // Publish progressively so each banner's candidates appear as they land.
            extractions = output
        }

        let totalCandidates = output.values.reduce(0) { $0 + $1.candidateCount }
        let bannersWithCandidates = output.values.filter { $0.candidateCount > 0 }.count
        extractionLogger.log("phase=run-finish banners=\(output.count) withCandidates=\(bannersWithCandidates) totalCandidates=\(totalCandidates)")
        extractionState = .completed
    }

    /// Matching can run once extraction has produced candidates.
    var canMatchDeals: Bool {
        extractionState == .completed && matchState != .loading
    }

    var isMatching: Bool {
        matchState == .loading
    }

    var matchSummary: String {
        switch matchState {
        case .idle:
            "Extract candidates first, then match them against your shopping list."
        case .loading:
            "Matching flyer candidates to your shopping list..."
        case .completed:
            matchCompletedSummary
        }
    }

    /// Results limited to items that found at least one deal — the useful subset.
    var matchedItemsWithDeals: [ShoppingItemFlyerMatches] {
        matches.filter(\.hasDeals)
    }

    /// One line per pipeline stage with at-a-glance counts, so a device run shows
    /// where data narrows (e.g. lots of candidates but few matches, or matches saved
    /// but nothing in Compare).
    struct PipelineStageSummary: Identifiable, Equatable {
        let stage: String
        let detail: String
        let systemImage: String
        var id: String { stage }
    }

    var pipelineSummary: [PipelineStageSummary] {
        // Discovery
        let discovery: String
        if runState == .completed {
            let found = results.filter { $0.state == .found }.count
            let render = results.filter { $0.state == .needsRenderedExtraction }.count
            let unsupported = results.filter { $0.state == .unsupported }.count
            discovery = "\(results.count) banners · \(found) found · \(render) need render · \(unsupported) unsupported"
        } else {
            discovery = "Not run yet"
        }

        // Acquisition
        let acquisition: String
        if acquisitionState == .completed {
            let values = acquisitions.values
            let acquired = values.filter { $0.state == .acquired }.count
            let noPrices = values.filter { $0.state == .acquiredNoPrices }.count
            let failed = values.filter { $0.state == .failed }.count
            acquisition = "\(acquired) acquired · \(noPrices) no-prices · \(failed) failed"
        } else {
            acquisition = "Not run yet"
        }

        // Extraction
        let extraction: String
        if extractionState == .completed {
            let total = extractions.values.reduce(0) { $0 + $1.candidateCount }
            let withCandidates = extractions.values.filter { $0.candidateCount > 0 }.count
            extraction = "\(total) candidates · \(withCandidates) banners"
        } else {
            extraction = "Not run yet"
        }

        // Match
        let match: String
        if matchState == .completed {
            let totalDeals = matches.reduce(0) { $0 + $1.deals.count }
            let listLabel = matchedAgainstRealList ? "your list" : "sample list"
            match = "\(matchedItemsWithDeals.count)/\(matches.count) \(listLabel) items · \(totalDeals) deals"
        } else {
            match = "Not run yet"
        }

        // Saved
        let saved = savedDealKeys.isEmpty
            ? "No flyer prices saved"
            : "\(savedDealKeys.count) flyer price\(savedDealKeys.count == 1 ? "" : "s") saved"

        return [
            PipelineStageSummary(stage: "1 · Discovery", detail: discovery, systemImage: "magnifyingglass"),
            PipelineStageSummary(stage: "2 · Acquisition", detail: acquisition, systemImage: "square.and.arrow.down"),
            PipelineStageSummary(stage: "3 · Extraction", detail: extraction, systemImage: "list.bullet.rectangle"),
            PipelineStageSummary(stage: "4 · Match", detail: match, systemImage: "cart"),
            PipelineStageSummary(stage: "5 · Saved", detail: saved, systemImage: "tray.full")
        ]
    }

    /// Matches extracted candidates against the user's real shopping list,
    /// falling back to the built-in sample list when the list is empty so the POC
    /// still demonstrates. Pass the SwiftData context from the view environment.
    ///
    /// Deterministic results publish immediately (`matchState` completes without
    /// waiting on the model); the name-enrichment pass then re-matches and refines
    /// the published results in place when it adds knowledge.
    func matchDeals(context: ModelContext) async {
        guard extractionState == .completed, matchState != .loading else {
            return
        }

        matchState = .loading
        matchGeneration += 1
        let generation = matchGeneration
        let queries = shoppingListQueries(context: context)
        matchLogger.log("phase=run-start items=\(queries.count) realList=\(matchedAgainstRealList) banners=\(extractions.count)")

        // Deterministic pass first, so results never wait on the on-device model.
        publishMatchResults(queries: queries, queryEnrichments: [:])
        matchState = .completed
        loadSavedDealKeys(context: context)

        // Enrichment then refines the published results from behind: three name
        // sets, all cache-backed and availability-gated — the direct matcher's
        // token-subset prefilter, the alternative finder's looser shared-token
        // prefilter (class comparison needs candidates the subset rule never
        // reaches), and the query names themselves (the query side of every class
        // comparison). When the model adds knowledge, matching re-runs and the
        // results update in place; the generation guard keeps a stale refinement
        // from overwriting a newer run.
        let extractionResults = Array(extractions.values)
        var targets = FlyerDealMatcher.enrichmentTargets(queries: queries, extractions: extractionResults)
        var targetSet = Set(targets)
        for name in FlyerAlternativeFinder.enrichmentTargets(queries: queries, extractions: extractionResults)
        where targetSet.insert(name).inserted {
            targets.append(name)
        }
        targets += queries.map(\.displayName).filter { targetSet.insert($0).inserted }
        guard !targets.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            let enrichments = await self.nameEnricher.enrichments(for: targets)
            self.matchLogger.log("phase=enrichment targets=\(targets.count) enriched=\(enrichments.count)")
            guard !enrichments.isEmpty, self.matchGeneration == generation else { return }
            self.extractions = self.extractions.mapValues { $0.applyingEnrichments(enrichments) }
            // Re-key the queries' own enrichments by item key for the alternative
            // finder (its matches carry keys, not raw names). Two display names can
            // normalize to the same key; keep the enrichment carrying a substitution
            // class so class-based alternatives aren't lost to the collision.
            let queryEnrichments = Dictionary(
                queries.compactMap { query in
                    enrichments[query.displayName].map { (query.itemKey, $0) }
                },
                uniquingKeysWith: { first, second in
                    first.substitutionClass != nil ? first : second
                }
            )
            self.publishMatchResults(queries: queries, queryEnrichments: queryEnrichments)
        }
    }

    /// Runs the deterministic matcher and alternative finder over the current
    /// extractions and publishes the results. Alternatives ride alongside direct
    /// matches: similar products worth a look when the exact item has no deal (or a
    /// similar one beats its best deal).
    private func publishMatchResults(
        queries: [FlyerDealMatcher.Query],
        queryEnrichments: [String: EnrichedProductName]
    ) {
        let extractionResults = Array(extractions.values)
        let results = dealMatcher.match(queries: queries, extractions: extractionResults)
        for item in results {
            matchLogger.log("item=\(item.displayName) deals=\(item.deals.count) best=\(item.bestDeal.map { CurrencyFormatter.shared.display($0.candidate.price) + " @ " + $0.banner.name } ?? "none")")
        }
        let itemsWithDeals = results.filter(\.hasDeals).count
        let totalDeals = results.reduce(0) { $0 + $1.deals.count }
        matchLogger.log("phase=run-finish items=\(results.count) withDeals=\(itemsWithDeals) totalDeals=\(totalDeals)")
        matches = results
        alternatives = alternativeFinder.findAlternatives(
            matches: results,
            extractions: extractionResults,
            queryEnrichments: queryEnrichments
        )
    }

    /// Clears published match results and bumps the generation so any in-flight
    /// enrichment refinement abandons itself instead of resurrecting stale matches.
    private func invalidateMatches() {
        matches = []
        alternatives = []
        matchState = .idle
        matchGeneration += 1
    }

    /// The alternative suggestions for one matched item, if any.
    func alternatives(forItemKey itemKey: String) -> ShoppingItemFlyerAlternatives? {
        alternatives.first { $0.itemKey == itemKey }
    }

    /// Items worth showing in the review list: a direct deal, an alternative, or both.
    var reviewableItems: [ShoppingItemFlyerMatches] {
        matches.filter { $0.hasDeals || alternatives(forItemKey: $0.itemKey) != nil }
    }

    /// Runs the whole pipeline as one user action (the Check Flyers surface): each
    /// stage's guard makes a stage that couldn't start fall through, leaving the
    /// pipeline exactly as far as it got.
    func runFullCheck(context: ModelContext) async {
        guard !isRunningFullCheck else { return }
        isRunningFullCheck = true
        defer { isRunningFullCheck = false }

        await checkFlyers()
        await acquireContent()
        await extractContent()
        await matchDeals(context: context)
    }

    /// The in-flight stage, for the Check Flyers progress UI.
    var fullCheckPhaseDescription: String {
        if runState == .loading { return "Checking retailer flyer sources…" }
        if acquisitionState == .loading { return "Fetching this week's flyers…" }
        if extractionState == .loading { return "Reading advertised prices…" }
        return "Matching deals to your list…"
    }

    /// Builds match queries from the user's active (not-done) shopping-list items;
    /// falls back to the sample list when the real list is empty. Sets
    /// `matchedAgainstRealList` accordingly.
    private func shoppingListQueries(context: ModelContext) -> [FlyerDealMatcher.Query] {
        let repository = ShoppingListRepository(context: context)
        let items = (try? repository.fetchOrCreateDefaultList())?.items ?? []
        let activeQueries = items
            .filter { !$0.isDone }
            .map { FlyerDealMatcher.Query(itemKey: $0.itemKey, displayName: $0.displayName) }

        if activeQueries.isEmpty {
            matchedAgainstRealList = false
            return Self.sampleQueries
        }
        matchedAgainstRealList = true
        return activeQueries
    }

    /// Whether a given deal has already been saved (for the review row's saved state).
    func isDealSaved(_ deal: FlyerDeal) -> Bool {
        savedDealKeys.contains(FlyerPriceRecord.dealKey(
            bannerID: deal.banner.id.rawValue,
            normalizedItemKey: deal.candidate.normalizedItemKey,
            price: deal.candidate.price
        ))
    }

    /// Saves a reviewed deal to the dedicated flyer price store. Pass a nil `itemKey`
    /// for an alternative suggestion: the record is always stored under the flyer
    /// product's own item key, and `matchedItemKey` must not claim a list match that
    /// didn't happen.
    func saveDeal(_ deal: FlyerDeal, forItemKey itemKey: String?, context: ModelContext) {
        let repository = FlyerPriceRecordRepository(context: context)
        do {
            try repository.save(deal, matchedItemKey: itemKey, storeContext: storeContextLabel)
            loadSavedDealKeys(context: context)
            matchLogger.log("phase=save dealKey=\(deal.banner.id.rawValue)|\(deal.candidate.normalizedItemKey)|\(deal.candidate.price) ok")
        } catch {
            matchLogger.log("phase=save error=\(error.localizedDescription)")
        }
    }

    /// Refreshes the set of saved deal keys from the store.
    func loadSavedDealKeys(context: ModelContext) {
        let repository = FlyerPriceRecordRepository(context: context)
        savedDealKeys = (try? repository.savedDealKeys()) ?? []
    }

    /// Geography the POC acquires under, recorded as provenance on saved deals.
    private var storeContextLabel: String { FlyerStoreContext.defaultAlberta.label }

    private var matchCompletedSummary: String {
        let itemsWithDeals = matchedItemsWithDeals.count
        let totalDeals = matches.reduce(0) { $0 + $1.deals.count }
        let listLabel = matchedAgainstRealList ? "shopping list" : "sample list"
        return "Found \(totalDeals) flyer deal\(totalDeals == 1 ? "" : "s") for \(itemsWithDeals) of \(matches.count) \(listLabel) items."
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

/// Console logging for deal matching, emitting a `[FlyerMatch]` trail.
struct ConsoleFlyerMatchLogger: FlyerAcquisitionLogging {
    func log(_ message: String) {
        print("[FlyerMatch] \(message)")
    }
}
