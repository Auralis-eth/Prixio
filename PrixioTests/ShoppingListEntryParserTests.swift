import Foundation
import Testing
@testable import Prixio

/// Tests for the deterministic pieces of shopping-list entry parsing: answer
/// validation (fields must be built from the entry's own words), word folding, the
/// cache, and the cache-first/gated flow. Model generation is gated off in unit
/// tests (`OnDeviceModelGate`) and validated on device runs.
@Suite("Shopping-list entry parsing")
struct ShoppingListEntryParserTests {
    @Test("A sound split is kept; each field must use the entry's own words")
    func soundSplitKept() {
        let generated = GeneratedShoppingListEntry(
            itemName: "eggs", brand: "PC", quantityNote: "half a dozen"
        )
        let parsed = ShoppingListEntryParser.validated(
            generated, forRawEntry: "half a dozen PC eggs for the weekend"
        )
        #expect(parsed == ParsedShoppingListEntry(itemName: "eggs", brand: "PC", quantityNote: "half a dozen"))
    }

    @Test("An item name with invented words rejects the whole answer")
    func inventedItemNameRejected() {
        let generated = GeneratedShoppingListEntry(itemName: "chicken breast", brand: nil, quantityNote: nil)
        #expect(ShoppingListEntryParser.validated(generated, forRawEntry: "2 dozen eggs") == nil)
    }

    @Test("A drifting brand or quantity is dropped without losing the item")
    func driftingFieldsDropped() {
        let generated = GeneratedShoppingListEntry(
            itemName: "eggs", brand: "President's Choice", quantityNote: "12"
        )
        let parsed = ShoppingListEntryParser.validated(generated, forRawEntry: "2 dozen PC eggs")
        #expect(parsed?.itemName == "eggs")
        // Neither "President's Choice" nor "12" appears verbatim in the entry.
        #expect(parsed?.brand == nil)
        #expect(parsed?.quantityNote == nil)
    }

    @Test("An answer that changes nothing returns nil")
    func noChangeReturnsNil() {
        let generated = GeneratedShoppingListEntry(itemName: "Organic Eggs", brand: nil, quantityNote: nil)
        #expect(ShoppingListEntryParser.validated(generated, forRawEntry: "organic eggs") == nil)
    }

    @Test("Product-defining descriptors survive in the item name")
    func descriptorsSurvive() {
        let generated = GeneratedShoppingListEntry(
            itemName: "organic whole wheat bread", brand: nil, quantityNote: "2"
        )
        let parsed = ShoppingListEntryParser.validated(
            generated, forRawEntry: "2 organic whole wheat bread"
        )
        #expect(parsed?.itemName == "organic whole wheat bread")
        #expect(parsed?.quantityNote == "2")
    }

    @Test("Word folding keeps quantity and unit words, unlike the item normalizer")
    func foldedWordsKeepUnits() {
        #expect(ShoppingListEntryParser.foldedWords(of: "Half a Dozen Eggs") == ["half", "a", "dozen", "eggs"])
        #expect(ShoppingListEntryParser.foldedWords(of: "2 kg") == ["2", "kg"])
        #expect(ShoppingListEntryParser.foldedWords(of: "  ") == [])
    }

    @Test("The parse cache round-trips through its file")
    func cacheRoundTrips() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "entry-parse-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let parsed = ParsedShoppingListEntry(itemName: "eggs", brand: "PC", quantityNote: "2 dozen")
        let cache = ShoppingListEntryParseCache(fileURL: fileURL, maxEntries: 100)
        await cache.store("2 dozen pc eggs", value: parsed)

        let reloaded = ShoppingListEntryParseCache(fileURL: fileURL, maxEntries: 100)
        #expect(await reloaded.lookup("2 dozen pc eggs") == parsed)
        #expect(await reloaded.lookup("unknown") == nil)
    }

    @Test("A cached entry is answered without the model; misses stay nil when gated")
    func cacheFirstAndGated() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "entry-parse-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let cache = ShoppingListEntryParseCache(fileURL: fileURL, maxEntries: 100)
        let parsed = ParsedShoppingListEntry(itemName: "eggs", brand: nil, quantityNote: "2 dozen")
        await cache.store("2 dozen eggs", value: parsed)

        let parser = ShoppingListEntryParser(cache: cache)
        // Cache hit (case-insensitive key) — never reaches the (test-gated) model.
        #expect(await parser.parse(" 2 Dozen Eggs ") == parsed)
        // Cache miss — generation is gated off in tests, so no parse.
        #expect(await parser.parse("3 cans of tomato soup") == nil)
        // Single-word entries have nothing to split.
        #expect(await parser.parse("milk") == nil)
    }
}
