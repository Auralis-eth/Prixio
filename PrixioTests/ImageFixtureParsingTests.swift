import Foundation
import Testing
import UIKit
@testable import Prixio

@MainActor
struct ImageFixtureParsingTests {
    func assertFixtureLoadsAndProducesOCR(named fixtureName: String) async throws {
        let image = try ImageFixtureTestSupport.loadImage(named: fixtureName)
        let observations = try await ImageFixtureTestSupport.extractObservations(from: image)

        #expect(observations.isEmpty == false, Comment(rawValue: fixtureName))
        #expect(
            observations.contains(where: { $0.string.isMeaningfulObservationLine() }),
            Comment(rawValue: fixtureName)
        )
    }

    func assertFixtureProducesReviewableParse(named fixtureName: String) async throws {
        let image = try ImageFixtureTestSupport.loadImage(named: fixtureName)
        let observations = try await ImageFixtureTestSupport.extractObservations(from: image)
        let result = await PriceParsingService.extract(from: observations)

        #expect(result.rawText.isEmpty == false, Comment(rawValue: fixtureName))
        #expect(result.review.summary.isEmpty == false, Comment(rawValue: fixtureName))
        #expect(
            result.itemNameHint != nil || result.price != nil || !result.priceCandidates.isEmpty,
            Comment(rawValue: fixtureName)
        )

        if result.priceCandidates.isEmpty {
            #expect(result.review.state == .reviewRequired, Comment(rawValue: fixtureName))
        }
    }

    @Test(
        .tags(.ocr, .product, .evaluation, .realWorldOCR),
        arguments: ImageFixtureTestSupport.fixtureBatchA
    )
    func fixtureBatchALoadsAndProducesOCR(named fixtureName: String) async throws {
        try await assertFixtureLoadsAndProducesOCR(named: fixtureName)
    }

    @Test(
        .tags(.ocr, .product, .evaluation, .realWorldOCR),
        arguments: ImageFixtureTestSupport.fixtureBatchB
    )
    func fixtureBatchBLoadsAndProducesOCR(named fixtureName: String) async throws {
        try await assertFixtureLoadsAndProducesOCR(named: fixtureName)
    }

    @Test(
        .tags(.ocr, .product, .evaluation, .realWorldOCR),
        arguments: ImageFixtureTestSupport.fixtureBatchC
    )
    func fixtureBatchCLoadsAndProducesOCR(named fixtureName: String) async throws {
        try await assertFixtureLoadsAndProducesOCR(named: fixtureName)
    }

    @Test(
        .tags(.ocr, .product, .evaluation, .realWorldOCR),
        arguments: ImageFixtureTestSupport.fixtureBatchA
    )
    func fixtureBatchAProducesReviewableParse(named fixtureName: String) async throws {
        try await assertFixtureProducesReviewableParse(named: fixtureName)
    }

    @Test(
        .tags(.ocr, .product, .evaluation, .realWorldOCR),
        arguments: ImageFixtureTestSupport.fixtureBatchB
    )
    func fixtureBatchBProducesReviewableParse(named fixtureName: String) async throws {
        try await assertFixtureProducesReviewableParse(named: fixtureName)
    }

    @Test(
        .tags(.ocr, .product, .evaluation, .realWorldOCR),
        arguments: ImageFixtureTestSupport.fixtureBatchC
    )
    func fixtureBatchCProducesReviewableParse(named fixtureName: String) async throws {
        try await assertFixtureProducesReviewableParse(named: fixtureName)
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func cadburyShelfTagImageFixtureStillProducesAReviewableParse() async throws {
        let image = try ImageFixtureTestSupport.loadImage(
            named: "Screenshot 2026-04-02 at 3.53.44 PM"
        )
        let observations = try await ImageFixtureTestSupport.extractObservations(from: image)
        let result = await PriceParsingService.extract(from: observations)

        #expect(observations.isEmpty == false)
        #expect(result.review.state == .reviewRequired)
        #expect(result.review.usedFoundationModel || result.priceCandidates.isEmpty)
    }

    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func miniCucumberImageFixtureKeepsTitleSeparateFromCardCopy() async throws {
        let image = try ImageFixtureTestSupport.loadImage(named: "IMG_0473")
        let observations = try await ImageFixtureTestSupport.extractObservations(from: image)
        let result = await PriceParsingService.extract(from: observations)

        #expect(observations.map(\.string) == [
            "MINI CUCUMBER",
            "Perfect for snacking",
            "High water content helps to keep you",
            "hydrated",
            "$4.00"
        ])
        #expect(result.itemNameHint?.localizedCaseInsensitiveContains("mini cucumber") == true)
        #expect(result.price == Decimal(string: "4"))
        #expect(result.unit == nil)
        #expect(result.quantity == nil)
        #expect(result.review.state == .reviewRecommended)
        #expect(result.review.usedFoundationModel == false)
        #expect(result.priceCandidates.map(\.value) == [Decimal(4)])
        #expect(result.supportingLines == [
            "MINI CUCUMBER",
            "Perfect for snacking",
            "High water content helps to keep you",
            "hydrated",
            "$4.00"
        ])
    }
}
