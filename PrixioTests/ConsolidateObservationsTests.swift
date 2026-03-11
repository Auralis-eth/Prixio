//
//  ConsolidateObservationsTests.swift
//  Prixio
//
//  Created by Daniel Bell on 3/11/26.
//

import Foundation
import Testing
@testable import Prixio

struct ConsolidateObservationsTests {
    struct ConsolidationTestCase {
        let input: [OCRTextObservation]
        let expectedConsolidationSize: Int
        let expectedConsolidationString: [String]?
        let unexpectedConsolidationString: String?
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
                input: [
                    OCRTextObservation(string: "C0ca-C0la", confidence: 0.6),
                    OCRTextObservation(string: "Coca-Cola", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Coca-Cola"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "1ite Beer", confidence: 0.6),
                    OCRTextObservation(string: "Lite Beer", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Lite Beer"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "chips", confidence: 0.8),
                    OCRTextObservation(string: "OLD DUTCH CHIPS", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["OLD DUTCH CHIPS"],
                unexpectedConsolidationString: "chips"
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Coke", confidence: 0.9),
                    OCRTextObservation(string: "Cake", confidence: 0.9)
                ],
                expectedConsolidationSize: 2,
                expectedConsolidationString: ["Coke", "Cake"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: ".", confidence: 0.9),
                    OCRTextObservation(string: "|", confidence: 0.9),
                    OCRTextObservation(string: "i", confidence: 0.9),
                    OCRTextObservation(string: "Old Dutch Chips", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Old Dutch Chips"],
                unexpectedConsolidationString: "."
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "   ", confidence: 0.9),
                    OCRTextObservation(string: "", confidence: 0.9)
                ],
                expectedConsolidationSize: 0,
                expectedConsolidationString: nil,
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Salt & Vinegar", confidence: 0.9),
                    OCRTextObservation(string: "Vinegar Chips", confidence: 0.9)
                ],
                expectedConsolidationSize: 2,
                expectedConsolidationString: ["Salt & Vinegar", "Vinegar Chips"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "$10.99", confidence: 0.9),
                    OCRTextObservation(string: "s10.99", confidence: 0.5),
                    OCRTextObservation(string: "10.99", confidence: 0.7)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["$10.99"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "$5.99", confidence: 0.9),
                    OCRTextObservation(string: "$5.99", confidence: 0.8),
                    OCRTextObservation(string: "$5.98", confidence: 0.9)
                ],
                expectedConsolidationSize: 2,
                expectedConsolidationString: ["$5.99", "$5.98"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "...Product Name...", confidence: 0.6),
                    OCRTextObservation(string: "Product Name", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Product Name"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Mini Eggs", confidence: 0.7),
                    OCRTextObservation(string: "Cadbury", confidence: 0.7),
                    OCRTextObservation(string: "Cadbury Mini Eggs", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Cadbury Mini Eggs"],
                unexpectedConsolidationString: "Cadbury"
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Cadbury Mini Eggs", confidence: 0.9),
                    OCRTextObservation(string: "Cadbury", confidence: 0.7)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Cadbury Mini Eggs"],
                unexpectedConsolidationString: "Cadbury"
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Dutch Chips", confidence: 0.7),
                    OCRTextObservation(string: "Old Dutch Chips", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Old Dutch Chips"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Pepsi Cola", confidence: 0.9),
                    OCRTextObservation(string: "Pepsi Max", confidence: 0.9)
                ],
                expectedConsolidationSize: 2,
                expectedConsolidationString: ["Pepsi Cola", "Pepsi Max"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Oreo Cookies", confidence: 0.9),
                    OCRTextObservation(string: "Oreos Cookies", confidence: 0.7)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Oreo Cookies"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Mini Eggs", confidence: 0.8),
                    OCRTextObservation(string: "Mini Egg", confidence: 0.8)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Mini Eggs"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Cadbury", confidence: 0.0),
                    OCRTextObservation(string: "Cadbury", confidence: 0.0)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Cadbury"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Oreo", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Oreo"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Cola", confidence: 0.9),
                    OCRTextObservation(string: "Cola", confidence: 0.8)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Cola"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "Old\tDutch\tChips", confidence: 0.9),
                    OCRTextObservation(string: "Old Dutch Chips", confidence: 0.8)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Old Dutch Chips"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "$2.99", confidence: 0.9),
                    OCRTextObservation(string: "2.99", confidence: 0.8)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["$2.99"],
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "A", confidence: 0.9),
                    OCRTextObservation(string: "5", confidence: 0.9)
                ],
                expectedConsolidationSize: 0,
                expectedConsolidationString: nil,
                unexpectedConsolidationString: nil
            ),
            ConsolidationTestCase(
                input: [
                    OCRTextObservation(string: "cadbury", confidence: 0.7),
                    OCRTextObservation(string: "Cadbury Mini Eggs", confidence: 0.9)
                ],
                expectedConsolidationSize: 1,
                expectedConsolidationString: ["Cadbury Mini Eggs"],
                unexpectedConsolidationString: "cadbury"
            )
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
}
