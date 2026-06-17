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
    func removesUnitAndSizeNoise() {
        #expect(ItemKeyNormalizer.normalize("Yellow Onions 3 lb") == "yellow onion")
        #expect(ItemKeyNormalizer.normalize("Greek Yogurt 750g") == "greek yogurt")
        #expect(ItemKeyNormalizer.normalize("Sparkling Water 6 pack") == "sparkling water")
    }

    @Test
    func keepsBrandLikeTextWhenItIdentifiesTheItem() {
        #expect(ItemKeyNormalizer.normalize("PC Blue Menu Black Beans 540 ml") == "pc blue menu black bean")
    }
}
