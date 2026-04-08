import Foundation
import Testing
import UIKit
@testable import Prixio

@MainActor
struct ImageFixtureParsingTests {
    struct FixtureContractCase {
        let name: String
        let fixtureName: String
        let expectedOCRLines: [String]?
        let expectedItemName: String
        let expectedPrice: Decimal?
        let expectedUnit: UnitType?
        let expectedQuantity: Decimal?
        let expectedReviewState: OCRReviewState
        let expectsFoundationModel: Bool
        let expectedPriceCandidates: [Decimal]?
        let expectedSupportingLines: [String]?
    }

    static let strictFixtureContracts = [
        FixtureContractCase(
            name: "cadbury shelf tag screenshot",
            fixtureName: "Screenshot 2026-04-02 at 3.53.44 PM",
            expectedOCRLines: [
                "3:53",
                "•l.%°",
                "Min",
                "E99Ş",
                "Rogers",
                "Rogers • 385 m",
                "Сабвичи",
                "Min",
                "Egg",
                "Саб",
                "Mude",
                "EggS",
                "Satury,",
                "Mini",
                "EggS",
                "-Сабвичи,",
                "Mifi",
                "Eggs'",
                "Cadbury Chocolate Mini",
                "Eggs Easter 875 g",
                "SAVE",
                "THIS WEEK",
                "22\"9",
                "Exo Mar 04, 2026",
                "1799",
                "SAVE",
                "S5.00 ea",
                "босочу",
                "Eggs",
                "MInI",
                "1Egg$",
                "Sure",
                "Min",
                "Сабвичо",
                "Mint",
                "2995",
                "говичу.",
                "Mir",
                "5g",
                "1001",
                "Сабвичу",
                "Eggs",
                "Саббич",
                "E",
                "Scan",
                "Items",
                "Trends",
                "Settings",
                "int",
                "E99"
            ],
            expectedItemName: "Mifi Eggs",
            expectedPrice: nil,
            expectedUnit: .each,
            expectedQuantity: nil,
            expectedReviewState: .reviewRequired,
            expectsFoundationModel: true,
            expectedPriceCandidates: nil,
            expectedSupportingLines: nil
        ),
        FixtureContractCase(
            name: "broxburn lettuce tag with cucumber neighbor",
            fixtureName: "IMG_0472",
            expectedOCRLines: [
                "BROXBURN",
                "VEGETABLES",
                "LE CUCUMBER",
                "platters, salads",
                "$6.00",
                "bac",
                "MINI CUCUMBER",
                "$4.00",
                "ALLIVING *",
                "LAJ",
                "BKUXBUKN",
                "IGETABLES",
                "Butterleuf Lettuce",
                "$ 4.50/each",
                "HOVIVILA301",
                "SOCALE",
                "NAIT",
                "Multileaf Lettuce",
                "4.25"
            ],
            expectedItemName: "Butterleuf Lettuce",
            expectedPrice: Decimal(string: "4.5")!,
            expectedUnit: .each,
            expectedQuantity: nil,
            expectedReviewState: .reviewRequired,
            expectsFoundationModel: true,
            expectedPriceCandidates: [
                Decimal(string: "4.5")!,
                Decimal(string: "4.25")!
            ],
            expectedSupportingLines: ["$ 4.50/each"]
        ),
        FixtureContractCase(
            name: "mini cucumber produce card",
            fixtureName: "IMG_0473",
            expectedOCRLines: [
                "MINI CUCUMBER",
                "Perfect for snacking",
                "High water content helps to keep you",
                "hydrated",
                "$4.00"
            ],
            expectedItemName: "MINI CUCUMBER",
            expectedPrice: Decimal(string: "4")!,
            expectedUnit: nil,
            expectedQuantity: nil,
            expectedReviewState: .reviewRecommended,
            expectsFoundationModel: false,
            expectedPriceCandidates: [Decimal(4)],
            expectedSupportingLines: [
                "MINI CUCUMBER",
                "Perfect for snacking",
                "High water content helps to keep you",
                "hydrated",
                "$4.00"
            ]
        ),
        FixtureContractCase(
            name: "old dutch chips shelf block",
            fixtureName: "IMG_0474",
            expectedOCRLines: nil,
            expectedItemName: "Ry Sea Salt Malt Vines",
            expectedPrice: Decimal(string: "4.99")!,
            expectedUnit: .each,
            expectedQuantity: nil,
            expectedReviewState: .clean,
            expectsFoundationModel: false,
            expectedPriceCandidates: [Decimal(string: "4.99")!],
            expectedSupportingLines: [
                "JUTCH",
                "CRUNCE",
                "COOKED / MARMITE",
                "CUTES!",
                "Mesquite BBO",
                "SHARE BBQ mesquite",
                "Dutch Crunch Potato",
                "Chips Selected Varieties",
                "200g",
                "Made in Canada",
                "ELEBRATING",
                "499",
                "O YEARS",
                "DUTCE",
                "WATER",
                "GINGER ALE",
                "SPARKLIN",
                "LOOKED",
                "Jalapeño",
                "KETTLE / CUITES IL",
                "12 x 355 mL CANS",
                "Cheddar.",
                "Old Dutch",
                "CELEBRATING",
                "Ginger Ale 355 ml",
                "Compliments Sparkling",
                "RUNCI",
                "JUICE",
                "SAVE",
                "THIS WEEK",
                "Ry Sea Salt & Malt Vines",
                "«e mer Bi vinaigre de to",
                "Set de mer et vinaigre de mal",
                "Sea Salt & Malt Vinegar",
                "el de mer et vinaigte",
                "a Salt & Mall V",
                "SPARKING",
                "SPARTING",
                "NO SWEETENERS"
            ]
        ),
        FixtureContractCase(
            name: "cropped old dutch price fragment",
            fixtureName: "IMG_0475",
            expectedOCRLines: nil,
            expectedItemName: "CRUNC",
            expectedPrice: Decimal(string: "4.99")!,
            expectedUnit: nil,
            expectedQuantity: nil,
            expectedReviewState: .reviewRequired,
            expectsFoundationModel: true,
            expectedPriceCandidates: [Decimal(string: "4.99")!],
            expectedSupportingLines: ["$4.99"]
        ),
        FixtureContractCase(
            name: "salad kit packaging noise",
            fixtureName: "IMG_0476",
            expectedOCRLines: nil,
            expectedItemName: "CHOPPED KIT • SALADE HACHEE with A VEGETABLE BLEND, SUNFLOWER SEEDS, COOKED BACON with Sweet Onion Dressing CONTIENT MELANGE DE LÉGUMENT STAINES BE TOURNESEL BALOR CUIT cuec Vinaigrete DINS CONTE SAND CONTEN Scene* PRICING ATLONTY Chopped or Leafy Salad Kits TaylpI oduct Produs product of USA 207-383 g FARMS Card without MEMBERS SAVEUp to 49% wlapenc BUTY Popper THEY Appe CHOPA VEGETA CRISPY T OPPED KIT! yeau HELL BEND, SH HONIONS",
            expectedPrice: nil,
            expectedUnit: .each,
            expectedQuantity: nil,
            expectedReviewState: .reviewRequired,
            expectsFoundationModel: true,
            expectedPriceCandidates: [],
            expectedSupportingLines: [
                "CHOPPED KIT • SALADE HACHEE",
                "with A",
                "VEGETABLE BLEND, SUNFLOWER SEEDS, COOKED BACON",
                "with Sweet Onion Dressing",
                "& CONTIENT",
                "MELANGE DE LÉGUMENT",
                "STAINES BE TOURNESEL BALOR CUIT",
                "cuec Vinaigrete",
                "DINS CONTE",
                "SAND CONTEN",
                "Scene*",
                "MEMBER",
                "PRICING",
                "ATLONTY",
                "Chopped or Leafy Salad",
                "Kits",
                "TaylpI",
                "oduct",
                "Produs",
                "product of USA 207-383 g",
                "FARMS",
                "Card",
                "without",
                "each",
                "MEMBERS SAVEUp to 49%",
                "Exp. March 4, 2026",
                "wlapenc",
                "BUTY",
                "Popper",
                "THEY",
                "Appe",
                "CHOPA",
                "VEGETA",
                "CRISPY T",
                "OPPED KIT!",
                "yeau",
                "HELL BEND, SH",
                "HONIONS"
            ]
        ),
        FixtureContractCase(
            name: "banana shelf tag picks plu as price",
            fixtureName: "IMG_0477",
            expectedOCRLines: [
                ".99",
                ") 247",
                "545 / Kg",
                "Bananas Stage 4 PLU 4011",
                ".79.-"
            ],
            expectedItemName: "Bananas Stage 4 PLU 4011",
            expectedPrice: Decimal(string: "40.11")!,
            expectedUnit: .kg,
            expectedQuantity: nil,
            expectedReviewState: .reviewRecommended,
            expectsFoundationModel: false,
            expectedPriceCandidates: [
                Decimal(string: "40.11")!,
                Decimal(string: "5.45")!,
                Decimal(string: "2.47")!
            ],
            expectedSupportingLines: [
                ".99",
                "Bananas Stage 4 PLU 4011",
                ") 247",
                "545 / Kg",
                ".79.-"
            ]
        ),
        FixtureContractCase(
            name: "jalapeno tomatillo partial produce card",
            fixtureName: "IMG_0478",
            expectedOCRLines: [
                "TOMATILL!",
                "PEPPERS",
                "Salade",
                "JALAPENO",
                "PEPPERS",
                "AMENT SALAPENC",
                "SPECTAL",
                "299",
                "GARDEN",
                "QUEEN.",
                "GARDEN",
                "QUEEN."
            ],
            expectedItemName: "PEPPERS",
            expectedPrice: nil,
            expectedUnit: nil,
            expectedQuantity: nil,
            expectedReviewState: .reviewRequired,
            expectsFoundationModel: true,
            expectedPriceCandidates: [],
            expectedSupportingLines: ["TOMATILL!"]
        ),
        FixtureContractCase(
            name: "sparse grower label",
            fixtureName: "IMG_0479",
            expectedOCRLines: [
                "1908.0",
                "HGROWER. COM YE",
                "299",
                "299"
            ],
            expectedItemName: "HGROWER. COM YE",
            expectedPrice: Decimal(string: "2.99")!,
            expectedUnit: nil,
            expectedQuantity: nil,
            expectedReviewState: .reviewRecommended,
            expectsFoundationModel: false,
            expectedPriceCandidates: [
                Decimal(string: "2.99")!,
                Decimal(string: "19.08")!
            ],
            expectedSupportingLines: [
                "1908.0",
                "HGROWER. COM YE",
                "299"
            ]
        ),
        FixtureContractCase(
            name: "pressata salami wrong winner",
            fixtureName: "IMG_0480",
            expectedOCRLines: nil,
            expectedItemName: "Mastro Genoa Salami PRESSATA Prosciutto",
            expectedPrice: Decimal(string: "5.42")!,
            expectedUnit: nil,
            expectedQuantity: nil,
            expectedReviewState: .reviewRequired,
            expectsFoundationModel: true,
            expectedPriceCandidates: [
                Decimal(string: "54")!,
                Decimal(string: "5.42")!,
                Decimal(string: "4.1")!,
                Decimal(string: "1")!
            ],
            expectedSupportingLines: [
                "Mastro Genoa Salami",
                "542",
                "PRESSATA",
                "Prosciutto"
            ]
        ),
        FixtureContractCase(
            name: "oral care aisle quantity disaster",
            fixtureName: "IMG_0482",
            expectedOCRLines: nil,
            expectedItemName: "40 g REPARE Brilliant INTENSIVE ENAMEL With triple cleaning action EXTRA FRESH rest AVANCÉ FRAÎCHEUR ARCTIQUE LA MARQUE LA PLUS RECOMMANDÉE PAR LES DENTISTES* UN BLANCHIMENT 2 FOIS PLUS RAPT ACHES DE SURF Blanchissant PRONAMEL REPAIR For Sironger, Heaty Tota AO8-R07-4 75 ml SENDOUIN LOUR LA PROTECER- ENDED BRAND• •1 DENTIST RECOMMENDED BRAND• MIERDED BRAND* CLEAN MINT",
            expectedPrice: Decimal(string: "100")!,
            expectedUnit: .hundredGrams,
            expectedQuantity: Decimal(string: "9867")!,
            expectedReviewState: .reviewRequired,
            expectsFoundationModel: true,
            expectedPriceCandidates: [
                Decimal(string: "100")!,
                Decimal(string: "100")!,
                Decimal(string: "18.72")!,
                Decimal(string: "11.98")!,
                Decimal(string: "5.99")!,
                Decimal(string: "4.75")!,
                Decimal(string: "17.49")!,
                Decimal(string: "9.19")!,
                Decimal(string: "7.49")!,
                Decimal(string: "4.49")!
            ],
            expectedSupportingLines: [
                "40 g",
                "1749",
                "749",
                "REPARE",
                "Brilliant",
                "INTENSIVE ENAMEL",
                "With triple cleaning action",
                "EXTRA FRESH",
                "rest",
                "AVANCÉ",
                "FRAÎCHEUR ARCTIQUE",
                "LA MARQUE LA PLUS RECOMMANDÉE PAR LES DENTISTES*",
                "• UN BLANCHIMENT 2 FOIS PLUS RAPT",
                "ACHES DE SURF",
                "Blanchissant",
                "PRONAMEL REPAIR",
                "For Sironger, Heaty Tota",
                "AO8-R07-4",
                "75 ml",
                "EAD Mar 04, 2026",
                "11.9867 /100ML",
                "Mar 04, 2026",
                "SENDOUIN",
                "449",
                "5.9900 /100ML",
                "LOUR LA PROTECER-",
                "ENDED BRAND•",
                "•1 DENTIST RECOMMENDED BRAND•",
                "MIERDED BRAND*",
                "CLEAN MINT"
            ]
        ),
        FixtureContractCase(
            name: "butter shelf multi-product image",
            fixtureName: "IMG_0483",
            expectedOCRLines: nil,
            expectedItemName: "Comp Butter Salted",
            expectedPrice: Decimal(string: "5.99")!,
            expectedUnit: .each,
            expectedQuantity: nil,
            expectedReviewState: .clean,
            expectsFoundationModel: false,
            expectedPriceCandidates: [Decimal(string: "5.99")!],
            expectedSupportingLines: ["Comp Butter Salted", "454 g", "599"]
        )
    ]

    func assertStrictFixtureContract(_ contract: FixtureContractCase) async throws {
        let image = try ImageFixtureTestSupport.loadImage(named: contract.fixtureName)
        let observations = try await ImageFixtureTestSupport.extractObservations(from: image)
        let result = await PriceParsingService.extract(from: observations)

        if let expectedOCRLines = contract.expectedOCRLines {
            let observedLines = Set(observations.map(\.string))
            #expect(observations.isEmpty == false, Comment(rawValue: contract.name))
            #expect(expectedOCRLines.contains(where: observedLines.contains), Comment(rawValue: contract.name))
        }

        #expect(observations.isEmpty == false, Comment(rawValue: contract.name))
        #expect(result.supportingLines.isEmpty == false, Comment(rawValue: contract.name))

        if let expectedPriceCandidates = contract.expectedPriceCandidates, expectedPriceCandidates.isEmpty == false {
            let observedPrices = Set(result.priceCandidates.map(\.value) + (result.price.map { [$0] } ?? []))
            #expect(
                expectedPriceCandidates.contains(where: observedPrices.contains),
                Comment(rawValue: contract.name)
            )
        }
        if let expectedSupportingLines = contract.expectedSupportingLines {
            let observedEvidence = Set(result.supportingLines + observations.map(\.string))
            #expect(result.supportingLines.isEmpty == false, Comment(rawValue: contract.name))
            #expect(expectedSupportingLines.contains(where: observedEvidence.contains), Comment(rawValue: contract.name))
        }
    }

    @Test(
        .tags(.ocr, .product, .evaluation, .realWorldOCR),
        arguments: strictFixtureContracts
    )
    func strictLiveFixtureContracts(case contract: FixtureContractCase) async throws {
        try await assertStrictFixtureContract(contract)
    }
}
