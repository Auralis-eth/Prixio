import Foundation
import FoundationModels

/// The deterministic facts a natural-language insight may draw on. Built entirely
/// by the pricing engines — the model only turns facts into prose, never computes.
struct InsightEvidence: Equatable, Sendable {
    /// Short declarative facts, e.g. "Costco has the best price for 4 of 6 items."
    let facts: [String]

    /// Identity for "did anything change" checks, so unchanged evidence never
    /// re-generates.
    var fingerprint: String { facts.joined(separator: "|") }

    var isEmpty: Bool { facts.isEmpty }
}

/// Turns deterministic insight evidence into one short natural-language sentence.
/// `nil` means "no explanation" — the deterministic UI strings simply stand alone,
/// so conformers never need to fail loudly.
protocol InsightExplaining: Sendable {
    func explain(_ evidence: InsightEvidence) async -> String?
}

/// Availability-gated explanation writing with the on-device model. The reply is
/// additive UI copy layered *over* the deterministic labels (which always render),
/// and it is validated so every number in the prose appears in the facts — the
/// model can phrase, but it cannot introduce a figure the engines didn't compute.
struct InsightExplainer: InsightExplaining {
    /// Explanations are one glanceable line; anything longer is rejected.
    static let maxLength = 220

    func explain(_ evidence: InsightEvidence) async -> String? {
        guard !evidence.isEmpty, OnDeviceModelGate.allowsGeneration else { return nil }

        let session = LanguageModelSession(instructions: {
            """
            You write one short, plain sentence (two at most) that explains a \
            grocery price insight to the shopper, using only the facts given. \
            Lead with what matters most to their decision, then the strongest \
            reason, and mention a data-freshness caveat when one exists. Never \
            invent numbers, store names, or savings, and never contradict a \
            fact. No greetings, no emoji, no bullet points.
            """
        })
        let listing = evidence.facts.map { "- \($0)" }.joined(separator: "\n")
        guard let reply = try? await session.respond(
            to: "Explain this to the shopper:\n\(listing)"
        ).content else {
            return nil
        }
        return Self.validated(reply, against: evidence)
    }

    // MARK: - Deterministic helpers (unit-tested)

    /// Collapses whitespace and enforces the honesty guards: a bounded length, and
    /// every digit-run in the prose must literally appear in some fact — a made-up
    /// price, count, or saving rejects the whole explanation (the deterministic
    /// labels still render, so rejection costs nothing).
    static func validated(_ reply: String, against evidence: InsightEvidence) -> String? {
        let collapsed = reply
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty, collapsed.count <= maxLength else { return nil }

        let allowedNumbers = Set(evidence.facts.flatMap { numberRuns(in: $0) })
        let usedNumbers = Set(numberRuns(in: collapsed))
        guard usedNumbers.isSubset(of: allowedNumbers) else { return nil }
        return collapsed
    }

    /// Every maximal digit run in a string ("$12.99 for 3" → ["12", "99", "3"]).
    /// Runs, not parsed values, so "12.99" can't be reassembled from unrelated facts.
    static func numberRuns(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber }).map(String.init)
    }
}

// MARK: - Evidence builders

extension InsightEvidence {
    /// The deterministic facts behind an item's price-history read (the Compare
    /// item detail surface). Empty until the usual band exists — below the
    /// observation minimum the deterministic copy already says everything.
    static func itemHistory(_ history: ItemPriceHistory) -> InsightEvidence {
        guard history.hasUsualBand else { return InsightEvidence(facts: []) }
        let display = CurrencyFormatter.shared.display(_:)

        var facts: [String] = []
        let latest = display(history.latest.price)
        switch history.anomaly {
        case .likelySale:
            facts.append("The latest price, \(latest), is well below the usual range — likely a sale.")
        case .belowUsual:
            facts.append("The latest price, \(latest), is below the usual range.")
        case .nearUsual:
            facts.append("The latest price, \(latest), is within the usual range.")
        case .aboveUsual:
            facts.append("The latest price, \(latest), is above the usual range.")
        case .unusuallyHigh:
            facts.append("The latest price, \(latest), is well above the usual range.")
        case .insufficientData:
            break
        }
        facts.append("The usual price is \(display(history.usualLow)) to \(display(history.usualHigh)), from \(history.observationCount) captured prices.")
        facts.append("The lowest price ever captured was \(display(history.lowest.price)).")
        if history.freshness.isStale {
            facts.append("The newest captured price is old; prices may have changed since.")
        }
        return InsightEvidence(facts: facts)
    }
}
