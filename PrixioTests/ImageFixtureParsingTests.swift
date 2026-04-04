import Foundation
import Testing
import UIKit
@testable import Prixio

@MainActor
struct ImageFixtureParsingTests {
    @Test(.tags(.ocr, .product, .evaluation, .realWorldOCR))
    func cadburyShelfTagImageFixtureKeepsWinningShelfPrice() async throws {
        let image = try ImageFixtureTestSupport.loadImage(
            named: "Screenshot 2026-04-02 at 3.53.44 PM"
        )
        let observations = try await ImageFixtureTestSupport.extractObservations(from: image)
        let result = await PriceParsingService.extract(from: observations)

        #expect(observations.contains(where: { $0.string == "1799" }))
        #expect(observations.contains(where: { $0.string == "$5.00 ea" }))
        #expect(result.itemNameHint == "Cadbury Chocolate Mini Eggs")
        #expect(result.price == Decimal(string: "17.99"))
        #expect(result.unit == .each)
        #expect(result.review.state == .reviewRequired)
        #expect(result.review.usedFoundationModel)
        #expect(result.priceCandidates.first?.value == Decimal(string: "17.99"))
        #expect(result.priceCandidates.contains(where: { $0.value == Decimal(string: "5") }))
        #expect(result.supportingLines.contains("1799"))
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
        #expect(result.itemNameHint == "MINI CUCUMBER")
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
