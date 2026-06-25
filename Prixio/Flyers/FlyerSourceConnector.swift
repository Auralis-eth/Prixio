import Foundation

struct FlyerSourceConnector: Identifiable, Equatable {
    let banner: FlyerBanner
    let officialEntryURLs: [URL]
    let allowedDomains: [String]
    let searchQueries: [String]
    let unsupportedReason: String?

    var id: FlyerBannerID { banner.id }

    var supportsKnownURLDiscovery: Bool {
        !officialEntryURLs.isEmpty && unsupportedReason == nil
    }

    func allows(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return allowedDomains.contains { domain in
            let normalized = domain.lowercased()
            return host == normalized || host.hasSuffix(".\(normalized)")
        }
    }
}

enum FlyerSourceConnectorCatalog {
    static let albertaConnectors: [FlyerSourceConnector] = FlyerBannerCatalog.albertaBanners.compactMap { banner in
        switch banner.id {
        case .realCanadianSuperstore:
            return connector(
                banner: banner,
                urls: [
                    "https://www.realcanadiansuperstore.ca/en/print-flyer",
                    "https://www.realcanadiansuperstore.ca/en/deals/flyer"
                ],
                allowedDomains: ["realcanadiansuperstore.ca"],
                queries: [
                    "Real Canadian Superstore Alberta flyer official",
                    "Real Canadian Superstore weekly flyer Calgary Edmonton official"
                ]
            )
        case .safeway:
            return connector(
                banner: banner,
                urls: [
                    "https://www.safeway.ca/flyer",
                    "https://www.safeway.ca/value-flyer"
                ],
                allowedDomains: ["safeway.ca"],
                queries: [
                    "Safeway Canada Alberta flyer official",
                    "Safeway weekly flyer Calgary Edmonton official"
                ]
            )
        case .sobeys:
            return connector(
                banner: banner,
                urls: ["https://www.sobeys.com/flyer"],
                allowedDomains: ["sobeys.com"],
                queries: [
                    "Sobeys Alberta flyer official",
                    "Sobeys weekly flyer Calgary Edmonton official"
                ]
            )
        case .costco:
            return connector(
                banner: banner,
                urls: [],
                allowedDomains: [],
                queries: [],
                unsupportedReason: "No accessible public grocery flyer source for v1; Costco only exposes a JS coupon shell."
            )
        case .walmartSupercentre:
            return connector(
                banner: banner,
                urls: ["https://www.walmart.ca/en/flyer"],
                allowedDomains: ["walmart.ca"],
                queries: [
                    "Walmart Canada Alberta flyer official",
                    "Walmart Canada weekly flyer Calgary Edmonton official"
                ]
            )
        case .noFrills:
            return connector(
                banner: banner,
                urls: [
                    "https://www.nofrills.ca/print-flyer",
                    "https://www.nofrills.ca/en/deals/flyer"
                ],
                allowedDomains: ["nofrills.ca"],
                queries: [
                    "No Frills Western Canada flyer official",
                    "No Frills Alberta weekly flyer official"
                ]
            )
        case .saveOnFoods:
            return connector(
                banner: banner,
                urls: ["https://www.saveonfoods.com/circular"],
                allowedDomains: ["saveonfoods.com"],
                queries: [
                    "Save-On-Foods Alberta flyer official",
                    "Save-On-Foods weekly flyer Calgary Edmonton official"
                ]
            )
        case .freshCo:
            return connector(
                banner: banner,
                urls: ["https://www.freshco.com/flyer"],
                allowedDomains: ["freshco.com"],
                queries: [
                    "FreshCo Alberta flyer official",
                    "Chalo FreshCo Alberta weekly flyer official"
                ]
            )
        case .coOp:
            return connector(
                banner: banner,
                urls: [
                    "https://www.calgarycoop.com/food/flyers/",
                    "https://www.food.crs/more/foodflyers"
                ],
                allowedDomains: ["calgarycoop.com", "food.crs", "co-op.crs"],
                queries: [
                    "Calgary Co-op food flyer official",
                    "Co-op food flyer Alberta official"
                ]
            )
        case .fresonBros:
            return connector(
                banner: banner,
                urls: [
                    "https://www.freson.com/weekly-flyer/",
                    "https://www.freson.com/flyers/"
                ],
                allowedDomains: ["freson.com"],
                queries: [
                    "Freson Bros weekly flyer official",
                    "Freson Bros Alberta flyer official"
                ]
            )
        }
    }

    private static func connector(
        banner: FlyerBanner,
        urls: [String],
        allowedDomains: [String],
        queries: [String],
        unsupportedReason: String? = nil
    ) -> FlyerSourceConnector {
        FlyerSourceConnector(
            banner: banner,
            officialEntryURLs: urls.compactMap(URL.init(string:)),
            allowedDomains: allowedDomains,
            searchQueries: queries,
            unsupportedReason: unsupportedReason
        )
    }
}
