import Foundation
import Testing
@testable import Prixio

/// Tests for the LLM name-enrichment pass around deal matching: the deterministic
/// pieces only — the head-noun-aware match rule, answer validation/repair, the
/// enrichment-target prefilter, enrichment application, the enrichment cache, and
/// the flyer-text chunking/mapping helpers. Model generation itself is gated off in
/// unit tests (`OnDeviceModelGate`) and validated on device runs.
@Suite("Flyer name enrichment")
struct FlyerNameEnrichmentTests {
    private func candidate(
        _ name: String,
        price: String = "1.99",
        headNoun: String? = nil,
        canonicalName: String? = nil,
        substitutionClass: String? = nil
    ) -> FlyerPriceCandidate {
        var candidate = FlyerPriceCandidate(
            productName: name,
            normalizedItemKey: ItemKeyNormalizer.normalize(name),
            brand: nil,
            price: Decimal(string: price)!,
            regularPrice: nil,
            priceKind: .regular,
            packageSize: nil,
            unitPrice: nil,
            saleStartDate: nil,
            saleEndDate: nil,
            memberOnly: false,
            sourceText: name,
            confidence: 0.9
        )
        if headNoun != nil || substitutionClass != nil {
            candidate = candidate.enriched(with: EnrichedProductName(
                canonicalName: canonicalName ?? headNoun ?? "",
                headNoun: headNoun ?? "",
                substitutionClass: substitutionClass
            ))
        }
        return candidate
    }

    private func result(_ candidates: [FlyerPriceCandidate]) -> FlyerExtractionResult {
        FlyerExtractionResult(
            banner: FlyerBannerCatalog.banner(for: .safeway)!,
            sourceURL: nil,
            fetchedAt: nil,
            method: .endpointJSON,
            candidates: candidates,
            message: "test"
        )
    }

    private func query(_ name: String) -> FlyerDealMatcher.Query {
        FlyerDealMatcher.Query(itemKey: ItemKeyNormalizer.normalize(name), displayName: name)
    }

    // MARK: - Head-noun-aware matching

    @Test("A trailing descriptor no longer blocks a match when the head noun is known")
    func trailingDescriptorRecallFixed() {
        let entry = "Chicken Breast Boneless Skinless"
        // Today's last-token rule anchors on "skinless" and misses.
        #expect(!ItemKeyNormalizer.matches(queryKey: "chicken breast", entryKey: entry))
        // The enriched head noun restores the match.
        #expect(ItemKeyNormalizer.matches(
            queryKey: "chicken breast", entryKey: entry, entryHeadNoun: "chicken breast"
        ))
    }

    @Test("A compound product no longer rolls up under its generic tail")
    func compoundProductFalsePositiveFixed() {
        let entry = "Kraft Peanut Butter"
        // Today's rule wrongly matches: the entry's last token is "butter".
        #expect(ItemKeyNormalizer.matches(queryKey: "butter", entryKey: entry))
        // The head-noun phrase "peanut butter" must be fully contained in the query.
        #expect(!ItemKeyNormalizer.matches(queryKey: "butter", entryKey: entry, entryHeadNoun: "peanut butter"))
        #expect(ItemKeyNormalizer.matches(queryKey: "peanut butter", entryKey: entry, entryHeadNoun: "peanut butter"))
        #expect(ItemKeyNormalizer.matches(queryKey: "kraft peanut butter", entryKey: entry, entryHeadNoun: "peanut butter"))
    }

    @Test("Modifier products keep matching through their true head noun")
    func modifierProductsStillRollUp() {
        // A sour cream *is* a cream, so the model's head noun is "cream".
        #expect(ItemKeyNormalizer.matches(queryKey: "cream", entryKey: "Daisy Sour Cream", entryHeadNoun: "cream"))
        #expect(ItemKeyNormalizer.matches(queryKey: "sour cream", entryKey: "Daisy Sour Cream", entryHeadNoun: "cream"))
        // Milk chocolate's head noun is "chocolate" — "milk" still can't pull it in.
        #expect(!ItemKeyNormalizer.matches(queryKey: "milk", entryKey: "Milk Chocolate", entryHeadNoun: "chocolate"))
    }

    @Test("A more-specific query still never matches a broader enriched entry")
    func specificQueryStillRejectsBroaderEntry() {
        #expect(!ItemKeyNormalizer.matches(
            queryKey: "daisy sour cream", entryKey: "Sour Cream", entryHeadNoun: "cream"
        ))
    }

    @Test("A nil, empty, or unit-only head noun delegates to the plain rule")
    func nilHeadNounDelegates() {
        let pairs = [("milk", "Almond Milk"), ("milk", "Milk Chocolate"), ("butter", "Peanut Butter")]
        for (query, entry) in pairs {
            // Head nouns carrying no lexical knowledge: absent, blank, or normalizing
            // to no tokens (a unit-only phrase from a corrupted cache entry).
            for headNoun in [nil, "", "  ", "454g", "2 kg"] {
                #expect(
                    ItemKeyNormalizer.matches(queryKey: query, entryKey: entry, entryHeadNoun: headNoun)
                        == ItemKeyNormalizer.matches(queryKey: query, entryKey: entry)
                )
            }
        }
    }

    // MARK: - Matcher integration

    @Test("The matcher uses enrichment when present and falls back when absent")
    func matcherUsesEnrichment() {
        let extractions = [result([
            candidate("Chicken Breast Boneless Skinless", price: "9.99", headNoun: "chicken breast", canonicalName: "chicken breast"),
            candidate("Kraft Peanut Butter", price: "4.99", headNoun: "peanut butter", canonicalName: "peanut butter"),
            candidate("Salted Butter", price: "5.49")
        ])]
        let matches = FlyerDealMatcher().match(
            queries: [query("chicken breast"), query("butter")],
            extractions: extractions
        )

        let chicken = matches.first { $0.displayName == "chicken breast" }
        #expect(chicken?.deals.count == 1)
        #expect(chicken?.bestDeal?.candidate.productName == "Chicken Breast Boneless Skinless")

        // "butter" keeps the unenriched salted butter but no longer sees peanut butter.
        let butter = matches.first { $0.displayName == "butter" }
        #expect(butter?.deals.map(\.candidate.productName) == ["Salted Butter"])
    }

    @Test("applyingEnrichments only touches candidates whose names are enriched")
    func applyingEnrichmentsIsTargeted() {
        let extraction = result([candidate("Kraft Peanut Butter"), candidate("Salted Butter")])
        let applied = extraction.applyingEnrichments([
            "Kraft Peanut Butter": EnrichedProductName(canonicalName: "peanut butter", headNoun: "peanut butter")
        ])
        #expect(applied.candidates[0].enrichedItemKey == "peanut butter")
        #expect(applied.candidates[0].enrichedHeadNoun == "peanut butter")
        #expect(applied.candidates[1].enrichedItemKey == nil)
        #expect(applied.candidates[1].enrichedHeadNoun == nil)
        // An empty map is a no-op.
        #expect(extraction.applyingEnrichments([:]) == extraction)
    }

    @Test("Enrichment targets are the candidates a query's tokens could touch")
    func enrichmentTargetPrefilter() {
        let extractions = [result([
            candidate("Chicken Breast Boneless Skinless"),   // superset of "chicken breast"
            candidate("Kraft Peanut Butter"),                // superset of "butter" (false-positive direction)
            candidate("Ground Beef Lean"),                   // shares no query's full token set
            candidate("Whipped Butter", headNoun: "butter")  // already enriched — skipped
        ])]
        let targets = FlyerDealMatcher.enrichmentTargets(
            queries: [query("chicken breast"), query("butter")],
            extractions: extractions
        )
        #expect(Set(targets) == ["Chicken Breast Boneless Skinless", "Kraft Peanut Butter"])
    }

    // MARK: - Answer validation

    @Test("A head noun with a token not in the name is rejected")
    func hallucinatedHeadNounRejected() {
        let answer = EnrichedProductName(canonicalName: "chicken breast", headNoun: "poultry")
        #expect(FlyerNameEnricher.validated(answer, forRawName: "Chicken Breast Boneless") == nil)
    }

    @Test("A drifting canonical name is repaired to the head noun")
    func driftingCanonicalRepaired() {
        let junkCanonical = EnrichedProductName(canonicalName: "fresh never frozen", headNoun: "chicken breast")
        let repaired = FlyerNameEnricher.validated(junkCanonical, forRawName: "Chicken Breast Boneless Skinless")
        #expect(repaired == EnrichedProductName(canonicalName: "chicken breast", headNoun: "chicken breast"))

        // A canonical name that doesn't end in the head noun is also repaired.
        let reordered = EnrichedProductName(canonicalName: "breast chicken", headNoun: "chicken breast")
        let fixed = FlyerNameEnricher.validated(reordered, forRawName: "Chicken Breast Boneless Skinless")
        #expect(fixed?.canonicalName == "chicken breast")
    }

    @Test("A sound answer is kept, normalized")
    func soundAnswerKept() {
        let answer = EnrichedProductName(canonicalName: "Peanut Butter", headNoun: "Peanut Butter")
        let valid = FlyerNameEnricher.validated(answer, forRawName: "Kraft Peanut Butter 1 kg")
        #expect(valid == EnrichedProductName(canonicalName: "peanut butter", headNoun: "peanut butter"))
    }

    @Test("Head-noun choices are the name's own tokens and bigrams, letters only")
    func headNounChoices() {
        let choices = FlyerNameEnricher.headNounChoices(for: "2% Milk 4L")
        #expect(choices == ["milk"])

        let compound = FlyerNameEnricher.headNounChoices(for: "Kraft Peanut Butter")
        #expect(compound.contains("peanut butter"))
        #expect(compound.contains("butter"))
        #expect(!compound.contains("butter kraft"))
    }

    // MARK: - Alternative finder

    @Test("An enriched head noun re-anchors alternative similarity")
    func alternativeAnchorsOnEnrichedHead() {
        // Head noun "chocolate": no longer offered as an alternative for "milk".
        #expect(!FlyerAlternativeFinder.isAlternative(
            queryKey: "milk", candidateKey: "milk chocolate bar", candidateHeadNoun: "chocolate"
        ))
        // Trailing-descriptor candidate becomes a valid "breast"-anchored suggestion.
        #expect(FlyerAlternativeFinder.isAlternative(
            queryKey: "turkey breast", candidateKey: "chicken breast boneless skinless", candidateHeadNoun: "chicken breast"
        ))
    }

    // MARK: - Substitution classes

    @Test("Matching classes make unrelated head nouns substitutable")
    func classEqualityDecidesSimilarity() {
        // The lexical rule can't: heads "thigh" vs "breast".
        #expect(!FlyerAlternativeFinder.isAlternative(
            queryKey: "chicken thighs", candidateKey: "chicken breast boneless skinless", candidateHeadNoun: "chicken breast"
        ))
        #expect(FlyerAlternativeFinder.isAlternative(
            queryKey: "chicken thighs", candidateKey: "chicken breast boneless skinless",
            candidateHeadNoun: "chicken breast", queryClass: "chicken", candidateClass: "chicken"
        ))
    }

    @Test("Differing classes reject a shared-head-noun collision")
    func classMismatchRejectsHeadCollision() {
        // The lexical rule wrongly suggests: both heads are "cream".
        #expect(FlyerAlternativeFinder.isAlternative(queryKey: "sour cream", candidateKey: "ice cream"))
        #expect(!FlyerAlternativeFinder.isAlternative(
            queryKey: "sour cream", candidateKey: "ice cream",
            queryClass: "cream", candidateClass: "ice cream and frozen desserts"
        ))
    }

    @Test("A class missing on either side falls back to the head-noun rule")
    func missingClassFallsBack() {
        for (queryClass, candidateClass) in [(nil, "cream"), ("cream", nil), (nil, nil)] as [(String?, String?)] {
            #expect(
                FlyerAlternativeFinder.isAlternative(
                    queryKey: "sour cream", candidateKey: "whipping cream",
                    queryClass: queryClass, candidateClass: candidateClass
                )
            )
        }
    }

    @Test("The same product is never its own alternative, even with equal classes")
    func sameProductNeverAlternative() {
        #expect(!FlyerAlternativeFinder.isAlternative(
            queryKey: "2% Milk", candidateKey: "2 milk",
            queryClass: "dairy milk", candidateClass: "dairy milk"
        ))
    }

    @Test("Validation keeps a vocabulary class and drops an off-vocabulary one")
    func classValidation() {
        let good = EnrichedProductName(canonicalName: "chicken breast", headNoun: "chicken breast", substitutionClass: "chicken")
        #expect(FlyerNameEnricher.validated(good, forRawName: "Chicken Breast Boneless")?.substitutionClass == "chicken")

        let junkClass = EnrichedProductName(canonicalName: "chicken breast", headNoun: "chicken breast", substitutionClass: "poultry cuts")
        let validated = FlyerNameEnricher.validated(junkClass, forRawName: "Chicken Breast Boneless")
        // The enrichment survives; only the unusable class is dropped.
        #expect(validated?.headNoun == "chicken breast")
        #expect(validated?.substitutionClass == nil)
    }

    @Test("Enrichment application carries the class onto the candidate")
    func enrichedCandidateCarriesClass() {
        let extraction = result([candidate("Chicken Breast Boneless")])
        let applied = extraction.applyingEnrichments([
            "Chicken Breast Boneless": EnrichedProductName(
                canonicalName: "chicken breast", headNoun: "chicken breast", substitutionClass: "chicken"
            )
        ])
        #expect(applied.candidates[0].enrichedSubstitutionClass == "chicken")
    }

    @Test("Alternative enrichment targets share a substantive token with a query")
    func alternativeEnrichmentTargetPrefilter() {
        let extractions = [result([
            candidate("Chicken Breast Boneless Skinless"),                        // shares "chicken"
            candidate("Ground Beef Lean"),                                        // shares nothing
            candidate("Chicken Thighs Club Pack", substitutionClass: "chicken")   // already classed — skipped
        ])]
        let targets = FlyerAlternativeFinder.enrichmentTargets(
            queries: [query("chicken thighs")],
            extractions: extractions
        )
        #expect(targets == ["Chicken Breast Boneless Skinless"])
    }

    @Test("The finder suggests class-matched deals through query enrichments")
    func findAlternativesUsesClasses() {
        let extractions = [result([
            candidate("Chicken Breast Boneless Skinless", price: "8.99", headNoun: "chicken breast", canonicalName: "chicken breast", substitutionClass: "chicken"),
            candidate("Ice Cream Vanilla", price: "3.99", headNoun: "ice cream", canonicalName: "ice cream", substitutionClass: "ice cream and frozen desserts")
        ])]
        let itemKey = ItemKeyNormalizer.normalize("chicken thighs")
        let matches = FlyerDealMatcher().match(queries: [query("chicken thighs")], extractions: extractions)
        let alternatives = FlyerAlternativeFinder().findAlternatives(
            matches: matches,
            extractions: extractions,
            queryEnrichments: [itemKey: EnrichedProductName(
                canonicalName: "chicken thigh", headNoun: "chicken thigh", substitutionClass: "chicken"
            )]
        )
        #expect(alternatives.count == 1)
        #expect(alternatives.first?.alternatives.map(\.candidate.productName) == ["Chicken Breast Boneless Skinless"])
    }

    // MARK: - Cache

    @Test("The enrichment cache round-trips through its file")
    func cacheRoundTrips() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "enrichment-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let enrichment = EnrichedProductName(canonicalName: "peanut butter", headNoun: "peanut butter")
        let cache = FlyerNameEnrichmentCache(fileURL: fileURL, maxEntries: 100)
        await cache.store(["Kraft Peanut Butter": enrichment])

        // A fresh instance reads the same file.
        let reloaded = FlyerNameEnrichmentCache(fileURL: fileURL, maxEntries: 100)
        let hits = await reloaded.lookup(["Kraft Peanut Butter", "Unknown Product"])
        #expect(hits == ["Kraft Peanut Butter": enrichment])
    }

    // MARK: - Flyer-text model extraction helpers

    @Test("Priced-line chunking keeps only $ lines and respects budgets")
    func pricedLineChunking() {
        let payload = """
        Weekly Flyer — Valid July 3 to July 9
        Boneless Skinless Chicken Breast $9.99
        Sign up for our newsletter
        2% Milk 4L $5.49
        """
        let chunks = FoundationModelsFlyerTextExtractor.pricedLineChunks(from: payload)
        #expect(chunks == ["Boneless Skinless Chicken Breast $9.99\n2% Milk 4L $5.49"])

        // Budget forces a split; maxChunks caps output.
        let many = Array(repeating: "Product Line $1.99", count: 50).joined(separator: "\n")
        let capped = FoundationModelsFlyerTextExtractor.pricedLineChunks(from: many, budget: 60, maxChunks: 3)
        #expect(capped.count == 3)
        #expect(capped.allSatisfy { $0.count <= 60 })
    }

    @Test("Generated text deals map to candidates with plausibility rules applied")
    func generatedDealMapping() {
        let good = GeneratedFlyerTextDeal(
            productName: "Boneless Skinless Chicken Breast",
            price: 9.99,
            sizeText: "per kg",
            memberOnly: false
        )
        let candidate = FoundationModelsFlyerTextExtractor.candidate(from: good)
        #expect(candidate?.price == Decimal(string: "9.99"))
        #expect(candidate?.normalizedItemKey == ItemKeyNormalizer.normalize("Boneless Skinless Chicken Breast"))
        #expect(candidate?.confidence == FoundationModelsFlyerTextExtractor.confidence)
        #expect(candidate?.packageSize == "per kg")

        let implausible = GeneratedFlyerTextDeal(productName: "Milk", price: 0, sizeText: nil, memberOnly: false)
        #expect(FoundationModelsFlyerTextExtractor.candidate(from: implausible) == nil)

        let nonProduct = GeneratedFlyerTextDeal(productName: "12345", price: 3.99, sizeText: nil, memberOnly: false)
        #expect(FoundationModelsFlyerTextExtractor.candidate(from: nonProduct) == nil)

        let member = GeneratedFlyerTextDeal(productName: "Coffee", price: 12.99, sizeText: nil, memberOnly: true)
        #expect(FoundationModelsFlyerTextExtractor.candidate(from: member)?.priceKind == .member)
    }
}
