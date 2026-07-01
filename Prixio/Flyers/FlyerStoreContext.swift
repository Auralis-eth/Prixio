import Foundation

/// A default geographic/store context for flyer acquisition. The banner APIs are
/// store/region-scoped — Flipp's `flyers-ng` takes a postal code, and pcexpress takes
/// a store id — so this supplies the location those queries resolve against.
struct FlyerStoreContext: Equatable {
    let provinceCode: String
    let city: String
    /// Postal code without a space, e.g. `T2P1J9`.
    let postalCode: String
    /// Postal code with the conventional space, e.g. `T2P 1J9`.
    let postalCodeSpaced: String
    let latitude: Double
    let longitude: Double

    var label: String { "\(provinceCode)/\(city)/\(postalCode)" }

    /// Downtown Calgary — a dense Alberta location every supported banner serves.
    static let defaultAlberta = FlyerStoreContext(
        provinceCode: "AB",
        city: "Calgary",
        postalCode: "T2P1J9",
        postalCodeSpaced: "T2P 1J9",
        latitude: 51.0447,
        longitude: -114.0719
    )
}

/// Per-banner instruction for which structured flyer endpoint serves a banner. Every
/// supported Alberta banner exposes its flyer through one of two public APIs; this maps
/// a banner to the id its API needs (all read from live API responses). Banners with
/// neither (Costco, Freson) have no endpoint and are handled as unsupported upstream.
struct FlyerStorePreparation: Equatable {
    /// The Flipp `merchant_id`, when this banner serves its flyer via Flipp's
    /// `flyers-ng.flippback.com` API (`FlippFlyerKitClient`).
    var flippMerchantID: Int? = nil
    /// The pcexpress banner + store, when this is a Loblaw banner whose flyer is served
    /// by the `api.pcexpress.ca` BFF (`PCExpressClient`).
    var pcExpress: PCExpressClient.BannerConfig? = nil
}

enum FlyerStorePreparationCatalog {
    /// Ids read from the live Flipp `data` / pcexpress `pickup-locations` responses
    /// (Calgary, T2P1J9). `context` is reserved for future region→store resolution.
    static func preparation(for banner: FlyerBannerID, context _: FlyerStoreContext) -> FlyerStorePreparation {
        switch banner {
        case .safeway:
            return FlyerStorePreparation(flippMerchantID: 2126)
        case .sobeys:
            return FlyerStorePreparation(flippMerchantID: 2072)
        case .freshCo:
            return FlyerStorePreparation(flippMerchantID: 2267)
        case .saveOnFoods:
            return FlyerStorePreparation(flippMerchantID: 2062)
        case .walmartSupercentre:
            return FlyerStorePreparation(flippMerchantID: 234)
        case .coOp:
            // Calgary Co-op — `food.crs` loads only its Flipp merchant config and never
            // selects a publication, so the direct flyers-ng fetch is its reliable source.
            return FlyerStorePreparation(flippMerchantID: 2051)
        case .realCanadianSuperstore:
            // Store 1521 is a Calgary superstore (verified live).
            return FlyerStorePreparation(
                pcExpress: PCExpressClient.BannerConfig(
                    siteBanner: "superstore",
                    storeID: "1521",
                    origin: "https://www.realcanadiansuperstore.ca"
                )
            )
        case .noFrills:
            // Store 6969 is "Cynthia's NOFRILLS Calgary" (870 11 St SW), verified live.
            return FlyerStorePreparation(
                pcExpress: PCExpressClient.BannerConfig(
                    siteBanner: "nofrills",
                    storeID: "6969",
                    origin: "https://www.nofrills.ca"
                )
            )
        case .costco, .fresonBros:
            // No structured flyer endpoint — handled as unsupported at discovery.
            return FlyerStorePreparation()
        }
    }
}
