import Testing
@testable import Prixio

struct ItemKeyNormalizerTests {
    @Test
    func normalizesPunctuationWhitespaceAndCase() {
        #expect(ItemKeyNormalizer.normalize("  Organic, MILK!!  ") == "organic milk")
    }

    @Test
    func singularizesSimplePluralProductWords() {
        #expect(ItemKeyNormalizer.normalize("Bananas") == "banana")
        #expect(ItemKeyNormalizer.normalize("Strawberries") == "strawberry")
    }

    @Test
    func collapsesSibilantAndOPluralsWithTheirSingulars() {
        // Plurals that add "-es" must reduce to the same key as their singular form.
        #expect(ItemKeyNormalizer.normalize("Tomatoes") == ItemKeyNormalizer.normalize("Tomato"))
        #expect(ItemKeyNormalizer.normalize("Potatoes") == ItemKeyNormalizer.normalize("Potato"))
        #expect(ItemKeyNormalizer.normalize("Peaches") == ItemKeyNormalizer.normalize("Peach"))
        #expect(ItemKeyNormalizer.normalize("Boxes") == ItemKeyNormalizer.normalize("Box"))
        #expect(ItemKeyNormalizer.normalize("Tomatoes") == "tomato")
        #expect(ItemKeyNormalizer.normalize("Peaches") == "peach")
    }

    @Test
    func doesNotOverStemNonSibilantWords() {
        // "houses"/"roses" must not be treated as sibilant "-es" plurals.
        #expect(ItemKeyNormalizer.normalize("Roses") == "rose")
        #expect(ItemKeyNormalizer.normalize("Houses") == "house")
    }

    @Test
    func removesUnitAndSizeNoise() {
        #expect(ItemKeyNormalizer.normalize("Yellow Onions 3 lb") == "yellow onion")
        #expect(ItemKeyNormalizer.normalize("Greek Yogurt 750g") == "greek yogurt")
        #expect(ItemKeyNormalizer.normalize("Sparkling Water 6 pack") == "sparkling water")
    }

    @Test
    func keepsBrandLikeTextWhenItIdentifiesTheItem() {
        #expect(ItemKeyNormalizer.normalize("PC Blue Menu Black Beans 540 ml") == "pc blue menu black bean")
    }

    @Test
    func genericQueryMatchesMoreSpecificProducts() {
        // A generic shopping name rolls up specific scanned products that satisfy it.
        #expect(ItemKeyNormalizer.matches(queryKey: "sour cream", entryKey: "Daisy Sour Cream"))
        #expect(ItemKeyNormalizer.matches(queryKey: "butter", entryKey: "Salted Butter 454g"))
        #expect(ItemKeyNormalizer.matches(queryKey: "milk", entryKey: "Almond Milk"))
    }

    @Test
    func identicalItemsMatch() {
        #expect(ItemKeyNormalizer.matches(queryKey: "Sour Cream", entryKey: "sour cream"))
    }

    @Test
    func specificQueryDoesNotMatchBroaderEntry() {
        // Matching is directional: a specific query must not roll up under a broader entry.
        #expect(!ItemKeyNormalizer.matches(queryKey: "Daisy Sour Cream", entryKey: "sour cream"))
    }

    @Test
    func unrelatedItemsDoNotMatch() {
        #expect(!ItemKeyNormalizer.matches(queryKey: "cream cheese", entryKey: "sour cream"))
    }

    @Test
    func genericQueryDoesNotMatchWhenItIsOnlyAModifier() {
        // The generic word being a modifier in the entry (not its head noun) must not match: a
        // shopper asking for "milk"/"cream" shouldn't roll up these compound products.
        #expect(!ItemKeyNormalizer.matches(queryKey: "milk", entryKey: "Milk Chocolate"))
        #expect(!ItemKeyNormalizer.matches(queryKey: "cream", entryKey: "Cream Cheese"))
        #expect(!ItemKeyNormalizer.matches(queryKey: "cream", entryKey: "Cream Soda"))
    }

    @Test
    func emptyQueryNeverRollsUpRealProducts() {
        #expect(!ItemKeyNormalizer.matches(queryKey: "", entryKey: "sour cream"))
        #expect(!ItemKeyNormalizer.matches(queryKey: "  ", entryKey: "sour cream"))
    }
}
