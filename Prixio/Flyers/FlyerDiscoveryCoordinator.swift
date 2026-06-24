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
    let message: String

    var id: FlyerBannerID { banner.id }
}

final class FlyerDiscoveryCoordinator {
    private let connectors: [FlyerSourceConnector]
    private let fetcher: FlyerDocumentFetching
    private let searchProvider: FlyerSearchProviding

    init(
        connectors: [FlyerSourceConnector] = FlyerSourceConnectorCatalog.albertaConnectors,
        fetcher: FlyerDocumentFetching = URLSessionFlyerDocumentFetcher(),
        searchProvider: FlyerSearchProviding = BraveSearchProvider()
    ) {
        self.connectors = connectors.sorted { $0.banner.rank < $1.banner.rank }
        self.fetcher = fetcher
        self.searchProvider = searchProvider
    }

    func discoverSources() async -> [FlyerDiscoveryResult] {
        var results: [FlyerDiscoveryResult] = []
        for connector in connectors {
            results.append(await discoverSource(for: connector))
        }
        return results
    }

    private func discoverSource(for connector: FlyerSourceConnector) async -> FlyerDiscoveryResult {
        if let unsupportedReason = connector.unsupportedReason {
            return FlyerDiscoveryResult(
                banner: connector.banner,
                state: .unsupported,
                selectedURL: nil,
                method: nil,
                message: unsupportedReason
            )
        }

        if let knownURLResult = await firstUsableKnownURL(for: connector) {
            return knownURLResult
        }

        return await discoverWithSearchFallback(for: connector)
    }

    private func firstUsableKnownURL(for connector: FlyerSourceConnector) async -> FlyerDiscoveryResult? {
        for url in connector.officialEntryURLs where connector.allows(url: url) {
            do {
                let document = try await fetcher.fetch(url)
                guard document.isUsable else {
                    continue
                }

                return FlyerDiscoveryResult(
                    banner: connector.banner,
                    state: .found,
                    selectedURL: document.finalURL,
                    method: .knownURL,
                    message: "Official source returned HTTP \(document.statusCode) with \(document.byteCount) bytes."
                )
            } catch {
                continue
            }
        }

        return nil
    }

    private func discoverWithSearchFallback(for connector: FlyerSourceConnector) async -> FlyerDiscoveryResult {
        var sawMissingAPIKey = false
        var sawRejectedThirdParty = false

        for query in connector.searchQueries {
            do {
                let searchResults = try await searchProvider.search(query: query)
                for searchResult in rankedSearchResults(searchResults, for: connector) {
                    guard connector.allows(url: searchResult.url) else {
                        sawRejectedThirdParty = true
                        continue
                    }

                    do {
                        let document = try await fetcher.fetch(searchResult.url)
                        guard document.isUsable else {
                            continue
                        }

                        return FlyerDiscoveryResult(
                            banner: connector.banner,
                            state: .found,
                            selectedURL: document.finalURL,
                            method: .braveSearch,
                            message: "Brave fallback selected an official result from \(hostLabel(for: document.finalURL))."
                        )
                    } catch {
                        continue
                    }
                }
            } catch FlyerSearchError.missingAPIKey {
                sawMissingAPIKey = true
                break
            } catch {
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
}
