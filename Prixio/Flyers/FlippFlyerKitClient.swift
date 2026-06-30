import Foundation

/// Fetches flyer items directly from Flipp's public legacy API (`flyers-ng.flippback.com`)
/// — the endpoint the `Kiizon/flippscrape` project uses, which needs only a postal code
/// and a random 16-digit session id (`sid`), no access token.
///
/// Two steps, verified against the live API:
/// 1. `…/api/flipp/data?locale=en&postal_code=<pc>&sid=<sid>` → `{"flyers":[…]}`, each
///    flyer carrying `id`, `merchant`, `merchant_id`, `valid_from`, `valid_to`.
/// 2. `…/api/flipp/flyers/<flyerID>/flyer_items?locale=en&sid=<sid>` → a JSON array of
///    items shaped `{name, brand, price, valid_from, valid_to, …}`.
///
/// This is the deterministic source for banners whose rendered widget never fetches
/// items in budget — notably Co-op (`merchant_id` 2051, "Calgary Co-op"), which loads
/// only its Flipp merchant config and never selects a publication. The returned items
/// JSON feeds the same `FlyerPriceExtractor` (endpointJSON) path as captured payloads.
struct FlippFlyerKitClient {
    var locale = "en"
    /// Random 16-digit session id, mirroring flippscrape. Injectable for tests.
    var makeSessionID: () -> String = { (0..<16).map { _ in String(Int.random(in: 0...9)) }.joined() }
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

    private let host = "https://flyers-ng.flippback.com/api/flipp"

    /// Resolves the merchant's current flyer for the postal code and returns its items
    /// JSON. `merchantID` is the Flipp `merchant_id` (e.g. Co-op 2051).
    func fetchItemsJSON(merchantID: Int, postalCode: String, now: Date = .now) async throws -> String {
        let sid = makeSessionID()
        let flyersData = try await fetch(dataURL(postalCode: postalCode, sid: sid))
        let flyers = try Self.parseFlyers(flyersData)
        guard let flyerID = Self.currentFlyerID(from: flyers, merchantID: merchantID, now: now) else {
            throw FlippFlyerKitError.noPublication
        }
        let itemsData = try await fetch(itemsURL(flyerID: flyerID, sid: sid))
        guard let json = String(data: itemsData, encoding: .utf8), !json.isEmpty else {
            throw FlippFlyerKitError.emptyProducts
        }
        return json
    }

    func dataURL(postalCode: String, sid: String) -> URL {
        var components = URLComponents(string: "\(host)/data")!
        components.queryItems = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "postal_code", value: postalCode),
            URLQueryItem(name: "sid", value: sid)
        ]
        return components.url!
    }

    func itemsURL(flyerID: Int, sid: String) -> URL {
        var components = URLComponents(string: "\(host)/flyers/\(flyerID)/flyer_items")!
        components.queryItems = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "sid", value: sid)
        ]
        return components.url!
    }

    private static func parseFlyers(_ data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let dict = object as? [String: Any], let flyers = dict["flyers"] as? [[String: Any]] {
            return flyers
        }
        if let array = object as? [[String: Any]] { return array }
        throw FlippFlyerKitError.badResponse
    }

    /// Among the merchant's flyers, the one whose validity window contains `now`; falls
    /// back to the merchant's first flyer (Flipp lists the current run first).
    static func currentFlyerID(from flyers: [[String: Any]], merchantID: Int, now: Date) -> Int? {
        var fallback: Int?
        for flyer in flyers where intValue(flyer["merchant_id"]) == merchantID {
            guard let id = intValue(flyer["id"]) else { continue }
            if fallback == nil { fallback = id }
            if let from = day(flyer["valid_from"]), let to = day(flyer["valid_to"]),
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
