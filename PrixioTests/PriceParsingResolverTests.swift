import Foundation
import Testing
@testable import Prixio

@MainActor
struct PriceParsingResolverTests {
    @Test(.tags(.ocr, .product))
    func unitResolverDetectsDirectAndPackageUnits() {
        let resolver = PriceParsingUnitResolver()

        #expect(resolver.detectUnit(in: "$3.99/lb") == .lb)
        #expect(resolver.detectUnit(in: "$1.10 / 100 g") == .hundredGrams)
        #expect(resolver.detectUnit(in: "6 pack cans") == .each)
        #expect(resolver.detectUnit(in: "2.49 per liter") == .liter)
        #expect(resolver.detectUnit(in: "organic apples") == nil)
    }

    @Test(.tags(.ocr, .product))
    func unitResolverQuantityFallbacksHandleOfferPackAndExplicitUnit() {
        let resolver = PriceParsingUnitResolver()

        #expect(resolver.inferOfferQuantity(in: "3 for $5") == Decimal(3))
        #expect(resolver.inferPackQuantity(in: "6 pack") == Decimal(6))
        #expect(resolver.detectQuantity(in: "2.5 kg", unit: .kg) == Decimal(string: "2.5"))
        #expect(resolver.detectQuantity(in: "1/2 lb", unit: .lb) == Decimal(string: "0.5"))
        #expect(resolver.detectQuantity(in: "aisle marker", unit: nil) == nil)
    }

    @Test(.tags(.ocr, .product))
    func itemNameResolverRejectsReceiptsPromosPricesAndShelfCodes() {
        let resolver = PriceParsingItemNameResolver()
        let observations: [any TextObservation] = [
            PlainTextObservation(string: "Subtotal", confidence: 1.0),
            PlainTextObservation(string: "Weekly Special", confidence: 1.0),
            PlainTextObservation(string: "$4.99", confidence: 1.0),
            PlainTextObservation(string: "AB12-CD34", confidence: 1.0)
        ]

        for index in observations.indices {
            #expect(resolver.scoredItemNameCandidate(
                for: observations[index].string,
                lineIndex: index,
                priceCandidates: [],
                observations: observations
            ) == nil)
        }
    }

    @Test(.tags(.ocr, .product))
    func itemNameResolverRepairsCommonOCRDigitSubstitutions() {
        let resolver = PriceParsingItemNameResolver()

        #expect(resolver.canonicalDisplayName(from: "C0ke Zer0") == "Coke Zero")
        #expect(resolver.cleanedNameFragment("Organic Apples 3 lb", preserveTrailingSizeTokens: false) == "Organic Apples")
    }

    @Test(.tags(.ocr, .product))
    func confidenceResolverFindsSourceLinesAndRejectsReceiptStyleDescriptors() {
        let resolver = PriceParsingConfidenceResolver()
        let observations: [any TextObservation] = [
            PlainTextObservation(string: "Organic Apples", confidence: 1.0),
            PlainTextObservation(string: "$2.99/lb", confidence: 1.0)
        ]
        let candidate = PriceCandidate(
            label: "$2.99/lb",
            value: Decimal(string: "2.99")!,
            quantity: nil,
            priority: 0,
            sourceText: "$2.99/lb",
            kind: .shelf,
            sourceLineIndexes: [],
            confidence: 1.0
        )

        #expect(resolver.sourceLineIndexes(for: candidate, in: observations) == [1])
        #expect(resolver.containsPhoneNumber(in: "4035551212"))
        #expect(resolver.looksLikeDateLine("June 17 2026"))
        #expect(resolver.isProductDescriptor("Organic Apples"))
        #expect(resolver.isProductDescriptor("Subtotal") == false)
    }
}
