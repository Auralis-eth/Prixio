import Foundation
import FoundationModels

/// A free-text shopping-list entry split into the sheet's structured fields:
/// "half a dozen PC eggs for the weekend" → item "eggs", brand "PC", quantity
/// note "half a dozen".
nonisolated struct ParsedShoppingListEntry: Codable, Equatable, Sendable {
    /// The core item name, with quantities, brands, and filler words removed but
    /// product-defining descriptors kept ("organic eggs" stays "organic eggs").
    let itemName: String
    let brand: String?
    let quantityNote: String?
}

/// Parses one raw shopping-list entry. A `nil` result means "nothing to improve" —
/// the typed text stands exactly as entered, so conformers never need to fail
/// loudly.
protocol ShoppingListEntryParsing: Sendable {
    func parse(_ rawEntry: String) async -> ParsedShoppingListEntry?
}

/// One shopping-list entry split into its parts.
@Generable(description: "A shopping-list entry split into item, brand, and quantity")
struct GeneratedShoppingListEntry {
    @Guide(description: "The core item name with quantities, brand names, and filler words removed. Keep words that define the product, like 'organic' or 'whole wheat'.")
    var itemName: String
    @Guide(description: "The brand name, only if one is mentioned, e.g. 'PC' or 'Kraft'. Null otherwise.")
    var brand: String?
    @Guide(description: "The quantity or amount as written, e.g. '2', 'half a dozen', '2 kg'. Null if none is mentioned.")
    var quantityNote: String?
}

/// Cache-backed, availability-gated entry parsing with the on-device model, in the
/// `FlyerNameEnricher` mould: every returned field is validated to be built solely
/// from the raw entry's own words, so the model can relocate words into the right
/// fields but can never introduce ones the user didn't type. The split lands in the
/// form's visible fields before the user taps Add — that tap is the confirmation.
struct ShoppingListEntryParser: ShoppingListEntryParsing {
    var cache: ShoppingListEntryParseCache = sharedShoppingListEntryParseCache

    func parse(_ rawEntry: String) async -> ParsedShoppingListEntry? {
        let trimmed = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.foldedWords(of: trimmed).count >= 2 else {
            // Single-word entries ("milk") have nothing to split.
            return nil
        }
        let key = trimmed.lowercased()
        if let cached = await cache.lookup(key) {
            return cached
        }
        guard OnDeviceModelGate.allowsGeneration else { return nil }

        let session = LanguageModelSession(instructions: {
            """
            You split one shopping-list entry, as typed by a grocery shopper, into \
            its parts: the core item name, an optional brand, and an optional \
            quantity. Remove filler words ("for the weekend", "don't forget") \
            entirely. Keep descriptors that define the product — organic, whole \
            wheat, boneless — in the item name. Never add words the shopper \
            didn't type.
            """
        })
        guard let generated = try? await session.respond(
            to: "Split this shopping-list entry: \(trimmed)",
            generating: GeneratedShoppingListEntry.self
        ).content else {
            return nil
        }
        guard let parsed = Self.validated(generated, forRawEntry: trimmed) else {
            return nil
        }
        await cache.store(key, value: parsed)
        return parsed
    }

    // MARK: - Deterministic helpers (unit-tested)

    /// Validates a model answer against the raw entry. The item name (and brand)
    /// must be built solely from the entry's own words — the hard guarantee that the
    /// split never invents products. A field that drifts is dropped (brand/quantity)
    /// or rejects the whole answer (item name). An answer that changes nothing
    /// (no brand, no quantity, item name equal to the raw entry) returns nil so
    /// callers don't churn the form.
    static func validated(
        _ generated: GeneratedShoppingListEntry,
        forRawEntry rawEntry: String
    ) -> ParsedShoppingListEntry? {
        let rawWords = Set(foldedWords(of: rawEntry))
        let itemWords = foldedWords(of: generated.itemName)
        guard !itemWords.isEmpty, itemWords.allSatisfy(rawWords.contains) else {
            return nil
        }

        func fieldIfSound(_ value: String?) -> String? {
            guard let value else { return nil }
            let words = foldedWords(of: value)
            guard !words.isEmpty, words.allSatisfy(rawWords.contains) else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let brand = fieldIfSound(generated.brand)
        let quantityNote = fieldIfSound(generated.quantityNote)

        let itemName = generated.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let changesNothing = brand == nil && quantityNote == nil
            && foldedWords(of: rawEntry) == itemWords
        guard !changesNothing else { return nil }
        return ParsedShoppingListEntry(itemName: itemName, brand: brand, quantityNote: quantityNote)
    }

    /// Case/diacritic-folded alphanumeric words. Unlike `ItemKeyNormalizer.tokens`,
    /// unit and quantity words survive — a quantity note like "half a dozen" must be
    /// checkable against the raw entry.
    static func foldedWords(of value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}

/// On-disk cache for entry parses (see `EnrichmentDiskCache`). List entries repeat
/// heavily week to week ("2 milk", "dozen eggs"), so most parses never touch the
/// model.
typealias ShoppingListEntryParseCache = EnrichmentDiskCache<ParsedShoppingListEntry>

/// Process-wide instance (a generic type can't hold a `shared` stored property).
let sharedShoppingListEntryParseCache = ShoppingListEntryParseCache(
    fileURL: .applicationSupportDirectory.appending(path: "ShoppingListEntryParses.json"),
    maxEntries: 600
)
