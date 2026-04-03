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
        #expect(result.review.usedFoundationModel)
        #expect(result.priceCandidates.first?.value == Decimal(string: "17.99"))
        #expect(result.priceCandidates.contains(where: { $0.value == Decimal(string: "5") }))
        #expect(result.supportingLines.contains("1799"))
    }
}
