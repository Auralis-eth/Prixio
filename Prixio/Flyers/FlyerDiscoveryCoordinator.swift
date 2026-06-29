import Foundation

enum FlyerDiscoveryMethod: String, Equatable {
    case knownURL = "Known URL"
    case braveSearch = "Brave Search"
}

/// The outcome of a single URL the coordinator considered while discovering a
/// source. Recorded for every attempt so a real run can be debugged from the
/// result model alone, without reading Xcode console logs.
enum FlyerAttemptOutcome: String, Equatable {
    /// Extractable official source; selected as the discovery result.
    case accepted
    /// Reachable official page, but a JS shell (`dynamicHTML`/`unknown`) that
    /// needs rendered extraction before prices can be read.
    case weakDynamic
    /// Non-2xx status or an empty body.
    case unusable
    /// The fetch threw before a response was classified.
    case fetchError
    /// A search result rejected by the domain filter (never fetched).
    case domainRejected

    var label: String {
        switch self {
        case .accepted:
            "Accepted"
        case .weakDynamic:
            "Weak (dynamic)"
        case .unusable:
            "Unusable"
        case .fetchError:
            "Fetch error"
        case .domainRejected:
            "Domain rejected"
        }
    }
}

/// A single audit-trail entry describing one URL the coordinator attempted while
/// discovering a banner's source. Deterministic and free of timestamps/UUIDs so
/// whole `FlyerDiscoveryResult` values stay `Equatable` and testable.
struct FlyerDiscoveryAttempt: Equatable {
    let method: FlyerDiscoveryMethod
    let attemptedURL: URL
    let finalURL: URL?
    let statusCode: Int?
    let mimeType: String?
    let byteCount: Int?
    let sourceShape: FlyerSourceShape?
    let outcome: FlyerAttemptOutcome
    let detail: String
}

enum FlyerDiscoveryState: Equatable {
    case found
    case needsRenderedExtraction
    case fallbackUnavailable
    case unsupported
    case failed

    var label: String {
        switch self {
        case .found:
            "Found"
        case .needsRenderedExtraction:
            "Needs rendered extraction"
        case .fallbackUnavailable:
            "Fallback unavailable"
        case .unsupported:
            "Unsupported"
        case .failed:
            "Failed"
        }
    }
}

struct FlyerDiscoveryResult: Identifiable, Equatable {
    let banner: FlyerBanner
    let state: FlyerDiscoveryState
    let selectedURL: URL?
    let method: FlyerDiscoveryMethod?
    let sourceShape: FlyerSourceShape?
    let message: String
    /// Every URL the coordinator considered for this banner, in attempt order.
    let attempts: [FlyerDiscoveryAttempt]
    /// Every search query the coordinator issued for this banner, in order.
    let attemptedQueries: [String]

    var id: FlyerBannerID { banner.id }

    init(
        banner: FlyerBanner,
        state: FlyerDiscoveryState,
        selectedURL: URL?,
        method: FlyerDiscoveryMethod?,
        sourceShape: FlyerSourceShape? = nil,
        message: String,
        attempts: [FlyerDiscoveryAttempt] = [],
        attemptedQueries: [String] = []
    ) {
        self.banner = banner
        self.state = state
        self.selectedURL = selectedURL
        self.method = method
        self.sourceShape = sourceShape
        self.message = message
        self.attempts = attempts
        self.attemptedQueries = attemptedQueries
    }

    /// Returns a copy carrying the accumulated per-attempt audit trail. Keeps the
    /// state-producing call sites focused on the decision while diagnostics are
    /// attached once at the end of discovery.
    func addingDiagnostics(
        attempts: [FlyerDiscoveryAttempt],
        attemptedQueries: [String]
    ) -> FlyerDiscoveryResult {
        FlyerDiscoveryResult(
            banner: banner,
            state: state,
            selectedURL: selectedURL,
            method: method,
            sourceShape: sourceShape,
            message: message,
            attempts: attempts,
            attemptedQueries: attemptedQueries
        )
    }
}

final class FlyerDiscoveryCoordinator {
    private let connectors: [FlyerSourceConnector]
    private let fetcher: FlyerDocumentFetching
    private let searchProvider: FlyerSearchProviding
    private let logger: FlyerDiscoveryLogging

    init(
        connectors: [FlyerSourceConnector] = FlyerSourceConnectorCatalog.albertaConnectors,
        fetcher: FlyerDocumentFetching = URLSessionFlyerDocumentFetcher(),
        searchProvider: FlyerSearchProviding = BraveSearchProvider(),
        logger: FlyerDiscoveryLogging = ConsoleFlyerDiscoveryLogger()
    ) {
        self.connectors = connectors.sorted { $0.banner.rank < $1.banner.rank }
        self.fetcher = fetcher
        self.searchProvider = searchProvider
        self.logger = logger
    }

    func discoverSources() async -> [FlyerDiscoveryResult] {
        let runID = FlyerDiscoveryLogRunID.make()
        logger.log("run=\(runID) phase=start banners=\(connectors.count) braveKeyConfigured=\(BraveSearchConfiguration.hasUsableAPIKey)")

        var results: [FlyerDiscoveryResult] = []
        for connector in connectors {
            results.append(await discoverSource(for: connector, runID: runID))
        }

        let foundCount = results.filter { $0.state == .found }.count
        let needsRenderedExtractionCount = results.filter { $0.state == .needsRenderedExtraction }.count
        let fallbackUnavailableCount = results.filter { $0.state == .fallbackUnavailable }.count
        let failedCount = results.filter { $0.state == .failed }.count
        let unsupportedCount = results.filter { $0.state == .unsupported }.count
        logger.log("run=\(runID) phase=finish found=\(foundCount) needsRenderedExtraction=\(needsRenderedExtractionCount) fallbackUnavailable=\(fallbackUnavailableCount) failed=\(failedCount) unsupported=\(unsupportedCount)")

        return results
    }

    private func discoverSource(for connector: FlyerSourceConnector, runID: String) async -> FlyerDiscoveryResult {
        let bannerLabel = logLabel(for: connector.banner)
        logger.log("run=\(runID) banner=\(bannerLabel) phase=banner-start knownURLs=\(connector.officialEntryURLs.count) queries=\(connector.searchQueries.count)")

        if let unsupportedReason = connector.unsupportedReason {
            logger.log("run=\(runID) banner=\(bannerLabel) phase=unsupported reason=\(unsupportedReason)")
            return FlyerDiscoveryResult(
                banner: connector.banner,
                state: .unsupported,
                selectedURL: nil,
                method: nil,
                message: unsupportedReason
            )
        }

        var attempts: [FlyerDiscoveryAttempt] = []
        var attemptedQueries: [String] = []

        let knownURLResult = await firstUsableKnownURL(for: connector, runID: runID, attempts: &attempts)
        if let knownURLResult, knownURLResult.state == .found {
            let result = knownURLResult.addingDiagnostics(attempts: attempts, attemptedQueries: attemptedQueries)
            logBannerFinish(result, bannerLabel: bannerLabel, runID: runID)
            return result
        }

        let fallbackResult = await discoverWithSearchFallback(
            for: connector,
            runID: runID,
            attempts: &attempts,
            attemptedQueries: &attemptedQueries
        )
        let result = bestResult(fallbackResult, fallback: knownURLResult)
            .addingDiagnostics(attempts: attempts, attemptedQueries: attemptedQueries)
        logBannerFinish(result, bannerLabel: bannerLabel, runID: runID)
        return result
    }

    private func logBannerFinish(_ result: FlyerDiscoveryResult, bannerLabel: String, runID: String) {
        logger.log("run=\(runID) banner=\(bannerLabel) phase=banner-finish state=\(result.state.label) method=\(result.method?.rawValue ?? "none") shape=\(result.sourceShape?.rawValue ?? "none") attempts=\(result.attempts.count) selectedURL=\(result.selectedURL?.absoluteString ?? "none") message=\(result.message)")
    }

    private func firstUsableKnownURL(
        for connector: FlyerSourceConnector,
        runID: String,
        attempts: inout [FlyerDiscoveryAttempt]
    ) async -> FlyerDiscoveryResult? {
        let bannerLabel = logLabel(for: connector.banner)
        var weakResult: FlyerDiscoveryResult?
        var weakByteCount = -1
        for url in connector.officialEntryURLs {
            guard connector.allows(url: url) else {
                logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-rejected reason=domain-not-allowed attemptedURL=\(url.absoluteString)")
                attempts.append(FlyerDiscoveryAttempt(
                    method: .knownURL,
                    attemptedURL: url,
                    finalURL: nil,
                    statusCode: nil,
                    mimeType: nil,
                    byteCount: nil,
                    sourceShape: nil,
                    outcome: .domainRejected,
                    detail: "Known URL host is not in the connector's allowed domains."
                ))
                continue
            }

            logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-fetch-start attemptedURL=\(url.absoluteString)")
            do {
                let document = try await fetcher.fetch(url)
                logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-fetch-finish attemptedURL=\(url.absoluteString) finalURL=\(document.finalURL.absoluteString) status=\(document.statusCode) mime=\(document.mimeType ?? "unknown") bytes=\(document.byteCount) shape=\(document.sourceShape.rawValue) usable=\(document.isUsable) signals=\(signalsLabel(for: document)) snippet=\(snippetLabel(for: document))")
                guard document.isUsable else {
                    logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-unusable reason=\(unusableReason(for: document)) attemptedURL=\(url.absoluteString)")
                    attempts.append(FlyerDiscoveryAttempt(
                        method: .knownURL,
                        attemptedURL: url,
                        finalURL: document.finalURL,
                        statusCode: document.statusCode,
                        mimeType: document.mimeType,
                        byteCount: document.byteCount,
                        sourceShape: document.sourceShape,
                        outcome: .unusable,
                        detail: "Unusable response: \(unusableReason(for: document))."
                    ))
                    continue
                }

                guard isExtractableSource(document.sourceShape) else {
                    logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-weak reason=requires-rendered-extraction attemptedURL=\(url.absoluteString) finalURL=\(document.finalURL.absoluteString) shape=\(document.sourceShape.rawValue)")
                    attempts.append(FlyerDiscoveryAttempt(
                        method: .knownURL,
                        attemptedURL: url,
                        finalURL: document.finalURL,
                        statusCode: document.statusCode,
                        mimeType: document.mimeType,
                        byteCount: document.byteCount,
                        sourceShape: document.sourceShape,
                        outcome: .weakDynamic,
                        detail: "Reachable but \(document.sourceShape.label); needs rendered extraction."
                    ))
                    // Among reachable-but-dynamic official URLs, keep the richest by
                    // byte count. A suspiciously tiny dynamic response is usually an
                    // anti-bot/redirect shell (e.g. No Frills' ~2.6 KB Akamai
                    // challenge) rather than the real flyer page, so the larger shell
                    // is the better seed for the rendered fetch.
                    if document.byteCount > weakByteCount {
                        weakByteCount = document.byteCount
                        weakResult = FlyerDiscoveryResult(
                            banner: connector.banner,
                            state: .needsRenderedExtraction,
                            selectedURL: document.finalURL,
                            method: .knownURL,
                            sourceShape: document.sourceShape,
                            message: "Official source is reachable but requires rendered extraction before prices can be read."
                        )
                    }
                    continue
                }

                attempts.append(FlyerDiscoveryAttempt(
                    method: .knownURL,
                    attemptedURL: url,
                    finalURL: document.finalURL,
                    statusCode: document.statusCode,
                    mimeType: document.mimeType,
                    byteCount: document.byteCount,
                    sourceShape: document.sourceShape,
                    outcome: .accepted,
                    detail: "Accepted official \(document.sourceShape.label) source."
                ))
                return FlyerDiscoveryResult(
                    banner: connector.banner,
                    state: .found,
                    selectedURL: document.finalURL,
                    method: .knownURL,
                    sourceShape: document.sourceShape,
                    message: "Official source returned HTTP \(document.statusCode), \(document.byteCount) bytes, shape \(document.sourceShape.label)."
                )
            } catch {
                logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-fetch-error attemptedURL=\(url.absoluteString) error=\(logDescription(for: error))")
                attempts.append(FlyerDiscoveryAttempt(
                    method: .knownURL,
                    attemptedURL: url,
                    finalURL: nil,
                    statusCode: nil,
                    mimeType: nil,
                    byteCount: nil,
                    sourceShape: nil,
                    outcome: .fetchError,
                    detail: logDescription(for: error)
                ))
                continue
            }
        }

        logger.log("run=\(runID) banner=\(bannerLabel) phase=known-urls-exhausted")
        return weakResult
    }

    private func discoverWithSearchFallback(
        for connector: FlyerSourceConnector,
        runID: String,
        attempts: inout [FlyerDiscoveryAttempt],
        attemptedQueries: inout [String]
    ) async -> FlyerDiscoveryResult {
        let bannerLabel = logLabel(for: connector.banner)
        var sawMissingAPIKey = false
        var sawRejectedThirdParty = false

        for query in connector.searchQueries {
            attemptedQueries.append(query)
            logger.log("run=\(runID) banner=\(bannerLabel) phase=search-query-start query=\(query)")
            do {
                let searchResults = try await searchProvider.search(query: query)
                let rankedResults = rankedSearchResults(searchResults, for: connector)
                logger.log("run=\(runID) banner=\(bannerLabel) phase=search-query-finish query=\(query) resultCount=\(searchResults.count)")
                for searchResult in rankedResults {
                    let score = score(searchResult, for: connector)
                    guard connector.allows(url: searchResult.url) else {
                        sawRejectedThirdParty = true
                        logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-rejected reason=domain-not-allowed score=\(score) title=\(searchResult.title) url=\(searchResult.url.absoluteString)")
                        attempts.append(FlyerDiscoveryAttempt(
                            method: .braveSearch,
                            attemptedURL: searchResult.url,
                            finalURL: nil,
                            statusCode: nil,
                            mimeType: nil,
                            byteCount: nil,
                            sourceShape: nil,
                            outcome: .domainRejected,
                            detail: "Rejected third-party domain (not fetched): \(searchResult.title)."
                        ))
                        continue
                    }

                    logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-fetch-start score=\(score) title=\(searchResult.title) url=\(searchResult.url.absoluteString)")
                    do {
                        let document = try await fetcher.fetch(searchResult.url)
                        logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-fetch-finish attemptedURL=\(searchResult.url.absoluteString) finalURL=\(document.finalURL.absoluteString) status=\(document.statusCode) mime=\(document.mimeType ?? "unknown") bytes=\(document.byteCount) shape=\(document.sourceShape.rawValue) usable=\(document.isUsable) signals=\(signalsLabel(for: document)) snippet=\(snippetLabel(for: document))")
                        guard document.isUsable else {
                            logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-unusable reason=\(unusableReason(for: document)) attemptedURL=\(searchResult.url.absoluteString)")
                            attempts.append(FlyerDiscoveryAttempt(
                                method: .braveSearch,
                                attemptedURL: searchResult.url,
                                finalURL: document.finalURL,
                                statusCode: document.statusCode,
                                mimeType: document.mimeType,
                                byteCount: document.byteCount,
                                sourceShape: document.sourceShape,
                                outcome: .unusable,
                                detail: "Unusable response: \(unusableReason(for: document))."
                            ))
                            continue
                        }

                        guard isExtractableSource(document.sourceShape) else {
                            logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-weak reason=requires-rendered-extraction attemptedURL=\(searchResult.url.absoluteString) finalURL=\(document.finalURL.absoluteString) shape=\(document.sourceShape.rawValue)")
                            attempts.append(FlyerDiscoveryAttempt(
                                method: .braveSearch,
                                attemptedURL: searchResult.url,
                                finalURL: document.finalURL,
                                statusCode: document.statusCode,
                                mimeType: document.mimeType,
                                byteCount: document.byteCount,
                                sourceShape: document.sourceShape,
                                outcome: .weakDynamic,
                                detail: "Reachable but \(document.sourceShape.label); needs rendered extraction."
                            ))
                            continue
                        }

                        attempts.append(FlyerDiscoveryAttempt(
                            method: .braveSearch,
                            attemptedURL: searchResult.url,
                            finalURL: document.finalURL,
                            statusCode: document.statusCode,
                            mimeType: document.mimeType,
                            byteCount: document.byteCount,
                            sourceShape: document.sourceShape,
                            outcome: .accepted,
                            detail: "Accepted official \(document.sourceShape.label) result from \(hostLabel(for: document.finalURL))."
                        ))
                        return FlyerDiscoveryResult(
                            banner: connector.banner,
                            state: .found,
                            selectedURL: document.finalURL,
                            method: .braveSearch,
                            sourceShape: document.sourceShape,
                            message: "Brave fallback selected an official \(document.sourceShape.label) result from \(hostLabel(for: document.finalURL))."
                        )
                    } catch {
                        logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-fetch-error attemptedURL=\(searchResult.url.absoluteString) error=\(logDescription(for: error))")
                        attempts.append(FlyerDiscoveryAttempt(
                            method: .braveSearch,
                            attemptedURL: searchResult.url,
                            finalURL: nil,
                            statusCode: nil,
                            mimeType: nil,
                            byteCount: nil,
                            sourceShape: nil,
                            outcome: .fetchError,
                            detail: logDescription(for: error)
                        ))
                        continue
                    }
                }
            } catch FlyerSearchError.missingAPIKey {
                sawMissingAPIKey = true
                logger.log("run=\(runID) banner=\(bannerLabel) phase=search-unavailable reason=missing-api-key query=\(query)")
                break
            } catch {
                logger.log("run=\(runID) banner=\(bannerLabel) phase=search-query-error query=\(query) error=\(logDescription(for: error))")
                continue
            }
        }

        if sawMissingAPIKey {
            return FlyerDiscoveryResult(
                banner: connector.banner,
                state: .fallbackUnavailable,
                selectedURL: nil,
                method: nil,
                message: "Official URLs were unavailable and BRAVE_SEARCH_API_KEY is not configured."
            )
        }

        let message = sawRejectedThirdParty
            ? "Search fallback found only rejected third-party or unusable official results."
            : "No usable official flyer source was found."

        return FlyerDiscoveryResult(
            banner: connector.banner,
            state: .failed,
            selectedURL: nil,
            method: nil,
            message: message
        )
    }

    private func bestResult(_ result: FlyerDiscoveryResult, fallback: FlyerDiscoveryResult?) -> FlyerDiscoveryResult {
        if result.state == .found {
            return result
        }

        if let fallback, fallback.state == .needsRenderedExtraction {
            if result.state == .fallbackUnavailable {
                return FlyerDiscoveryResult(
                    banner: fallback.banner,
                    state: fallback.state,
                    selectedURL: fallback.selectedURL,
                    method: fallback.method,
                    sourceShape: fallback.sourceShape,
                    message: "\(fallback.message) Brave fallback is unavailable because BRAVE_SEARCH_API_KEY is not configured."
                )
            }

            return fallback
        }

        return result
    }

    private func rankedSearchResults(
        _ results: [FlyerSearchResult],
        for connector: FlyerSourceConnector
    ) -> [FlyerSearchResult] {
        results.sorted { lhs, rhs in
            score(lhs, for: connector) > score(rhs, for: connector)
        }
    }

    private func score(_ result: FlyerSearchResult, for connector: FlyerSourceConnector) -> Int {
        let haystack = [result.title, result.description ?? "", result.url.absoluteString]
            .joined(separator: " ")
            .lowercased()
        var score = 0

        if connector.allows(url: result.url) {
            score += 100
        }
        if haystack.contains("flyer") || haystack.contains("weekly") || haystack.contains("deals") {
            score += 20
        }
        if haystack.contains("alberta") || haystack.contains("calgary") || haystack.contains("edmonton") {
            score += 10
        }
        if haystack.contains(connector.banner.name.lowercased()) {
            score += 5
        }

        return score
    }

    private func hostLabel(for url: URL) -> String {
        url.host ?? url.absoluteString
    }

    private func isExtractableSource(_ shape: FlyerSourceShape) -> Bool {
        switch shape {
        case .html, .pdf, .image, .json:
            true
        case .dynamicHTML, .unknown:
            false
        }
    }

    private func logLabel(for banner: FlyerBanner) -> String {
        "\(banner.rank)-\(banner.name.replacingOccurrences(of: " ", with: "_"))"
    }

    private func signalsLabel(for document: FlyerFetchedDocument) -> String {
        document.usefulnessSignals.isEmpty ? "none" : document.usefulnessSignals.joined(separator: "|")
    }

    private func snippetLabel(for document: FlyerFetchedDocument) -> String {
        guard let snippet = document.contentSnippet, !snippet.isEmpty else {
            return "none"
        }

        // Keep the log line readable; the full snippet (≤300 chars) lives on the
        // result model and the POC row.
        return "\"\(snippet.prefix(120))\""
    }

    private func unusableReason(for document: FlyerFetchedDocument) -> String {
        if !(200...299).contains(document.statusCode) {
            return "http-\(document.statusCode)"
        }

        if document.byteCount == 0 {
            return "empty-response"
        }

        return "unknown"
    }

    private func logDescription(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description.replacingOccurrences(of: "\n", with: " ")
        }

        return String(describing: error).replacingOccurrences(of: "\n", with: " ")
    }
}

protocol FlyerDiscoveryLogging {
    func log(_ message: String)
}

struct ConsoleFlyerDiscoveryLogger: FlyerDiscoveryLogging {
    func log(_ message: String) {
        print("[FlyerDiscovery] \(message)")
    }
}

enum FlyerDiscoveryLogRunID {
    static func make() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
