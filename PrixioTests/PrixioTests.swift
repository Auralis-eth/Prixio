//
//  PrixioTests.swift
//  PrixioTests
//
//  Created by Daniel Bell on 9/22/25.
//

import Foundation
import Testing
@testable import Prixio

@MainActor
struct PrixioTests {

    @Test func parsesMultiBuyOffer() async throws {
        let result = PriceParsingService.extract(from: ["Yellow Onions", "2/$5", "Product of Canada"])

        #expect(result.itemNameHint == "Yellow Onions")
        #expect(result.price == Decimal(string: "5"))
        #expect(result.quantity == Decimal(string: "2"))
    }

    @Test func reconstructsSplitDollarAndCents() async throws {
        let result = PriceParsingService.extract(from: ["Bananas", "17", "99"])

        #expect(result.price == Decimal(string: "17.99"))
        #expect(result.priceCandidates.first?.value == Decimal(string: "17.99"))
    }

    @Test func infersDecimalFromFourDigitOCRToken() async throws {
        let result = PriceParsingService.extract(from: ["Bananas", "1799", "99"])

        #expect(result.price == Decimal(string: "17.99"))
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "17.99") })
    }

    @Test func prefersHigherConfidencePriceCandidateWithinSamePriority() async throws {
        let result = PriceParsingService.extract(
            from: [
                OCRTextObservation(string: "Low confidence 2.99", confidence: 0.12),
                OCRTextObservation(string: "High confidence 4.99", confidence: 0.94)
            ]
        )

        #expect(result.price == Decimal(string: "4.99"))
        #expect(result.confidence == 0.94)
        #expect(result.priceCandidates.first?.sourceText == "High confidence 4.99")
    }

    @Test func consolidatesNoisyDuplicateOCRTokens() async throws {
        let result = PriceParsingService.extract(
            from: [
                "MinI",
                "EggS",
                "Min",
                "Cadbury",
                "Eg95",
                "* MIni",
                "Eggs",
                "Mini",
                "EggS",
                "Min!",
                "Eggs",
                "Cadbury Chocolate Mini"
            ]
        )

        #expect(result.rawText.contains("Cadbury Chocolate Mini"))
        #expect(result.rawText.contains("* MIni") == false)
        #expect(result.rawText.contains("Min!") == false)
    }

    @Test func appliesContextualOCRCorrections() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Tutch",
                "Dutch Crunch Potato Chips Selected Varieties",
                "Compliments Sparkli Ginger Ale",
                "12 x 3355 ml CANS"
            ]
        )

        #expect(result.rawText.contains("Old Dutch"))
        #expect(result.rawText.contains("Compliments Sparkling Ginger Ale"))
        #expect(result.rawText.contains("12 x 355 mL CANS"))
    }

    @Test func buildsDistinctProductFamiliesAndUsesPrimaryFamilyPriceRanking() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Tutch",
                "Dutch Crunch Potato Chips Selected Varieties",
                "200g",
                "Compliments Sparkli Ginger Ale",
                "12 x 3355 ml CANS",
                "2/$5"
            ]
        )

        #expect(result.productFamilies.count >= 2)
        #expect(result.price == Decimal(string: "5"))
        #expect(result.productFamilies.contains { family in
            family.supportingLines.contains(where: { $0.contains("Old Dutch") })
        })
        #expect(result.productFamilies.contains { family in
            family.priceCandidates.first?.value == Decimal(string: "5")
        })
    }

    @Test func normalizesPoundsToKilograms() async throws {
        let normalized = PriceParsingService.normalize(
            price: Decimal(string: "3.99")!,
            unit: .lb,
            quantity: nil
        )

        #expect(normalized?.1 == .kg)
        #expect(rounded(normalized?.0, scale: 4) == Decimal(string: "8.7964"))
    }

    @Test func draftRequiresExplicitStoreSelection() async throws {
        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"

        #expect(draft.canSave == false)

        draft.storeChainExplicitlySelected = true
        #expect(draft.canSave == true)
    }

    @Test func detectsReceiptLikeText() async throws {
        let text = """
        Calgary Co-op
        Subtotal 12.99
        GST 0.65
        Total 13.64
        Thank you
        """

        #expect(PriceParsingService.looksLikeReceipt(text: text) == true)
    }

    @Test func pipelineStep_removeObviousNoiseFiltersSkuAndNumericJunk() async throws {
        let result = PriceParsingService.extract(
            from: [
                "AB12/CD34",
                "12345",
                "Old Dutch Chips",
                "2/$5"
            ]
        )

        #expect(result.rawText.contains("AB12/CD34") == false)
        #expect(result.rawText.contains("12345") == false)
        #expect(result.rawText.contains("Old Dutch Chips"))
        #expect(result.price == Decimal(string: "5"))
    }

    @Test func pipelineStep_applyContextualNormalizationRepairsKnownOCRTypos() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Tutch",
                "Compliments Sparkli Water",
                "12 x 3355 ml cans"
            ]
        )

        #expect(result.rawText.contains("Old Dutch"))
        #expect(result.rawText.contains("Compliments Sparkling Water"))
        #expect(result.rawText.contains("12 x 355 mL cans"))
    }

    @Test func applyContextualNormalization_emptyInputIsSafe() async throws {
        let result = PriceParsingService.extract(from: [String]())

        #expect(result.rawText.isEmpty)
        #expect(result.productFamilies.isEmpty)
    }

    @Test func applyContextualNormalization_isIdempotentForAlreadyNormalizedInput() async throws {
        let input = [
            "Old Dutch Chips",
            "Mesquite BBQ",
            "355 mL",
            "12 x 355 mL"
        ]
        let result = PriceParsingService.extract(from: input)

        #expect(parsedLines(from: result.rawText) == input)
    }

    @Test func applyContextualNormalization_correctsSingleExplicitTypo() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Tutch",
                "2/$5"
            ]
        )

        #expect(result.rawText.contains("Old Dutch"))
        #expect(result.rawText.contains("Old Tutch") == false)
    }

    @Test func applyContextualNormalization_correctsRepeatedNearMatchesTowardSameTarget() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Tutch",
                "Tutch Kettle Chips",
                "Old Dutch Kettle Chips"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("Old Dutch"))
        #expect(lines.contains("Dutch Kettle Chips"))
        #expect(lines.contains("Tutch Kettle Chips") == false)
    }

    @Test func applyContextualNormalization_preservesAmbiguousTokenWithoutStrongSupport() async throws {
        let result = PriceParsingService.extract(
            from: [
                OCRTextObservation(string: "Acmecoo Salsa", confidence: 0.95),
                OCRTextObservation(string: "2/$5", confidence: 0.95)
            ]
        )

        #expect(result.rawText.contains("Acmecoo Salsa"))
        #expect(result.rawText.contains("Acmeco Salsa") == false)
    }

    @Test func applyContextualNormalization_doesNotExpandPartialTokenWithoutEvidence() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Sparkl Water"
            ]
        )

        #expect(result.rawText.contains("Sparkl Water"))
        #expect(result.rawText.contains("Sparkling Water") == false)
    }

    @Test func applyContextualNormalization_repairsPackSizeFormattingVariants() async throws {
        let result = PriceParsingService.extract(
            from: [
                "355ml",
                "355 mL",
                "12x3355ml",
                "12 x 355 mL"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("355ml"))
        #expect(lines.contains("355 mL"))
        #expect(lines.contains("12 x 355 mL"))
        #expect(lines.contains("12x3355ml") == false)
    }

    @Test func applyContextualNormalization_repairs3355OnlyInPackSizeMLContext() async throws {
        let result = PriceParsingService.extract(
            from: [
                "12 x 3355 bolts",
                "12 x 3355 ml cans"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("12 x 3355 bolts"))
        #expect(lines.contains("12 x 355 mL cans"))
    }

    @Test func applyContextualNormalization_handlesFlavorTokensWithoutReorderingMeaning() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Mesquite BBQMA",
                "BBQ mesquite"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("Mesquite BBQ"))
        #expect(lines.contains("BBQ mesquite"))
    }

    @Test func applyContextualNormalization_preservesUnicodeVariantsWithoutCollapsingDistinctForms() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Jalapeño Chips",
                "Jalapeno Chips"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("Jalapeño Chips"))
        #expect(lines.contains("Jalapeno Chips"))
    }

    @Test func applyContextualNormalization_doesNotMergeDistinctProductsIntoOneCollision() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Acme Cola",
                "Acme Color"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("Acme Cola"))
        #expect(lines.contains("Acme Color"))
    }

    @Test func applyContextualNormalization_preservesMeaningfulProductModifiers() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Acme Cola Diet",
                "Acme Cola Regular",
                "Acme Peanuts Salted",
                "Acme Peanuts Unsalted"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("Acme Cola Diet"))
        #expect(lines.contains("Acme Cola Regular"))
        #expect(lines.contains("Acme Peanuts Salted"))
        #expect(lines.contains("Acme Peanuts Unsalted"))
    }

    @Test func applyContextualNormalization_doesNotHallucinateUnsupportedTerms() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Chp crisps",
                "sltd"
            ]
        )

        #expect(result.rawText.contains("chips") == false)
        #expect(result.rawText.contains("salted") == false)
    }

    @Test func applyContextualNormalization_doesNotMutateInputObservations() async throws {
        let original = [
            OCRTextObservation(string: "Old Tutch", confidence: 0.91),
            OCRTextObservation(string: "12x3355ml", confidence: 0.82)
        ]

        _ = PriceParsingService.extract(from: original)

        #expect(original[0].string == "Old Tutch")
        #expect(original[1].string == "12x3355ml")
    }

    @Test func pipelineStep_consolidateObservationsCollapsesNearDuplicateSingleTokens() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Cadbury",
                "Cadbury",
                "Cadbary",
                "Mini Eggs",
                "Mini Eggs"
            ]
        )

        let cadburyLikeLines = result.rawText
            .components(separatedBy: .newlines)
            .filter { $0.lowercased().contains("cadbur") }
        #expect(cadburyLikeLines.count <= 1)
    }

    @Test func consolidateObservations_emptyInputReturnsEmpty() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations([])
        #expect(consolidated.isEmpty)
    }

    @Test func consolidateObservations_singleObservationReturnsAsIs() async throws {
        let input = [OCRTextObservation(string: "Old Dutch Chips", confidence: 0.7)]
        let consolidated = PriceParsingService._test_consolidateObservations(input)

        #expect(consolidated.count == 1)
        #expect(consolidated[0].string == "Old Dutch Chips")
        #expect(consolidated[0].confidence == 0.7)
    }

    @Test func consolidateObservations_identicalObservationsMergeToOne() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations(
            [
                OCRTextObservation(string: "Mini Eggs", confidence: 0.2),
                OCRTextObservation(string: "Mini Eggs", confidence: 0.9)
            ]
        )

        #expect(consolidated.count == 1)
        #expect(consolidated[0].string == "Mini Eggs")
        #expect(consolidated[0].confidence == 0.9)
    }

    @Test func consolidateObservations_caseSpacingAndPunctuationVariantsMerge() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations(
            [
                OCRTextObservation(string: "mini eggs", confidence: 0.2),
                OCRTextObservation(string: "Mini   Eggs", confidence: 0.6),
                OCRTextObservation(string: "Mini-Eggs", confidence: 0.3),
                OCRTextObservation(string: "Mini Eggs", confidence: 0.8)
            ]
        )

        #expect(consolidated.count == 1)
        #expect(consolidated[0].string == "Mini Eggs")
        #expect(consolidated[0].confidence == 0.8)
    }

    @Test func consolidateObservations_nearDuplicatesMergeWhenSupportedByConsensus() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations(
            [
                OCRTextObservation(string: "Cadbury", confidence: 0.6),
                OCRTextObservation(string: "Cadbury", confidence: 0.8),
                OCRTextObservation(string: "Cadbary", confidence: 0.5)
            ]
        )

        #expect(consolidated.count == 1)
        #expect(consolidated[0].string == "Cadbury")
    }

    @Test func consolidateObservations_nearDuplicatesWithoutSupportRemainSeparate() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations(
            [
                OCRTextObservation(string: "Mint", confidence: 0.6),
                OCRTextObservation(string: "Hint", confidence: 0.6)
            ]
        )

        let lines = Set(consolidated.map(\.string))
        #expect(consolidated.count == 2)
        #expect(lines == Set(["Mint", "Hint"]))
    }

    @Test func consolidateObservations_contradictoryObservationsRemainSeparate() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations(
            [
                OCRTextObservation(string: "Diet Cola", confidence: 0.8),
                OCRTextObservation(string: "Regular Cola", confidence: 0.8)
            ]
        )

        let lines = Set(consolidated.map(\.string))
        #expect(consolidated.count == 2)
        #expect(lines == Set(["Diet Cola", "Regular Cola"]))
    }

    @Test func consolidateObservations_repeatedStandaloneTokenGetsDroppedWhenCoveredByMultiwordEvidence() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations(
            [
                OCRTextObservation(string: "Cadbury", confidence: 0.7),
                OCRTextObservation(string: "Cadbury", confidence: 0.7),
                OCRTextObservation(string: "Cadbury Mini Eggs", confidence: 0.9)
            ]
        )

        let lines = consolidated.map(\.string)
        #expect(lines.contains("Cadbury") == false)
        #expect(lines.contains("Cadbury Mini Eggs"))
    }

    @Test func consolidateObservations_prefersHigherConfidenceRepresentativeWithinCluster() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations(
            [
                OCRTextObservation(string: "Sparkling Water", confidence: 0.31),
                OCRTextObservation(string: "Sparkling Water", confidence: 0.92)
            ]
        )

        #expect(consolidated.count == 1)
        #expect(consolidated[0].confidence == 0.92)
    }

    @Test func consolidateObservations_largeBatchProducesExpectedGroupCount() async throws {
        let consolidated = PriceParsingService._test_consolidateObservations(
            [
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
            ]
        )

        let lines = Set(consolidated.map(\.string))
        #expect(lines.contains("Old Dutch Chips"))
        #expect(lines.contains("Compliments Sparkli Water"))
        #expect(lines.contains("2/$5"))
        #expect(lines.contains("AB12/CD34"))
        #expect(lines.contains("12345"))
        #expect(lines.contains("Cadbury Mini Eggs"))
        #expect(lines.contains("Cadbury") == false)
        #expect(consolidated.count == 6)
    }

    @Test func consolidateObservations_isOrderIndependentByResultSet() async throws {
        let input = [
            OCRTextObservation(string: "Cadbury", confidence: 0.7),
            OCRTextObservation(string: "Cadbury", confidence: 0.8),
            OCRTextObservation(string: "Cadbary", confidence: 0.6),
            OCRTextObservation(string: "Mini Eggs", confidence: 0.9),
            OCRTextObservation(string: "Mini-Eggs", confidence: 0.4)
        ]
        let reversed = Array(input.reversed())

        let lhs = Set(PriceParsingService._test_consolidateObservations(input).map(\.string))
        let rhs = Set(PriceParsingService._test_consolidateObservations(reversed).map(\.string))

        #expect(lhs == rhs)
    }

    @Test func pipelineStep_buildProductFamiliesSeparatesDistinctClusters() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Dutch Chips Mesquite BBQ",
                "2/$5",
                "Compliments Sparkli Ginger Ale",
                "12 x 3355 ml cans"
            ]
        )

        #expect(result.productFamilies.count >= 2)
        #expect(result.productFamilies.contains { family in
            family.supportingLines.contains(where: { $0.contains("Old Dutch") })
        })
        #expect(result.productFamilies.contains { family in
            family.supportingLines.contains(where: { $0.contains("Sparkling Ginger Ale") })
        })
    }

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
        #expect(family.priceCandidates.first?.value == Decimal(string: "5"))
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
        #expect(families[0].priceCandidates.first?.value == Decimal(string: "4.99"))
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

    @Test func pipelineStep_primaryFamilyChoosesFamilyWithBestPriceSignal() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Dutch Chips",
                "4.99",
                "Compliments Sparkli Water",
                "2/$5"
            ]
        )

        #expect(result.price == Decimal(string: "5"))
        #expect(result.priceCandidates.first?.quantity == Decimal(string: "2"))
    }

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

        let winner = PriceParsingService._test_primaryFamily(from: [low, high])
        #expect(winner?.id == high.id)
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

        let winner = PriceParsingService._test_primaryFamily(from: [lowerConfidence, higherConfidence])
        #expect(winner?.id == higherConfidence.id)
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

        let winner = PriceParsingService._test_primaryFamily(from: [generic, branded])
        #expect(winner?.id == branded.id)
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

        let winner = PriceParsingService._test_primaryFamily(from: [farPrice, nearPrice])
        #expect(winner?.id == nearPrice.id)
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

        let lhsWinner = PriceParsingService._test_primaryFamily(from: [older, newer])
        let rhsWinner = PriceParsingService._test_primaryFamily(from: [newer, older])
        #expect(lhsWinner?.id == newer.id)
        #expect(rhsWinner?.id == newer.id)
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

        let winner = PriceParsingService._test_primaryFamily(from: [weakGeneric, weakBranded])
        #expect(winner?.id == weakGeneric.id)
    }

    @Test func pipelineStep_removeObviousNoiseKeepsExplicitSizeTokenForClustering() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Dutch Chips",
                "200g",
                "2/$5"
            ]
        )

        #expect(result.rawText.contains("200g"))
    }

    @Test func removeObviousNoise_emptyInputReturnsEmptyCollection() async throws {
        let result = PriceParsingService.extract(from: [String]())

        #expect(result.rawText.isEmpty)
        #expect(result.priceCandidates.isEmpty)
        #expect(result.productFamilies.isEmpty)
    }

    @Test func removeObviousNoise_allNoiseInputReturnsEmptyCollection() async throws {
        let result = PriceParsingService.extract(
            from: [
                "12345",
                "AB12/CD34",
                "!!!",
                "   "
            ]
        )

        #expect(result.rawText.isEmpty)
        #expect(result.priceCandidates.isEmpty)
        #expect(result.productFamilies.isEmpty)
    }

    @Test func removeObviousNoise_validInputPreservesSemanticLinesInOrder() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Dutch Chips",
                "Mesquite BBQ",
                "200g",
                "2/$5"
            ]
        )

        #expect(parsedLines(from: result.rawText) == ["Old Dutch Chips", "Mesquite BBQ", "200g", "2/$5"])
    }

    @Test func removeObviousNoise_mixedInputRemovesNoiseButKeepsValidEvidence() async throws {
        let result = PriceParsingService.extract(
            from: [
                "AB12/CD34",
                "Old Dutch Chips",
                "12345",
                "Jalapeño",
                "***",
                "355 mL"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("Old Dutch Chips"))
        #expect(lines.contains("Jalapeño"))
        #expect(lines.contains("355 mL"))
        #expect(lines.contains("AB12/CD34") == false)
        #expect(lines.contains("12345") == false)
        #expect(lines.contains("***") == false)
    }

    @Test func removeObviousNoise_brokenWordsCloseToRealWordsAreNotDropped() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Dutcn",
                "Jalapeno"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("Dutcn"))
        #expect(lines.contains("Jalapeno"))
    }

    @Test func removeObviousNoise_repeatedFragmentsAreConsolidatedSafely() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Mini Eggs",
                "Mini Eggs",
                "Mini Eggs",
                "2/$5"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.filter { $0 == "Mini Eggs" }.count == 1)
        #expect(lines.contains("2/$5"))
    }

    @Test func removeObviousNoise_keepsShortMeaningfulTokens() async throws {
        let result = PriceParsingService.extract(
            from: [
                "XL",
                "BBQ",
                "2L",
                "7UP"
            ]
        )

        let lines = parsedLines(from: result.rawText)
        #expect(lines.contains("XL"))
        #expect(lines.contains("BBQ"))
        #expect(lines.contains("2L"))
        #expect(lines.contains("7UP"))
    }

    @Test func pipelineStep_applyContextualNormalizationAvoidsLowSignalBrandOverCorrection() async throws {
        let result = PriceParsingService.extract(
            from: [
                OCRTextObservation(string: "Acmeco Crunch Chips", confidence: 0.97),
                OCRTextObservation(string: "Acmeco Salsa", confidence: 0.95),
                OCRTextObservation(string: "2/$5", confidence: 0.93),
                OCRTextObservation(string: "Acmecoo Sauce", confidence: 0.12)
            ]
        )

        #expect(result.rawText.contains("Acmecoo Sauce"))
    }

    @Test func pipelineStep_consolidateObservationsDoesNotMergeUnrelatedShortTokensWithoutContext() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Mint",
                "Hint",
                "Cereal 500g"
            ]
        )

        #expect(result.rawText.contains("Mint"))
        #expect(result.rawText.contains("Hint"))
    }

    @Test func pipelineStep_buildProductFamiliesAvoidsMisattachingGenericPromoLine() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Dutch Chips Mesquite BBQ",
                "Compliments Sparkli Ginger Ale",
                "2/$5"
            ]
        )

        let oldDutchFamily = result.productFamilies.first { family in
            family.supportingLines.contains(where: { $0.contains("Old Dutch") })
        }
        let complimentsFamily = result.productFamilies.first { family in
            family.supportingLines.contains(where: { $0.contains("Sparkling Ginger Ale") })
        }

        #expect(oldDutchFamily != nil)
        #expect(complimentsFamily != nil)
        let familiesWithPromoPrice = result.productFamilies.filter { family in
            family.priceCandidates.contains { $0.value == Decimal(string: "5") }
        }
        #expect(familiesWithPromoPrice.count <= 1)
    }

    @Test func pipelineStep_primaryFamilySelectionIsDeterministicForSameInput() async throws {
        let input = [
            "Alpha Cereal",
            "$4.99",
            "Beta Yogurt",
            "$4.99"
        ]
        let first = PriceParsingService.extract(from: input)
        let second = PriceParsingService.extract(from: input)

        #expect(first.price == Decimal(string: "4.99"))
        #expect(second.price == Decimal(string: "4.99"))
        #expect(first.itemNameHint == second.itemNameHint)
        #expect(["Alpha Cereal", "Beta Yogurt"].contains(first.itemNameHint ?? ""))
    }

    @Test func parsesWeightBasedPriceFromInlineSlashNotation() async throws {
        let result = PriceParsingService.extract(from: ["Apples", "$1.99/lb"])

        #expect(result.price == Decimal(string: "1.99"))
        #expect(result.unit == .lb)
        #expect(result.quantity == Decimal(1))
    }

    @Test func parsesWeightBasedPriceFromPerLineNotation() async throws {
        let result = PriceParsingService.extract(from: ["Bananas", "0.69", "per lb"])

        #expect(result.price == Decimal(string: "0.69"))
        #expect(result.unit == .lb)
        #expect(result.quantity == Decimal(1))
    }

    @Test func prioritizesMemberPriceOverRegularPriceWhenBothPresent() async throws {
        let result = PriceParsingService.extract(from: ["Member Price $4.99", "Regular Price $5.99"])

        #expect(result.price == Decimal(string: "4.99"))
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "4.99") })
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "5.99") })
        #expect(result.priceCandidates.first?.sourceText == "Member Price $4.99")
    }

    @Test func ignoresSaveLinePriceWhenSelectingProductPrice() async throws {
        let result = PriceParsingService.extract(from: ["Steak", "$14.99", "Save $3.00"])

        #expect(result.price == Decimal(string: "14.99"))
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "14.99") })
        #expect(result.priceCandidates.first?.value == Decimal(string: "14.99"))
        #expect(result.priceCandidates.first?.sourceText.lowercased().contains("save") == false)
    }

    @Test func parsesFractionalQuantityForWeightedItems() async throws {
        let result = PriceParsingService.extract(from: ["Ham", "1/2 lb", "$5.00"])

        #expect(result.price == Decimal(string: "5.00"))
        #expect(result.unit == .lb)
        #expect(result.quantity == Decimal(string: "0.5"))
    }

    @Test func ignoresDateAndPhoneNumbersAsPriceCandidates() async throws {
        let result = PriceParsingService.extract(from: ["Milk", "$4.99", "March 20 2026", "4035550123"])

        #expect(result.price == Decimal(string: "4.99"))
        #expect(result.priceCandidates.contains { $0.sourceText.contains("March 20 2026") } == false)
        #expect(result.priceCandidates.contains { $0.sourceText.contains("4035550123") } == false)
        #expect(result.priceCandidates.allSatisfy { $0.value == Decimal(string: "4.99") })
    }

    @Test func parsesCurrencySymbolsAndEuropeanDecimalComma() async throws {
        let result = PriceParsingService.extract(from: ["Greek Yogurt", "$4.99", "4,99", "4.99$"])

        #expect(result.price == Decimal(string: "4.99"))
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "4.99") })
    }

    @Test func parsesZeroPriceSignalsForFreeItems() async throws {
        let result = PriceParsingService.extract(from: ["Promo Item", "FREE", "$0.00", "0/$0"])

        #expect(result.price == Decimal.zero)
        #expect(result.priceCandidates.contains { $0.value == Decimal.zero })
    }

    @Test func salePriceWinsOverWasPrice() async throws {
        let result = PriceParsingService.extract(from: ["WAS $6.99", "NOW $4.99"])

        #expect(result.price == Decimal(string: "4.99"))
        #expect(result.priceCandidates.first?.sourceText == "NOW $4.99")
    }

    @Test func parsesThreeForTenMultiBuyOffer() async throws {
        let result = PriceParsingService.extract(from: ["Oranges", "3 for $10"])

        #expect(result.price == Decimal(string: "10"))
        #expect(result.quantity == Decimal(string: "3"))
    }

    @Test func capturesPriceRangeCandidates() async throws {
        let result = PriceParsingService.extract(from: ["Steak", "$3.99-$5.99"])

        #expect(result.price == Decimal(string: "5.99"))
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "3.99") })
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "5.99") })
    }

    @Test func parsesVeryLargeAndVerySmallPrices() async throws {
        let result = PriceParsingService.extract(from: ["Gift Basket $149.99", "Candy $0.09"])

        #expect(result.price == Decimal(string: "149.99"))
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "149.99") })
        #expect(result.priceCandidates.contains { $0.value == Decimal(string: "0.09") })
    }

    @Test func parsesUnitPricePerHundredGrams() async throws {
        let result = PriceParsingService.extract(from: ["Cheddar", "$1.29/100g"])

        #expect(result.price == Decimal(string: "1.29"))
        #expect(result.unit == .hundredGrams)
    }

    @Test func preservesMixedLanguageAndHyphenatedTokens() async throws {
        let result = PriceParsingService.extract(from: ["Crème fraîche", "Grüner Tee", "Häagen-Dazs", "Coca-Cola", "DIET COKE"])

        #expect(result.rawText.contains("Crème fraîche"))
        #expect(result.rawText.contains("Grüner Tee"))
        #expect(result.rawText.contains("Häagen-Dazs"))
        #expect(result.rawText.contains("Coca-Cola"))
        #expect(result.rawText.contains("DIET COKE"))
    }

    @Test func buildsThreeDistinctFamiliesInOneScan() async throws {
        let result = PriceParsingService.extract(
            from: [
                "Old Dutch Chips",
                "$4.99",
                "Lays Classic",
                "$3.99",
                "Coke Zero",
                "$2.49"
            ]
        )

        #expect(result.productFamilies.count >= 3)
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
        #expect(families[0].priceCandidates.first?.value == Decimal(string: "3.49"))
    }

    @Test func handlesPriceOrphanWithoutItemNameHint() async throws {
        let result = PriceParsingService.extract(from: ["$3.99"])

        #expect(result.price == Decimal(string: "3.99"))
        #expect(result.itemNameHint == nil)
        #expect(result.productFamilies.isEmpty == false)
    }

    @Test func receiptDetectionAvoidsSavingsFlyerFalsePositive() async throws {
        let text = """
        Weekend Flyer
        Total Savings: $3
        Buy 2 for $5
        """

        #expect(PriceParsingService.looksLikeReceipt(text: text) == false)
    }

    @Test func receiptDetectionRequiresMoreThanSingleSubtotalMarker() async throws {
        #expect(PriceParsingService.looksLikeReceipt(text: "Subtotal 12.99") == false)
    }

    @Test func draftCannotSaveWhenAllRequiredFieldsAreMissing() async throws {
        let draft = PriceEntryDraft()

        #expect(draft.canSave == false)
    }

    @Test func draftRejectsInvalidPriceTextValues() async throws {
        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"
        draft.storeChainExplicitlySelected = true

        draft.priceText = "abc"
        #expect(draft.canSave == false)

        draft.priceText = ""
        #expect(draft.canSave == false)

        draft.priceText = "-1"
        #expect(draft.canSave == false)
    }

    @Test func draftRoundTripStillRequiresExplicitStoreSelection() async throws {
        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"
        draft.storeChainExplicitlySelected = true

        #expect(draft.canSave == true)

        draft.storeChainName = nil
        draft.storeChainExplicitlySelected = false
        #expect(draft.canSave == false)
    }

    @Test func stressDeduplicatesManyIdenticalTokens() async throws {
        let repeatedCadbury = Array(repeating: "Cadbury", count: 50)
        let result = PriceParsingService.extract(from: repeatedCadbury + ["$4.99"])
        let lines = parsedLines(from: result.rawText)

        #expect(lines.filter { $0 == "Cadbury" }.count <= 1)
        #expect(result.price == Decimal(string: "4.99"))
    }

    @Test func stressHandlesDeepLowConfidenceNoiseGracefully() async throws {
        let observations = (0..<30).map { index in
            OCRTextObservation(string: "noise \(index)", confidence: 0.1)
        }
        let result = PriceParsingService.extract(from: observations)

        #expect(result.confidence != nil)
        #expect(result.priceCandidates.isEmpty)
    }

}

private func parsedLines(from rawText: String) -> [String] {
    rawText
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func rounded(_ value: Decimal?, scale: Int) -> Decimal? {
    guard var value else {
        return nil
    }
    var result = Decimal.zero
    NSDecimalRound(&result, &value, scale, .plain)
    return result
}

private func makeTestFamily(
    id: String,
    title: String,
    supportingLines: [String],
    keywords: [String],
    pricePriority: Int,
    priceConfidence: Float
) -> ProductFamily {
    ProductFamily(
        id: id,
        title: title,
        supportingLines: supportingLines,
        keywords: keywords,
        itemNameHint: supportingLines.first,
        priceCandidates: [makeTestPriceCandidate(priority: pricePriority, confidence: priceConfidence, sourceText: supportingLines.joined(separator: " "))]
    )
}

private func makeTestPriceCandidate(priority: Int, confidence: Float, sourceText: String) -> PriceCandidate {
    PriceCandidate(
        label: "$4.99",
        value: Decimal(string: "4.99")!,
        quantity: nil,
        priority: priority,
        sourceText: sourceText,
        confidence: confidence
    )
}
