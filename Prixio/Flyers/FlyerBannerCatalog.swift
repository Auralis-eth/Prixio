import Foundation

struct FlyerBanner: Identifiable, Equatable {
    let id: FlyerBannerID
    let rank: Int
    let name: String
    let parentType: String
    let albertaRationale: String
}

enum FlyerBannerID: String, CaseIterable, Identifiable {
    case realCanadianSuperstore
    case safeway
    case sobeys
    case costco
    case walmartSupercentre
    case noFrills
    case saveOnFoods
    case freshCo
    case coOp
    case fresonBros

    var id: String { rawValue }
}

enum FlyerBannerCatalog {
    static let albertaBanners: [FlyerBanner] = [
        FlyerBanner(
            id: .realCanadianSuperstore,
            rank: 1,
            name: "Real Canadian Superstore",
            parentType: "Loblaw",
            albertaRationale: "Big-format, price-focused, very common in Calgary and Edmonton."
        ),
        FlyerBanner(
            id: .safeway,
            rank: 2,
            name: "Safeway",
            parentType: "Sobeys / Empire",
            albertaRationale: "One of Alberta's strongest full-service grocery banners; Safeway's Canadian head office is in Calgary."
        ),
        FlyerBanner(
            id: .sobeys,
            rank: 3,
            name: "Sobeys",
            parentType: "Sobeys / Empire",
            albertaRationale: "Major full-service national grocery chain; Sobeys owns banners including Safeway, FreshCo, IGA West, Foodland, and Thrifty Foods."
        ),
        FlyerBanner(
            id: .costco,
            rank: 4,
            name: "Costco",
            parentType: "Costco Wholesale",
            albertaRationale: "High grocery volume, especially for families; Costco lists 18 Alberta warehouses."
        ),
        FlyerBanner(
            id: .walmartSupercentre,
            rank: 5,
            name: "Walmart Supercentre",
            parentType: "Walmart Canada",
            albertaRationale: "Major grocery competitor in Alberta, especially for pantry, household, and low-price basics."
        ),
        FlyerBanner(
            id: .noFrills,
            rank: 6,
            name: "No Frills",
            parentType: "Loblaw",
            albertaRationale: "Key discount banner with a large Alberta footprint."
        ),
        FlyerBanner(
            id: .saveOnFoods,
            rank: 7,
            name: "Save-On-Foods",
            parentType: "Pattison Food Group",
            albertaRationale: "Strong Western Canada chain; Calgary alone has 10 locations listed by Save-On-Foods."
        ),
        FlyerBanner(
            id: .freshCo,
            rank: 8,
            name: "FreshCo / Chalo! FreshCo",
            parentType: "Sobeys / Empire",
            albertaRationale: "Discount grocery banner expanding in Alberta, with locations including Calgary, Edmonton, Fort McMurray, Okotoks, and others."
        ),
        FlyerBanner(
            id: .coOp,
            rank: 9,
            name: "Co-op / Calgary Co-op",
            parentType: "Co-operative",
            albertaRationale: "Very important locally, especially Calgary and surrounding towns; Calgary Co-op lists locations in Calgary, Airdrie, Cochrane, High River, Okotoks, and Strathmore."
        ),
        FlyerBanner(
            id: .fresonBros,
            rank: 10,
            name: "Freson Bros.",
            parentType: "Alberta-owned independent",
            albertaRationale: "Probably Alberta's most important local independent grocery brand; it describes itself as Alberta grown, Alberta owned, and family operated since 1955."
        )
    ]

    static func banner(for id: FlyerBannerID) -> FlyerBanner? {
        albertaBanners.first { $0.id == id }
    }
}
