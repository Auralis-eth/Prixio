import Foundation
import Testing
@testable import Prixio

/// Tests for the deterministic pieces of expense-category suggestion: the merchant
/// cache key, the cache itself, and the cache-first/gated flow. Model generation is
/// gated off in unit tests (`OnDeviceModelGate`) and validated on device runs.
@Suite("Expense category suggestion")
struct ExpenseCategorySuggesterTests {
    private func temporaryCache() -> (cache: ExpenseCategorySuggestionCache, fileURL: URL) {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "category-cache-\(UUID().uuidString).json")
        return (ExpenseCategorySuggestionCache(fileURL: fileURL, maxEntries: 100), fileURL)
    }

    @Test("The cache key folds case, diacritics, and whitespace")
    func cacheKeyFolding() {
        #expect(ExpenseCategorySuggester.cacheKey(forMerchant: " NETFLIX ") == "netflix")
        #expect(ExpenseCategorySuggester.cacheKey(forMerchant: "Café Olé") == "cafe ole")
        #expect(ExpenseCategorySuggester.cacheKey(forMerchant: "   ") == "")
    }

    @Test("The cache round-trips through its file")
    func cacheRoundTrips() async {
        let (cache, fileURL) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await cache.store("netflix", value: .subscriptions)

        let reloaded = ExpenseCategorySuggestionCache(fileURL: fileURL, maxEntries: 100)
        #expect(await reloaded.lookup("netflix") == .subscriptions)
        #expect(await reloaded.lookup("unknown") == nil)
    }

    @Test("A cached merchant is answered without the model; a miss stays nil when gated")
    func cacheFirstAndGated() async {
        let (cache, fileURL) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        await cache.store("enmax", value: .utilities)

        let suggester = ExpenseCategorySuggester(cache: cache)
        // Cache hit — never reaches the (test-gated) model.
        #expect(await suggester.suggestCategory(merchant: "ENMAX", note: nil) == .utilities)
        // Cache miss — generation is gated off in tests, so no suggestion.
        #expect(await suggester.suggestCategory(merchant: "Some New Store", note: nil) == nil)
        // Blank merchants never suggest.
        #expect(await suggester.suggestCategory(merchant: "  ", note: nil) == nil)
    }
}
