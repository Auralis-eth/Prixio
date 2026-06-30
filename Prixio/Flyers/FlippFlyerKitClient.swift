import Foundation

/// Fetches flyer items directly from Flipp's public **flyerkit** REST API — the same
/// endpoints the on-page Flipp widget uses. Device diagnostics showed every Flipp
/// banner (Sobeys, Walmart, FreshCo, Save-On, Co-op) loads items from
/// `dam.flippenterprise.net/flyerkit/publication/<id>/products`, with a shared public
/// `access_token` and a per-merchant slug.
///
/// This is a deterministic fallback for banners whose rendered widget never fetches
/// products in budget — notably Co-op (`coopfood`), which loads only its merchant
/// config and never selects a publication. Returns the products JSON, which feeds the
/// same `FlyerPriceExtractor` (endpointJSON) path as captured payloads.
struct FlippFlyerKitClient {
    /// Public flyerkit access token observed across every Flipp banner's bundle URL
    /// (`aq.flippenterprise.net/a/<token>/lib/…`).
    var accessToken = "b349aa77564405f1fa8b432dc9d639e3258c6b9f"
    var locale = "en-ca"
    /// Injectable for tests; defaults to a bounded URLSession GET.
    var fetch: (URL) async throws -> Data = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("en-CA", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FlippFlyerKitError.badResponse
        }
        return data
    }

    private let host = "https://dam.flippenterprise.net/flyerkit"

    /// Resolves the merchant's current publication and returns its products JSON.
    func fetchProductsJSON(merchant: String, postalCode: String, now: Date = .now) async throws -> String {
        let publicationsData = try await fetch(publicationsURL(merchant: merchant, postalCode: postalCode))
        let publications = try Self.parseArray(publicationsData)
        guard let publicationID = Self.currentPublicationID(from: publications, now: now) else {
            throw FlippFlyerKitError.noPublication
        }
        let productsData = try await fetch(productsURL(publicationID: publicationID))
        guard let json = String(data: productsData, encoding: .utf8), !json.isEmpty else {
            throw FlippFlyerKitError.emptyProducts
        }
        return json
    }

    func publicationsURL(merchant: String, postalCode: String) -> URL {
        var components = URLComponents(string: "\(host)/publications/\(merchant)")!
        components.queryItems = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "access_token", value: accessToken),
            URLQueryItem(name: "postal_code", value: postalCode)
        ]
        return components.url!
    }

    func productsURL(publicationID: Int) -> URL {
        var components = URLComponents(string: "\(host)/publication/\(publicationID)/products")!
        components.queryItems = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "access_token", value: accessToken)
        ]
        return components.url!
    }

    private static func parseArray(_ data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let array = object as? [[String: Any]] { return array }
        // Some flyerkit responses wrap the list, e.g. {"publications":[…]}.
        if let dict = object as? [String: Any] {
            for value in dict.values {
                if let array = value as? [[String: Any]] { return array }
            }
        }
        throw FlippFlyerKitError.badResponse
    }

    /// Picks the publication whose validity window contains `now`; falls back to the
    /// first one with an id (Flipp lists the current flyer first).
    static func currentPublicationID(from publications: [[String: Any]], now: Date) -> Int? {
        var fallback: Int?
        for publication in publications {
            guard let id = intValue(publication["id"]) else { continue }
            if fallback == nil { fallback = id }
            if let from = day(publication["valid_from"]), let to = day(publication["valid_to"]),
               now >= from, now < to.addingTimeInterval(86_400) {
                return id
            }
        }
        return fallback
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static func day(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return dayFormatter.date(from: String(string.prefix(10)))
    }
}

enum FlippFlyerKitError: Error, Equatable {
    case badResponse
    case noPublication
    case emptyProducts
}
