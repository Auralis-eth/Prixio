import Foundation

struct FlyerFetchedDocument: Equatable {
    let finalURL: URL
    let statusCode: Int
    let mimeType: String?
    let byteCount: Int

    var isUsable: Bool {
        (200...299).contains(statusCode) && byteCount > 0
    }
}

protocol FlyerDocumentFetching {
    func fetch(_ url: URL) async throws -> FlyerFetchedDocument
}

enum FlyerDocumentFetchError: LocalizedError, Equatable {
    case nonHTTPResponse

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            "The source did not return an HTTP response."
        }
    }
}

final class URLSessionFlyerDocumentFetcher: FlyerDocumentFetching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(_ url: URL) async throws -> FlyerFetchedDocument {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("Prixio/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlyerDocumentFetchError.nonHTTPResponse
        }

        return FlyerFetchedDocument(
            finalURL: httpResponse.url ?? url,
            statusCode: httpResponse.statusCode,
            mimeType: httpResponse.mimeType,
            byteCount: data.count
        )
    }
}
