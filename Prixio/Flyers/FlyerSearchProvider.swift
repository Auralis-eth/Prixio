import Foundation

struct FlyerSearchResult: Equatable {
    let title: String
    let url: URL
    let description: String?
}

protocol FlyerSearchProviding {
    func search(query: String) async throws -> [FlyerSearchResult]
}

enum FlyerSearchError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidRequest
    case nonHTTPResponse
    case unsuccessfulStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Brave Search API key is missing."
        case .invalidRequest:
            "The search request could not be created."
        case .nonHTTPResponse:
            "The search provider did not return an HTTP response."
        case .unsuccessfulStatus(let status):
            "The search provider returned HTTP \(status)."
        }
    }
}

enum BraveSearchConfiguration {
    static var apiKey: String? {
        let environmentValue = ProcessInfo.processInfo.environment["BRAVE_SEARCH_API_KEY"]
        if let key = usableAPIKey(environmentValue) {
            return key
        }

        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "BRAVE_SEARCH_API_KEY") as? String
        return usableAPIKey(bundleValue)
    }

    static var hasUsableAPIKey: Bool {
        apiKey != nil
    }

    private static func usableAPIKey(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("$(") else {
            return nil
        }

        return trimmed
    }
}

final class BraveSearchProvider: FlyerSearchProviding {
    private let apiKeyProvider: () -> String?
    private let session: URLSession
    private let endpoint: URL

    init(
        apiKeyProvider: @escaping () -> String? = { BraveSearchConfiguration.apiKey },
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.search.brave.com/res/v1/web/search")!
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.endpoint = endpoint
    }

    func search(query: String) async throws -> [FlyerSearchResult] {
        guard let apiKey = apiKeyProvider() else {
            throw FlyerSearchError.missingAPIKey
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw FlyerSearchError.invalidRequest
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "country", value: "ca"),
            URLQueryItem(name: "search_lang", value: "en"),
            URLQueryItem(name: "count", value: "5")
        ]

        guard let url = components.url else {
            throw FlyerSearchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlyerSearchError.nonHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FlyerSearchError.unsuccessfulStatus(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(BraveSearchResponse.self, from: data)
        return decoded.web?.results.compactMap { result in
            guard let url = URL(string: result.url) else {
                return nil
            }

            return FlyerSearchResult(
                title: result.title,
                url: url,
                description: result.description
            )
        } ?? []
    }
}

private struct BraveSearchResponse: Decodable {
    let web: BraveWebResults?
}

private struct BraveWebResults: Decodable {
    let results: [BraveWebResult]
}

private struct BraveWebResult: Decodable {
    let title: String
    let url: String
    let description: String?
}
