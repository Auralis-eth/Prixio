import Foundation

/// Fetches flyer items directly from Loblaw's public `pcexpress` backend-for-frontend
/// (`api.pcexpress.ca/pcx-bff`) — the deterministic source for the Loblaw banners
/// whose site is an Akamai bot-wall shell through WebKit (Real Canadian Superstore,
/// No Frills). It needs only the app's public web apikey and a store id; no bearer
/// token or user session.
///
/// Verified live against the API (superstore, Calgary store 1521):
/// `POST …/pcx-bff/api/v2/flyersPage` with a JSON body carrying the banner and a
/// `fulfillmentInfo.storeId`, returns a server-driven-UI (SDUI) document whose flyer
/// items live at
/// `layout.sections.productListingSection.components[*].data.productGrid.productTiles[]`,
/// each tile shaped `{title, brand, packageSizing, pricing:{price, wasPrice}, deal}`.
/// Paging is offset-based (`pagination.from`/`size`), with `pagination.totalResults`
/// and `hasMore` in the response.
///
/// Rather than hand the noisy SDUI blob to the extractor, this flattens the tiles into
/// the same clean `[{name, brand, price, regular_price, package_size, valid_to}]` item
/// array `FlippFlyerKitClient` returns, so both Loblaw and Flipp banners feed the one
/// `FlyerPriceExtractor` (endpointJSON) path unchanged.
struct PCExpressClient {
    /// Per-banner request identity. `siteBanner` is Loblaw's banner slug (e.g.
    /// `superstore`, `nofrills`); `origin` is the banner's storefront, sent as the
    /// `Origin`/`Referer` the BFF expects.
    struct BannerConfig: Equatable {
        let siteBanner: String
        let storeID: String
        let origin: String
    }

    /// The pcexpress web apikey — a public, client-side key hardcoded in Loblaw's own
    /// storefront bundles (not a user secret). Injectable for tests.
    var apiKey = "C1xujSegT5j3ap3yexJjqhOfELwGKYvz"
    var locale = "en"
    /// Injectable for tests; defaults to a bounded URLSession POST that returns the
    /// response body and throws on non-2xx.
    var fetch: (URLRequest) async throws -> Data = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PCExpressError.badResponse
        }
        return data
    }

    private let host = "https://api.pcexpress.ca/pcx-bff/api/v2/flyersPage"

    /// Fetches the banner's flyer items and returns them as a clean JSON array string
    /// the `FlyerPriceExtractor` mines.
    ///
    /// A single request: `flyersPage` returns a fixed 48-item featured slice of the flyer
    /// and ignores every paging/filter lever (`pagination.from`/`size`, `categoryId`,
    /// `filters`, …) — all verified live to return the identical 48 tiles. Those 48 are
    /// the flyer's front-page deals, which is the coverage that matters for list matching;
    /// deeper browsing would require a different (products-search) endpoint. Tiles are
    /// still deduped by product id in case one repeats within the slice.
    func fetchItemsJSON(config: BannerConfig) async throws -> String {
        let data = try await fetch(request(config: config))
        let (tiles, _) = try Self.parse(data)

        var items: [[String: Any]] = []
        var seenIDs = Set<String>()
        for tile in tiles {
            let id = tile.id ?? tile.name
            guard seenIDs.insert(id).inserted else { continue }
            items.append(tile.itemDictionary)
        }

        guard !items.isEmpty else { throw PCExpressError.emptyProducts }
        let json = try JSONSerialization.data(withJSONObject: items)
        guard let string = String(data: json, encoding: .utf8) else { throw PCExpressError.emptyProducts }
        return string
    }

    func request(config: BannerConfig) -> URLRequest {
        var request = URLRequest(url: URL(string: host)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        let headers = [
            "x-apikey": apiKey,
            "Site-Banner": config.siteBanner,
            "baseSiteId": config.siteBanner,
            "x-application-type": "Web",
            "x-loblaw-tenant-id": "ONLINE_GROCERIES",
            "Business-User-Agent": "PCXWEB",
            "is-helios-account": "true",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Accept-Language": locale,
            "Origin": config.origin,
            "Referer": config.origin + "/"
        ]
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        let body: [String: Any] = [
            "lang": locale,
            "banner": config.siteBanner,
            "fulfillmentInfo": [
                "storeId": config.storeID,
                "pickupType": "STORE",
                "offerType": "ALL"
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// A parsed flyer tile, reduced to the fields the extractor needs.
    struct Tile: Equatable {
        let id: String?
        let name: String
        let brand: String?
        let price: String?
        let regularPrice: String?
        let packageSize: String?
        let validTo: String?

        /// The clean item shape (matching Flipp `flyer_items`) the extractor consumes.
        var itemDictionary: [String: Any] {
            var dict: [String: Any] = ["name": name]
            if let brand, !brand.isEmpty { dict["brand"] = brand }
            if let price { dict["price"] = price }
            if let regularPrice { dict["regular_price"] = regularPrice }
            if let packageSize, !packageSize.isEmpty { dict["package_size"] = packageSize }
            if let validTo { dict["valid_to"] = validTo }
            return dict
        }
    }

    /// Extracts the flyer tiles and the `hasMore` flag from a `flyersPage` SDUI
    /// response. Tolerant of the layout nesting: it finds every `productGrid` with a
    /// `productTiles` array among the page's components.
    static func parse(_ data: Data) throws -> (tiles: [Tile], hasMore: Bool) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PCExpressError.badResponse
        }
        guard let components = (((root["layout"] as? [String: Any])?["sections"] as? [String: Any])?["productListingSection"] as? [String: Any])?["components"] as? [[String: Any]] else {
            throw PCExpressError.badResponse
        }

        var tiles: [Tile] = []
        var hasMore = false
        for component in components {
            guard let grid = (component["data"] as? [String: Any])?["productGrid"] as? [String: Any] else { continue }
            if let pagination = grid["pagination"] as? [String: Any], let more = pagination["hasMore"] as? Bool {
                hasMore = hasMore || more
            }
            guard let rawTiles = grid["productTiles"] as? [[String: Any]] else { continue }
            for raw in rawTiles {
                if let tile = tile(from: raw) { tiles.append(tile) }
            }
        }
        return (tiles, hasMore)
    }

    private static func tile(from raw: [String: Any]) -> Tile? {
        guard let name = (raw["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let pricing = raw["pricing"] as? [String: Any]
        let deal = raw["deal"] as? [String: Any]
        // `wasPrice` arrives as `"$1.77"`; keep just the number so the extractor reads
        // it as a clean regular price.
        let regular = string(pricing?["wasPrice"]).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "$ ")) }
        return Tile(
            id: raw["productId"] as? String,
            name: name,
            brand: raw["brand"] as? String,
            price: string(pricing?["price"]),
            regularPrice: regular,
            packageSize: raw["packageSizing"] as? String,
            validTo: deal?["expiryDate"] as? String
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

enum PCExpressError: Error, Equatable {
    case badResponse
    case emptyProducts
}
