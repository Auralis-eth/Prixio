import Foundation
import FoundationModels

/// Extracts structured deals from harvested flyer *text* with the on-device model.
/// This is the migration of `FlyerPriceExtractor`'s lowest-confidence strategy (the
/// line-pairing heuristic for `.staticHTML`/`.renderedHTML`/`.imageOCR` payloads):
/// the deterministic path remains the floor — a `nil` result means "model
/// unavailable or failed, keep the deterministic candidates".
protocol FlyerTextCandidateExtracting: Sendable {
    func extractCandidates(fromText payload: String) async -> [FlyerPriceCandidate]?
}

/// One advertised deal read from flyer text.
@Generable(description: "One advertised grocery deal found in flyer text")
struct GeneratedFlyerTextDeal {
    @Guide(description: "Product name as advertised, without price, size, or promo wording")
    var productName: String
    @Guide(description: "Advertised dollar price, e.g. 3.99")
    var price: Double
    @Guide(description: "Package size text if shown, e.g. '500 g' or '12 x 355 mL'")
    var sizeText: String?
    @Guide(description: "True when the price requires a loyalty card, membership, or digital coupon")
    var memberOnly: Bool
}

struct FoundationModelsFlyerTextExtractor: FlyerTextCandidateExtracting {
    /// Model-read candidates rank between harvested-text pairing (0.5) and captured
    /// JSON (0.9): the model reads context a line heuristic can't, but the source is
    /// still unstructured text.
    static let confidence: Float = 0.7
    /// Character budget per model request, so each chunk stays well inside the
    /// context window.
    static let chunkCharacterBudget = 2200
    /// Upper bound on requests per payload — latency control for pathological pages.
    static let maxChunks = 6
    /// A single flyer line never needs more than this; longer runs are page scripts
    /// or concatenated markup, truncated so one line can't eat a chunk.
    static let maxLineLength = 200

    func extractCandidates(fromText payload: String) async -> [FlyerPriceCandidate]? {
        guard OnDeviceModelGate.allowsGeneration else { return nil }
        let chunks = Self.pricedLineChunks(from: payload)
        guard !chunks.isEmpty else { return nil }

        var candidates: [FlyerPriceCandidate] = []
        var seen = Set<String>()
        var anyChunkSucceeded = false
        for chunk in chunks {
            // Fresh session per chunk: bounded context, and one failed chunk doesn't
            // poison the rest.
            let session = LanguageModelSession(instructions: {
                """
                You extract advertised grocery deals from raw flyer page text, mostly \
                from Canadian grocery stores. The text is noisy: navigation, legal \
                lines, and dates are mixed in with real deals. List every distinct \
                product with an advertised dollar price. Skip prices that are not for \
                a product (delivery fees, donation asks, totals). Per-unit comparison \
                prices like "$1.10 / 100 g" are not the advertised price. For \
                multi-buy deals like "2 for $5", use the single advertised total \
                (5) only when no single-unit price is shown.
                """
            })
            do {
                let response = try await session.respond(
                    to: "Extract the advertised deals from this flyer text:\n\n\(chunk)",
                    generating: [GeneratedFlyerTextDeal].self
                )
                anyChunkSucceeded = true
                for item in response.content {
                    guard let candidate = Self.candidate(from: item) else { continue }
                    let key = "\(candidate.normalizedItemKey)|\(candidate.price)"
                    if seen.insert(key).inserted {
                        candidates.append(candidate)
                    }
                }
            } catch {
                continue
            }
        }
        // All chunks failing means the model path is broken right now — report nil so
        // the caller keeps the deterministic result rather than an empty one.
        return anyChunkSucceeded ? candidates : nil
    }

    // MARK: - Deterministic helpers (unit-tested)

    /// Packs the payload's `$`-priced lines into prompt-sized chunks: only lines
    /// carrying a dollar price can yield a deal, so everything else is dropped before
    /// any tokens are spent. Returns at most `maxChunks` chunks.
    static func pricedLineChunks(
        from payload: String,
        budget: Int = chunkCharacterBudget,
        maxChunks: Int = maxChunks
    ) -> [String] {
        var chunks: [String] = []
        var current = ""
        for rawLine in payload.split(whereSeparator: { $0 == "\n" || $0 == "\t" }) {
            let line = String(rawLine.trimmingCharacters(in: .whitespaces).prefix(maxLineLength))
            guard line.contains("$") else { continue }
            if !current.isEmpty, current.count + line.count + 1 > budget {
                chunks.append(current)
                guard chunks.count < maxChunks else { return chunks }
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty, chunks.count < maxChunks {
            chunks.append(current)
        }
        return chunks
    }

    /// Maps one generated deal to a candidate, applying the same plausibility rules
    /// as the deterministic extractor. Returns nil for junk the model shouldn't have
    /// produced (implausible price, non-product name).
    static func candidate(from item: GeneratedFlyerTextDeal) -> FlyerPriceCandidate? {
        let name = item.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= 120,
              name.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 2,
              let price = Decimal(string: String(format: "%.2f", item.price)),
              price >= Decimal(string: "0.01")!, price <= 9999 else {
            return nil
        }
        let normalizedKey = ItemKeyNormalizer.normalize(name)
        guard !normalizedKey.isEmpty else { return nil }

        return FlyerPriceCandidate(
            productName: name,
            normalizedItemKey: normalizedKey,
            brand: nil,
            price: price,
            regularPrice: nil,
            priceKind: item.memberOnly ? .member : .unknown,
            packageSize: item.sizeText,
            unitPrice: nil,
            saleStartDate: nil,
            saleEndDate: nil,
            memberOnly: item.memberOnly,
            sourceText: "\(name) $\(price)",
            confidence: Self.confidence
        )
    }
}
