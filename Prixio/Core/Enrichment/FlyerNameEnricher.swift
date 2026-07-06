import Foundation
import FoundationModels

/// The lexical enrichment of one messy product name — the knowledge the shared
/// deterministic normalizer can't derive: which words are the product, and which are
/// brand/size/marketing noise (FlyerOutstandingWork item 4).
nonisolated struct EnrichedProductName: Codable, Equatable, Sendable {
    /// The product's core name with brand, package size, and marketing phrases
    /// removed (e.g. "Chicken Breast Boneless Skinless Club Pack" → "chicken breast").
    let canonicalName: String
    /// The shortest trailing phrase of the canonical name that names what the product
    /// fundamentally is. A preceding word survives only when dropping it changes the
    /// product ("peanut butter" is not a butter; "sour cream" is a cream).
    let headNoun: String
    /// Coarse substitution class from `FlyerNameEnricher.substitutionClasses` — the
    /// level at which two *different* products are plausible substitutes ("chicken",
    /// "plant-based milk"). `FlyerAlternativeFinder` compares classes for equality.
    /// Optional so enrichments cached before this field existed still decode; those
    /// entries are re-asked on their next use (see `FlyerNameEnricher.enrichments`).
    let substitutionClass: String?

    init(canonicalName: String, headNoun: String, substitutionClass: String? = nil) {
        self.canonicalName = canonicalName
        self.headNoun = headNoun
        self.substitutionClass = substitutionClass
    }
}

/// Supplies name enrichments for deal matching. Absent names simply fall back to
/// deterministic matching, so conformers never need to fail loudly.
protocol FlyerNameEnriching: Sendable {
    /// Enrichments keyed by raw product name. Names the model is unavailable for,
    /// or answers invalidly for, are omitted.
    func enrichments(for names: [String]) async -> [String: EnrichedProductName]
}

/// Gate for on-device generation shared by the enrichment and flyer-text extraction
/// paths: the model must be available, and in-process unit tests never generate
/// (mirroring `PrixioApp.isRunningUnitTests`) so test runs stay deterministic.
enum OnDeviceModelGate {
    static var allowsGeneration: Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }
}

/// Cache-backed, availability-gated product-name enrichment using the on-device
/// model. Sits between flyer extraction and deal matching: matching stays pure and
/// deterministic, this pass only enriches its *inputs*.
///
/// The head noun is grammar-constrained: each name's schema property is an `anyOf`
/// over that name's own normalized tokens and adjacent bigrams, so the model can
/// pick "peanut butter" or "cream" but can never hallucinate a word that isn't in
/// the name. The free-text canonical name is post-validated against the same token
/// set and repaired to the head noun when the model drifts.
struct FlyerNameEnricher: FlyerNameEnriching {
    /// Names per model request. Small enough to keep each request well inside the
    /// context window, large enough that a shopping-list-sized batch is 1–3 calls.
    static let batchSize = 12

    var cache: FlyerNameEnrichmentCache = sharedFlyerNameEnrichmentCache

    func enrichments(for names: [String]) async -> [String: EnrichedProductName] {
        var unique: [String] = []
        var seen = Set<String>()
        for name in names where seen.insert(name).inserted {
            unique.append(name)
        }
        guard !unique.isEmpty else { return [:] }

        var out = await cache.lookup(unique)
        // A cached entry without a substitution class predates the field; treat it as
        // a miss so it is regenerated with one. If generation is gated or fails, the
        // class-less entry still serves head-noun matching exactly as before.
        let missing = unique.filter { out[$0]?.substitutionClass == nil }
        guard !missing.isEmpty, OnDeviceModelGate.allowsGeneration else { return out }

        let generated = await generate(names: missing)
        guard !generated.isEmpty else { return out }
        await cache.store(generated)
        out.merge(generated) { _, new in new }
        return out
    }

    // MARK: - Generation

    private func generate(names: [String]) async -> [String: EnrichedProductName] {
        var out: [String: EnrichedProductName] = [:]
        var start = 0
        while start < names.count {
            let chunk = Array(names[start..<min(start + Self.batchSize, names.count)])
            start += Self.batchSize
            // Fresh session per chunk so context stays bounded; a failed chunk is
            // skipped (its names just stay unenriched) rather than aborting the run.
            do {
                let answered = try await generateChunk(chunk)
                out.merge(answered) { _, new in new }
            } catch {
                continue
            }
        }
        return out
    }

    private func generateChunk(_ names: [String]) async throws -> [String: EnrichedProductName] {
        // Names with no usable head-noun choices (unit-only, numeric) can't be asked about.
        let askable = names.compactMap { name -> (name: String, choices: [String])? in
            let choices = Self.headNounChoices(for: name)
            return choices.isEmpty ? nil : (name, choices)
        }
        guard !askable.isEmpty else { return [:] }

        // A flat schema (canonical0/head0/class0/canonical1/…) keeps extraction to
        // simple top-level property reads. Each headN is anyOf-constrained to that
        // name's own tokens/bigrams; each classN references the one shared
        // substitution-class schema so the vocabulary appears once per request.
        let classSchema = DynamicGenerationSchema(
            name: "SubstitutionClass",
            anyOf: Self.substitutionClasses
        )
        var properties: [DynamicGenerationSchema.Property] = []
        for (index, entry) in askable.enumerated() {
            properties.append(DynamicGenerationSchema.Property(
                name: "canonical\(index)",
                description: "Product \(index + 1): core product name with brand, package size, and marketing words removed",
                schema: DynamicGenerationSchema(type: String.self)
            ))
            properties.append(DynamicGenerationSchema.Property(
                name: "head\(index)",
                description: "Product \(index + 1): the shortest trailing phrase naming what the product fundamentally is",
                schema: DynamicGenerationSchema(name: "Head\(index)", anyOf: entry.choices)
            ))
            properties.append(DynamicGenerationSchema.Property(
                name: "class\(index)",
                description: "Product \(index + 1): the substitution class that best describes what kind of product this is",
                schema: DynamicGenerationSchema(referenceTo: "SubstitutionClass")
            ))
        }
        let schema = try GenerationSchema(
            root: DynamicGenerationSchema(name: "ProductNameEnrichments", properties: properties),
            dependencies: [classSchema]
        )

        let session = LanguageModelSession(instructions: {
            """
            You canonicalize grocery product names from Canadian store flyers. For \
            each numbered product name, give its canonical core name (brand, package \
            size, and marketing phrases like "Selected Varieties" removed) and its \
            head noun — the shortest trailing phrase that names what the product \
            fundamentally is. Keep a preceding word in the head noun only when \
            dropping it would change what the product is: peanut butter is not a \
            butter, cream cheese is not a cream, but sour cream is a cream and \
            almond milk is a milk. Also pick each product's substitution class — \
            the kind of product a shopper could swap it for — from the allowed \
            list, using "other" only when nothing fits.
            """
        })
        let listing = askable.enumerated()
            .map { "\($0.offset + 1). \($0.element.name)" }
            .joined(separator: "\n")
        let response = try await session.respond(
            to: "Canonicalize these flyer product names:\n\(listing)",
            schema: schema
        )

        var out: [String: EnrichedProductName] = [:]
        for (index, entry) in askable.enumerated() {
            guard let head = try? response.content.value(String.self, forProperty: "head\(index)") else {
                continue
            }
            let canonical = (try? response.content.value(String.self, forProperty: "canonical\(index)")) ?? head
            let substitutionClass = try? response.content.value(String.self, forProperty: "class\(index)")
            let raw = EnrichedProductName(
                canonicalName: canonical,
                headNoun: head,
                substitutionClass: substitutionClass
            )
            if let valid = Self.validated(raw, forRawName: entry.name) {
                out[entry.name] = valid
            }
        }
        return out
    }

    // MARK: - Deterministic helpers (unit-tested)

    /// The substitution-class vocabulary: coarse product kinds at the level where
    /// two *different* products are plausible swaps ("chicken breast" and "chicken
    /// thighs" are both "chicken"; "soy milk" and "oat milk" are both "plant-based
    /// milk"; "sour cream" and "ice cream" are not the same kind of thing). The
    /// model is grammar-constrained to this list, so class equality is reliable
    /// across separate generation calls — which is what lets the alternative finder
    /// compare classes deterministically.
    static let substitutionClasses: [String] = [
        "dairy milk", "plant-based milk", "cream", "yogurt", "cheese",
        "butter and margarine", "eggs",
        "bread", "buns and rolls", "tortillas and flatbread",
        "breakfast cereal", "oats and hot cereal", "flour and baking",
        "sugar and sweeteners", "cooking oil", "spices and seasonings",
        "condiments and sauces", "salad dressing", "jam and sweet spreads",
        "nut butter",
        "chicken", "turkey", "beef", "pork", "ground meat",
        "bacon and sausage", "deli meat", "fish and seafood",
        "plant-based protein",
        "fresh fruit", "fresh vegetables", "salad greens",
        "frozen fruit and vegetables", "frozen meals", "pizza",
        "ice cream and frozen desserts",
        "soup and broth", "canned vegetables", "canned fruit",
        "canned fish and meat", "beans and lentils",
        "pasta and noodles", "pasta sauce", "rice and grains",
        "chips and snacks", "crackers", "cookies and baked sweets",
        "candy and chocolate", "granola and snack bars", "nuts and dried fruit",
        "juice", "soft drinks", "water", "coffee", "tea",
        "baby food and formula", "pet food",
        "household products", "personal care",
        "other"
    ]

    private static let substitutionClassSet = Set(substitutionClasses)

    /// The allowed head-noun answers for a name: its normalized tokens and adjacent
    /// bigrams, minus purely numeric fragments (a dangling "2" from "2%" must not be
    /// selectable). The `anyOf` grammar constraint means the model literally cannot
    /// answer outside this list.
    static func headNounChoices(for name: String) -> [String] {
        let tokens = ItemKeyNormalizer.tokens(name)
            .filter { $0.contains(where: \.isLetter) }
        guard !tokens.isEmpty else { return [] }
        var choices = tokens
        for index in tokens.indices.dropLast() {
            choices.append("\(tokens[index]) \(tokens[index + 1])")
        }
        var seen = Set<String>()
        return choices.filter { seen.insert($0).inserted }
    }

    /// Validates (and where possible repairs) a model answer against the raw name.
    /// The head noun must be built solely from the name's own tokens — the hard
    /// guarantee matching relies on. A canonical name that drifts outside the name's
    /// tokens, or doesn't end in the head noun, is repaired to the head noun itself.
    static func validated(_ enrichment: EnrichedProductName, forRawName rawName: String) -> EnrichedProductName? {
        let rawTokens = Set(ItemKeyNormalizer.tokens(rawName))
        let headTokens = ItemKeyNormalizer.tokens(enrichment.headNoun)
        guard !headTokens.isEmpty, headTokens.allSatisfy(rawTokens.contains) else {
            return nil
        }
        let head = headTokens.joined(separator: " ")

        let canonicalTokens = ItemKeyNormalizer.tokens(enrichment.canonicalName)
        let canonicalIsSound = !canonicalTokens.isEmpty
            && canonicalTokens.allSatisfy(rawTokens.contains)
            && canonicalTokens.suffix(headTokens.count).elementsEqual(headTokens)
        // The grammar constraint should make an off-vocabulary class impossible, but
        // the field also arrives from the on-disk cache — never trust it blindly.
        let substitutionClass = enrichment.substitutionClass
            .flatMap { substitutionClassSet.contains($0) ? $0 : nil }
        return EnrichedProductName(
            canonicalName: canonicalIsSound ? canonicalTokens.joined(separator: " ") : head,
            headNoun: head,
            substitutionClass: substitutionClass
        )
    }
}

/// On-disk cache for name enrichments (see `EnrichmentDiskCache`). Flyer product
/// names repeat week to week, so after the first run most enrichment lookups never
/// touch the model.
typealias FlyerNameEnrichmentCache = EnrichmentDiskCache<EnrichedProductName>

/// Process-wide instance (a generic type can't hold a `shared` stored property).
/// Capped generously: several banners' weekly flyers over a season.
let sharedFlyerNameEnrichmentCache = FlyerNameEnrichmentCache(
    fileURL: .applicationSupportDirectory.appending(path: "FlyerNameEnrichments.json"),
    maxEntries: 4000
)
