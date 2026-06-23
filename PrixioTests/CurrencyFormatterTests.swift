import Foundation
import Testing
@testable import Prixio

struct CurrencyFormatterTests {
    @Test(arguments: [
        (Decimal(0), "0.00"),
        (Decimal(string: "0.5")!, "0.50"),
        (Decimal(string: "12.345")!, "12.34"),
        (Decimal(string: "999999.99")!, "999999.99")
    ])
    func editableString_returnsTwoDecimalGroupingFreeText_givenBoundaryValues(value: Decimal, expected: String) {
        let text = CurrencyFormatter.shared.editableString(value)

        #expect(text == expected)
        #expect(!text.contains(","))
    }

    @Test(arguments: [
        ("0", Decimal(0)),
        (" 12.50 ", Decimal(string: "12.50")!),
        ("12,50", Decimal(string: "12.50")!),
        ("999999.99", Decimal(string: "999999.99")!),
        ("-1.25", Decimal(string: "-1.25")!)
    ])
    func price_parsesValidNumericText_givenSupportedSeparators(text: String, expected: Decimal) throws {
        let parsed = try #require(CurrencyFormatter.shared.price(from: text))

        #expect(parsed == expected)
    }

    @Test(arguments: ["", "   ", "abc", "$12.00", "12.3.4"])
    func price_returnsNil_givenInvalidOrEmptyText(text: String) {
        #expect(CurrencyFormatter.shared.price(from: text) == nil)
    }

    @Test
    func editableString_roundTripsThroughPriceParser_givenLargeValue() throws {
        let value = try #require(Decimal(string: "1234567.89"))

        let editable = CurrencyFormatter.shared.editableString(value)
        let parsed = try #require(CurrencyFormatter.shared.price(from: editable))

        #expect(editable == "1234567.89")
        #expect(parsed == value)
    }
}
