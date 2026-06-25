import Foundation

enum FlyerDiscoveryMethod: String, Equatable {
    case knownURL = "Known URL"
    case braveSearch = "Brave Search"
}

enum FlyerDiscoveryState: Equatable {
    case found
    case fallbackUnavailable
    case unsupported
    case failed

    var label: String {
        switch self {
        case .found:
            "Found"
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

    var id: FlyerBannerID { banner.id }

    init(
        banner: FlyerBanner,
        state: FlyerDiscoveryState,
        selectedURL: URL?,
        method: FlyerDiscoveryMethod?,
        sourceShape: FlyerSourceShape? = nil,
        message: String
    ) {
        self.banner = banner
        self.state = state
        self.selectedURL = selectedURL
        self.method = method
        self.sourceShape = sourceShape
        self.message = message
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
        let fallbackUnavailableCount = results.filter { $0.state == .fallbackUnavailable }.count
        let failedCount = results.filter { $0.state == .failed }.count
        let unsupportedCount = results.filter { $0.state == .unsupported }.count
        logger.log("run=\(runID) phase=finish found=\(foundCount) fallbackUnavailable=\(fallbackUnavailableCount) failed=\(failedCount) unsupported=\(unsupportedCount)")

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

        if let knownURLResult = await firstUsableKnownURL(for: connector, runID: runID) {
            logger.log("run=\(runID) banner=\(bannerLabel) phase=banner-finish state=\(knownURLResult.state.label) method=\(knownURLResult.method?.rawValue ?? "none") shape=\(knownURLResult.sourceShape?.rawValue ?? "none") selectedURL=\(knownURLResult.selectedURL?.absoluteString ?? "none") message=\(knownURLResult.message)")
            return knownURLResult
        }

        let fallbackResult = await discoverWithSearchFallback(for: connector, runID: runID)
        logger.log("run=\(runID) banner=\(bannerLabel) phase=banner-finish state=\(fallbackResult.state.label) method=\(fallbackResult.method?.rawValue ?? "none") shape=\(fallbackResult.sourceShape?.rawValue ?? "none") selectedURL=\(fallbackResult.selectedURL?.absoluteString ?? "none") message=\(fallbackResult.message)")
        return fallbackResult
    }

    private func firstUsableKnownURL(for connector: FlyerSourceConnector, runID: String) async -> FlyerDiscoveryResult? {
        let bannerLabel = logLabel(for: connector.banner)
        for url in connector.officialEntryURLs {
            guard connector.allows(url: url) else {
                logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-rejected reason=domain-not-allowed attemptedURL=\(url.absoluteString)")
                continue
            }

            logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-fetch-start attemptedURL=\(url.absoluteString)")
            do {
                let document = try await fetcher.fetch(url)
                logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-fetch-finish attemptedURL=\(url.absoluteString) finalURL=\(document.finalURL.absoluteString) status=\(document.statusCode) mime=\(document.mimeType ?? "unknown") bytes=\(document.byteCount) shape=\(document.sourceShape.rawValue) usable=\(document.isUsable) signals=\(signalsLabel(for: document)) snippet=\(snippetLabel(for: document))")
                guard document.isUsable else {
                    logger.log("run=\(runID) banner=\(bannerLabel) phase=known-url-unusable reason=\(unusableReason(for: document)) attemptedURL=\(url.absoluteString)")
                    continue
                }

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
                continue
            }
        }

        logger.log("run=\(runID) banner=\(bannerLabel) phase=known-urls-exhausted")
        return nil
    }

    private func discoverWithSearchFallback(for connector: FlyerSourceConnector, runID: String) async -> FlyerDiscoveryResult {
        let bannerLabel = logLabel(for: connector.banner)
        var sawMissingAPIKey = false
        var sawRejectedThirdParty = false

        for query in connector.searchQueries {
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
                        continue
                    }

                    logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-fetch-start score=\(score) title=\(searchResult.title) url=\(searchResult.url.absoluteString)")
                    do {
                        let document = try await fetcher.fetch(searchResult.url)
                        logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-fetch-finish attemptedURL=\(searchResult.url.absoluteString) finalURL=\(document.finalURL.absoluteString) status=\(document.statusCode) mime=\(document.mimeType ?? "unknown") bytes=\(document.byteCount) shape=\(document.sourceShape.rawValue) usable=\(document.isUsable) signals=\(signalsLabel(for: document)) snippet=\(snippetLabel(for: document))")
                        guard document.isUsable else {
                            logger.log("run=\(runID) banner=\(bannerLabel) phase=search-result-unusable reason=\(unusableReason(for: document)) attemptedURL=\(searchResult.url.absoluteString)")
                            continue
                        }

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
