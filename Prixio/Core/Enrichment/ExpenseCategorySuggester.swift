import Foundation
import FoundationModels

/// Suggests a spending category for a manually entered expense from its merchant
/// (and optional note). A `nil` result means "no suggestion" — the form's current
/// selection simply stands, so conformers never need to fail loudly.
protocol ExpenseCategorySuggesting: Sendable {
    func suggestCategory(merchant: String, note: String?) async -> ExpenseCategory?
}

/// Cache-backed, availability-gated category suggestion using the on-device model.
/// The response is grammar-constrained to `ExpenseCategory` (`@Generable`), so the
/// model cannot answer outside the enum. Mirrors `FlyerNameEnricher`'s shape: this
/// pass only proposes — the user confirms by saving the form, and a manual pick is
/// never overridden (see `AddExpenseSheet`).
struct ExpenseCategorySuggester: ExpenseCategorySuggesting {
    var cache: ExpenseCategorySuggestionCache = sharedExpenseCategorySuggestionCache

    func suggestCategory(merchant: String, note: String?) async -> ExpenseCategory? {
        let key = Self.cacheKey(forMerchant: merchant)
        guard !key.isEmpty else { return nil }
        if let cached = await cache.lookup(key) {
            return cached
        }
        guard OnDeviceModelGate.allowsGeneration else { return nil }

        let session = LanguageModelSession(instructions: {
            """
            You categorize one household expense into exactly one spending \
            category from its merchant name and an optional note. Categories: \
            groceries (supermarkets and food stores), bills (recurring bills with \
            no better category), utilities (power, gas, water), rent (rent, \
            mortgage, housing), insurance, phoneInternet (phone or internet \
            providers), subscriptions (streaming, memberships, software plans), \
            other (anything else, including restaurants, fuel, and one-off \
            shopping).
            """
        })
        let context = note.map { "Merchant: \(merchant)\nNote: \($0)" } ?? "Merchant: \(merchant)"
        guard let suggestion = try? await session.respond(
            to: "Categorize this expense.\n\(context)",
            generating: ExpenseCategory.self
        ).content else {
            return nil
        }
        await cache.store(key, value: suggestion)
        return suggestion
    }

    /// Merchants repeat; notes vary. The cache keys on the folded merchant alone so
    /// "Netflix", "NETFLIX", and " netflix " share one answer.
    static func cacheKey(forMerchant merchant: String) -> String {
        merchant
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// On-disk cache for merchant → category suggestions (see `EnrichmentDiskCache`).
/// The same merchants recur month to month, so after the first suggestion a
/// merchant never touches the model again.
typealias ExpenseCategorySuggestionCache = EnrichmentDiskCache<ExpenseCategory>

/// Process-wide instance (a generic type can't hold a `shared` stored property).
let sharedExpenseCategorySuggestionCache = ExpenseCategorySuggestionCache(
    fileURL: .applicationSupportDirectory.appending(path: "ExpenseCategorySuggestions.json"),
    maxEntries: 500
)
