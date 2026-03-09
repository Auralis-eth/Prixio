//
//  PriceParsingServiceDataSanitation.swift
//  PrixioTests
//
//  Created by Daniel Bell on 3/7/26.
//

import Foundation
import Testing
@testable import Prixio

extension Tag {
    @Tag static var ocr: Self
    @Tag static var product: Self
}

struct PriceParsingServiceDataSanitation {

    struct ConsolidateObservations {
//=====================================
        @Test(
            .tags(.ocr, .product),
            arguments: [
                ConsolidationTestCase(
                    input: [OCRTextObservation(string: "Old Dutch Chips", confidence: 0.7)],
                    expectedConsolidationSize: 1,
                    expectedConsolidationString: ["Old Dutch Chips"],
                    unexpectedConsolidationString: nil
                ),
                ConsolidationTestCase(
                    input: [],
                    expectedConsolidationSize: 0,
                    expectedConsolidationString: nil,
                    unexpectedConsolidationString: nil
                ),
                ConsolidationTestCase(
                    input: [
                        OCRTextObservation(string: "Mini Eggs", confidence: 0.2),
                        OCRTextObservation(string: "Mini Eggs", confidence: 0.9)
                    ],
                    expectedConsolidationSize: 1,
                    expectedConsolidationString: ["Mini Eggs"],
                    unexpectedConsolidationString: nil
                ),
                ConsolidationTestCase(
                    input: [
                        OCRTextObservation(string: "mini eggs", confidence: 0.2),
                        OCRTextObservation(string: "Mini   Eggs", confidence: 0.6),
                        OCRTextObservation(string: "Mini-Eggs", confidence: 0.3),
                        OCRTextObservation(string: "Mini Eggs", confidence: 0.8)
                    ],
                    expectedConsolidationSize: 1,
                    expectedConsolidationString: ["Mini Eggs"],
                    unexpectedConsolidationString: nil
                ),
                ConsolidationTestCase(
                    input: [
                        OCRTextObservation(string: "Cadbury", confidence: 0.6),
                        OCRTextObservation(string: "Cadbury", confidence: 0.8),
                        OCRTextObservation(string: "Cadbary", confidence: 0.5)
                    ],
                    expectedConsolidationSize: 1,
                    expectedConsolidationString: ["Cadbury"],
                    unexpectedConsolidationString: nil
                ),
                ConsolidationTestCase(
                    input: [
                        OCRTextObservation(string: "Mint", confidence: 0.6),
                        OCRTextObservation(string: "Hint", confidence: 0.6)
                    ],
                    expectedConsolidationSize: 2,
                    expectedConsolidationString: ["Mint", "Hint"],
                    unexpectedConsolidationString: nil
                ),
                ConsolidationTestCase(
                    input: [
                        OCRTextObservation(string: "Diet Cola", confidence: 0.8),
                        OCRTextObservation(string: "Regular Cola", confidence: 0.8)
                    ],
                    expectedConsolidationSize: 2,
                    expectedConsolidationString: ["Diet Cola", "Regular Cola"],
                    unexpectedConsolidationString: nil
                ),
                ConsolidationTestCase(
                    input: [
                        OCRTextObservation(string: "Old Dutch Chips", confidence: 0.9),
                        OCRTextObservation(string: "old dutch chips", confidence: 0.7),
                        OCRTextObservation(string: "Old Dutch Chips", confidence: 0.8),
                        OCRTextObservation(string: "Compliments Sparkling Water", confidence: 0.9),
                        OCRTextObservation(string: "Compliments Sparkli Water", confidence: 0.5),
                        OCRTextObservation(string: "2/$5", confidence: 0.9),
                        OCRTextObservation(string: "AB12/CD34", confidence: 0.9),
                        OCRTextObservation(string: "12345", confidence: 0.9),
                        OCRTextObservation(string: "Cadbury", confidence: 0.6),
                        OCRTextObservation(string: "Cadbury Mini Eggs", confidence: 0.8)
                    ],
                    expectedConsolidationSize: 6,
                    expectedConsolidationString: [
                        "Compliments Sparkling Water",
                        "2/$5",
                        "AB12/CD34",
                        "12345",
                        "Cadbury Mini Eggs",
                        "Old Dutch Chips",
                    ],
                    unexpectedConsolidationString: nil
                ),
                ConsolidationTestCase(
                    input: [
                        OCRTextObservation(string: "Cadbury", confidence: 0.7),
                        OCRTextObservation(string: "Cadbury", confidence: 0.7),
                        OCRTextObservation(string: "Cadbury Mini Eggs", confidence: 0.9)
                    ],
                    expectedConsolidationSize: 1,
                    expectedConsolidationString: ["Cadbury Mini Eggs"],
                    unexpectedConsolidationString: "Cadbury"
                )
            ]
        )
        func consolidateObservations(
            consolidationTestCase: ConsolidationTestCase
        ) async throws {
            
            let input = consolidationTestCase.input
            let expectedConsolidationSize = consolidationTestCase.expectedConsolidationSize
            let expectedConsolidationString = consolidationTestCase.expectedConsolidationString
            let unexpectedConsolidationString = consolidationTestCase.unexpectedConsolidationString
            
            let consolidated = PriceParsingService._test_consolidateObservations(input)
            
            #expect(consolidated.count == expectedConsolidationSize)
            
            let lines = Set(consolidated.map(\.string))
            
            if let expectedConsolidationString {
                for observation in expectedConsolidationString {
                    #expect(lines.contains(observation))
                }
            } else if let unexpectedConsolidationString {
                #expect(lines.contains(unexpectedConsolidationString) == false)
            } else {
                #expect(consolidated.isEmpty)
            }
        }
        
        @Test(
            .tags(.ocr, .product),
            arguments: [
                ConsolidationTestCase(
                    input: [OCRTextObservation(string: "Old Dutch Chips", confidence: 0.7)],
                    expectedConsolidationSize: 1,
                    expectedConsolidationString: ["Old Dutch Chips"],
                    unexpectedConsolidationString: nil
                ),
                
            ]
        )
        func consolidateObservations(
            edgeCases consolidationTestCase: ConsolidationTestCase
        ) async throws {
            
            let input = consolidationTestCase.input
            let expectedConsolidationSize = consolidationTestCase.expectedConsolidationSize
            let expectedConsolidationString = consolidationTestCase.expectedConsolidationString
            let unexpectedConsolidationString = consolidationTestCase.unexpectedConsolidationString
            
            let consolidated = PriceParsingService._test_consolidateObservations(input)
            
            #expect(consolidated.count == expectedConsolidationSize)
            
            let lines = Set(consolidated.map(\.string))
            
            if let expectedConsolidationString {
                for observation in expectedConsolidationString {
                    #expect(lines.contains(observation))
                }
            } else if let unexpectedConsolidationString {
                #expect(lines.contains(unexpectedConsolidationString) == false)
            } else {
                #expect(consolidated.isEmpty)
            }
        }
        
        @Test func isOrderIndependentOfResultSet() async throws {
            let input = [
                OCRTextObservation(string: "Cadbury", confidence: 0.7),
                OCRTextObservation(string: "Cadbury", confidence: 0.8),
                OCRTextObservation(string: "Cadbary", confidence: 0.6),
                OCRTextObservation(string: "Mini Eggs", confidence: 0.9),
                OCRTextObservation(string: "Mini-Eggs", confidence: 0.4)
            ]
            let reversed = Array(input.reversed())

            let lhs = Set(PriceParsingService._test_consolidateObservations(input).map(\.string))
            let rhs = Set(PriceParsingService._test_consolidateObservations(reversed).map(\.string).reversed())

            #expect(lhs == rhs)
        }
    }

    struct buildProductFamilies {
        @Test func buildProductFamilies_emptyInputReturnsEmpty() async throws {
            let families = PriceParsingService._test_buildProductFamilies(from: [])
            #expect(families.isEmpty)
        }

        @Test func buildProductFamilies_singleObservationBuildsOneFamilyWithMetadata() async throws {
            let families = PriceParsingService._test_buildProductFamilies(
                from: [
                    OCRTextObservation(string: "Old Dutch Chips Mesquite BBQ", confidence: 0.8)
                ]
            )

            #expect(families.count == 1)
            #expect(families[0].title == "Old Dutch Chips Mesquite BBQ")
            #expect(families[0].id.hasPrefix("family-0-"))
            #expect(families[0].supportingLines == ["Old Dutch Chips Mesquite BBQ"])
            #expect(families[0].keywords.contains("dutch"))
        }

        @Test func buildProductFamilies_groupsRelatedLinesIntoSameFamily() async throws {
            let families = PriceParsingService._test_buildProductFamilies(
                from: [
                    OCRTextObservation(string: "Old Dutch Chips Mesquite BBQ", confidence: 0.9),
                    OCRTextObservation(string: "Selected Varieties", confidence: 0.8),
                    OCRTextObservation(string: "2/$5", confidence: 0.9)
                ]
            )

            #expect(families.count == 1)
            let family = families[0]
            #expect(family.supportingLines.contains("Old Dutch Chips Mesquite BBQ"))
            #expect(family.supportingLines.contains("Selected Varieties"))
            #expect(family.supportingLines.contains("2/$5"))
            let priceCandiate = try #require(family.priceCandidates.first)
            #expect(priceCandiate.value == Decimal(string: "5"))
        }
        
        @Test func buildProductFamilies_separatesTwoClearFamilies() async throws {
            let families = PriceParsingService._test_buildProductFamilies(
                from: [
                    OCRTextObservation(string: "Old Dutch Chips Mesquite BBQ", confidence: 0.9),
                    OCRTextObservation(string: "$4.99", confidence: 0.9),
                    OCRTextObservation(string: "Compliments Sparkling Water", confidence: 0.9),
                    OCRTextObservation(string: "$3.99", confidence: 0.9)
                ]
            )

            #expect(families.count == 2)
            #expect(families.contains { $0.supportingLines.contains("Old Dutch Chips Mesquite BBQ") })
            #expect(families.contains { $0.supportingLines.contains("Compliments Sparkling Water") })
        }

        @Test func buildProductFamilies_multipleBrandsWithSimilarFlavorStaySeparate() async throws {
            let families = PriceParsingService._test_buildProductFamilies(
                from: [
                    OCRTextObservation(string: "Old Dutch Mesquite BBQ", confidence: 0.8),
                    OCRTextObservation(string: "$4.49", confidence: 0.9),
                    OCRTextObservation(string: "Lays Mesquite BBQ", confidence: 0.8),
                    OCRTextObservation(string: "$3.99", confidence: 0.9)
                ]
            )

            #expect(families.count == 2)
            let oldDutchFamily = families.first { $0.supportingLines.contains("Old Dutch Mesquite BBQ") }
            let laysFamily = families.first { $0.supportingLines.contains("Lays Mesquite BBQ") }
            #expect(oldDutchFamily != nil)
            #expect(laysFamily != nil)
        }

        @Test func buildProductFamilies_doesNotCreateFamilyFromGenericOrUnknownNoiseOnly() async throws {
            let families = PriceParsingService._test_buildProductFamilies(
                from: [
                    OCRTextObservation(string: "for", confidence: 0.7),
                    OCRTextObservation(string: "and", confidence: 0.7),
                    OCRTextObservation(string: "...", confidence: 0.7),
                    OCRTextObservation(string: "12345", confidence: 0.7)
                ]
            )

            #expect(families.isEmpty)
        }
        
        @Test func buildProductFamilies_partialEvidenceStillBuildsFamilySafely() async throws {
            let families = PriceParsingService._test_buildProductFamilies(
                from: [
                    OCRTextObservation(string: "Mesquite BBQ", confidence: 0.8),
                    OCRTextObservation(string: "$4.99", confidence: 0.8)
                ]
            )

            #expect(families.count == 1)
            #expect(families[0].itemNameHint == "Mesquite BBQ")
            let priceCandidate = try #require(families[0].priceCandidates.first)
            #expect(priceCandidate.value == Decimal(string: "4.99"))
        }

        @Test func buildProductFamilies_genericRepeatedEvidenceDoesNotOverrideStrongerDescriptorTitle() async throws {
            let families = PriceParsingService._test_buildProductFamilies(
                from: [
                    OCRTextObservation(string: "Selected Varieties", confidence: 0.7),
                    OCRTextObservation(string: "Selected Varieties", confidence: 0.6),
                    OCRTextObservation(string: "Old Dutch Chips Mesquite BBQ", confidence: 0.9),
                    OCRTextObservation(string: "$4.99", confidence: 0.9)
                ]
            )

            #expect(families.count == 1)
            #expect(families[0].title == "Old Dutch Chips Mesquite BBQ")
            #expect(families[0].supportingLines.contains("Old Dutch Chips Mesquite BBQ"))
        }
        
        @Test func buildProductFamilies_orderIndependentForClearlySeparatedFamilies() async throws {
            let input = [
                OCRTextObservation(string: "Old Dutch Chips Mesquite BBQ", confidence: 0.9),
                OCRTextObservation(string: "$4.99", confidence: 0.9),
                OCRTextObservation(string: "Compliments Sparkling Water", confidence: 0.9),
                OCRTextObservation(string: "$3.99", confidence: 0.9)
            ]

            let lhs = PriceParsingService._test_buildProductFamilies(from: input)
            let rhs = PriceParsingService._test_buildProductFamilies(from: Array(input.reversed()))

            let lhsDescriptors = Set(lhs.map(\.title))
            let rhsDescriptors = Set(rhs.map(\.title))
            #expect(lhsDescriptors == rhsDescriptors)
        }
        
        @Test func keepsLongSingleProductDescriptionInOneFamily() async throws {
            let families = PriceParsingService._test_buildProductFamilies(
                from: [
                    OCRTextObservation(string: "Acme Organic Tomato Soup", confidence: 0.8),
                    OCRTextObservation(string: "No artificial flavors", confidence: 0.8),
                    OCRTextObservation(string: "Low sodium", confidence: 0.8),
                    OCRTextObservation(string: "$3.49", confidence: 0.9)
                ]
            )

            #expect(families.count == 1)
            #expect(families[0].supportingLines.contains("Acme Organic Tomato Soup"))
            let priceCandiate = try #require(families[0].priceCandidates.first)
            #expect(priceCandiate.value == Decimal(string: "3.49"))
        }
    }

    struct primaryFamily {
        
        @Test func primaryFamily_emptyInputReturnsNil() async throws {
            let winner = PriceParsingService._test_primaryFamily(from: [])
            #expect(winner == nil)
        }

        @Test func primaryFamily_singleFamilyReturnsThatFamily() async throws {
            let only = makeTestFamily(
                id: "family-0-only",
                title: "Only",
                supportingLines: ["Only Product", "$4.99"],
                keywords: ["only", "product"],
                pricePriority: 3,
                priceConfidence: 0.8
            )

            let winner = PriceParsingService._test_primaryFamily(from: [only])
            #expect(winner == only)
        }

        @Test func primaryFamily_prefersFamilyWithHigherPricePriority() async throws {
            let low = makeTestFamily(
                id: "family-0-low",
                title: "Low",
                supportingLines: ["Old Dutch Chips", "$4.99"],
                keywords: ["old", "dutch", "chips"],
                pricePriority: 3,
                priceConfidence: 0.95
            )
            let high = makeTestFamily(
                id: "family-1-high",
                title: "High",
                supportingLines: ["Compliments Water", "2/$5"],
                keywords: ["compliments", "water"],
                pricePriority: 4,
                priceConfidence: 0.3
            )

            let winner = try #require(PriceParsingService._test_primaryFamily(from: [low, high]))
            #expect(winner.id == high.id)
        }

        @Test func primaryFamily_prefersHigherConfidenceWhenPriorityTies() async throws {
            let lowerConfidence = makeTestFamily(
                id: "family-0-a",
                title: "A",
                supportingLines: ["Alpha Yogurt", "$4.99"],
                keywords: ["alpha", "yogurt"],
                pricePriority: 3,
                priceConfidence: 0.42
            )
            let higherConfidence = makeTestFamily(
                id: "family-1-b",
                title: "B",
                supportingLines: ["Beta Yogurt", "$4.99"],
                keywords: ["beta", "yogurt"],
                pricePriority: 3,
                priceConfidence: 0.93
            )

            let winner = try #require(PriceParsingService._test_primaryFamily(from: [lowerConfidence, higherConfidence]))
            #expect(winner.id == higherConfidence.id)
        }

        @Test func primaryFamily_prefersStrongerBrandedEvidenceOverGenericClusterWhenPriceSignalsTie() async throws {
            let generic = makeTestFamily(
                id: "family-0-generic",
                title: "Generic",
                supportingLines: ["Sale Price", "$4.99"],
                keywords: ["sale", "price"],
                pricePriority: 3,
                priceConfidence: 0.7
            )
            let branded = makeTestFamily(
                id: "family-1-branded",
                title: "Branded",
                supportingLines: ["Old Dutch Mesquite BBQ", "$4.99"],
                keywords: ["old", "dutch", "mesquite", "bbq"],
                pricePriority: 3,
                priceConfidence: 0.7
            )

            let winner = try #require(PriceParsingService._test_primaryFamily(from: [generic, branded]))
            #expect(winner.id == branded.id)
        }

        @Test func primaryFamily_tieBreakUsesPriceProximityWhenSignalsAreOtherwiseEqual() async throws {
            let farPrice = makeTestFamily(
                id: "family-0-far",
                title: "Far",
                supportingLines: ["Old Dutch Chips", "Promo", "$4.99"],
                keywords: ["old", "dutch", "chips"],
                pricePriority: 3,
                priceConfidence: 0.7
            )
            let nearPrice = makeTestFamily(
                id: "family-1-near",
                title: "Near",
                supportingLines: ["Old Dutch Chips", "$4.99", "Promo"],
                keywords: ["old", "dutch", "chips"],
                pricePriority: 3,
                priceConfidence: 0.7
            )

            let winner = try #require(PriceParsingService._test_primaryFamily(from: [farPrice, nearPrice]))
            #expect(winner.id == nearPrice.id)
        }

        @Test func primaryFamily_recencyTieBreakIsDeterministicAndOrderIndependent() async throws {
            let older = makeTestFamily(
                id: "family-1-alpha",
                title: "Alpha",
                supportingLines: ["Alpha Product", "$4.99"],
                keywords: ["alpha", "product"],
                pricePriority: 3,
                priceConfidence: 0.7
            )
            let newer = makeTestFamily(
                id: "family-2-beta",
                title: "Beta",
                supportingLines: ["Beta Product", "$4.99"],
                keywords: ["beta", "product"],
                pricePriority: 3,
                priceConfidence: 0.7
            )

            let lhsWinner = try #require(PriceParsingService._test_primaryFamily(from: [older, newer]))
            let rhsWinner = try #require(PriceParsingService._test_primaryFamily(from: [newer, older]))
            #expect(lhsWinner.id == newer.id)
            #expect(rhsWinner.id == newer.id)
        }

        @Test func primaryFamily_confidenceOutweighsBrandednessWhenPriorityTies() async throws {
            let weakGeneric = makeTestFamily(
                id: "family-0-weak",
                title: "Weak",
                supportingLines: ["Sale", "$4.99"],
                keywords: ["sale"],
                pricePriority: 3,
                priceConfidence: 0.11
            )
            let weakBranded = makeTestFamily(
                id: "family-1-weakbrand",
                title: "Weak Brand",
                supportingLines: ["Old Dutch Chips", "$4.99"],
                keywords: ["old", "dutch", "chips"],
                pricePriority: 3,
                priceConfidence: 0.09
            )

            let winner = try #require(PriceParsingService._test_primaryFamily(from: [weakGeneric, weakBranded]))
            #expect(winner.id == weakGeneric.id)
        }
    }
}



extension PriceParsingServiceDataSanitation.ConsolidateObservations {
    struct ConsolidationTestCase {
        let input: [OCRTextObservation]
        let expectedConsolidationSize: Int
        let expectedConsolidationString: [String]?
        let unexpectedConsolidationString: String?
    }
}
