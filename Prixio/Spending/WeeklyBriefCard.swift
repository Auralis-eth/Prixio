import SwiftData
import SwiftUI

/// The weekly household brief as a Spending-tab section. Self-contained: queries
/// its own inputs and renders `HouseholdBrief.facts` verbatim, so the card and the
/// weekly notification always tell the same story. Hidden entirely when the week
/// has nothing to say. Composing the brief walks every entry and receipt, far too
/// heavy for a render pass, so it runs only when the inputs fingerprint changes —
/// never inside `body`.
struct WeeklyBriefCard: View {
    @Query private var entries: [PriceEntry]
    @Query private var receipts: [ReceiptCapture]
    @Query private var flyerRecords: [FlyerPriceRecord]
    @Query private var restockRules: [RestockRule]
    @Query private var lists: [ShoppingList]

    @State private var brief: HouseholdBrief?

    var body: some View {
        Group {
            if let brief, !brief.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(brief.facts.enumerated()), id: \.offset) { index, fact in
                            Text(fact)
                                .font(index == 0 ? .subheadline.weight(.medium) : .subheadline)
                                .foregroundStyle(index == 0 ? .primary : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("This Week")
                }
            }
        }
        .onChange(of: inputsFingerprint, initial: true) { _, _ in
            brief = WeeklyBriefEngine.compose(
                entries: entries,
                receipts: receipts,
                flyerRecords: flyerRecords,
                restockRules: restockRules,
                listItemKeys: activeListItemKeys
            )
        }
    }

    private var activeListItemKeys: [String] {
        lists.filter { !$0.isArchived }.flatMap(\.items).map(\.itemKey)
    }

    /// Hash of every brief-relevant field, so `onChange` fires on in-place edits
    /// (a receipt flipping to reviewed, a corrected price, a rule dismissal) as
    /// well as inserts — same reasoning as
    /// `ShoppingListRootView.restockInputsFingerprint`.
    private var inputsFingerprint: Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.id)
            hasher.combine(entry.capturedAt)
            hasher.combine(entry.priceValue)
        }
        for receipt in receipts {
            hasher.combine(receipt.id)
            hasher.combine(receipt.reviewStateRaw)
            hasher.combine(receipt.total)
            hasher.combine(receipt.lineItems.count)
        }
        for record in flyerRecords {
            hasher.combine(record.id)
        }
        for rule in restockRules {
            hasher.combine(rule.itemKey)
            hasher.combine(rule.statusRaw)
            hasher.combine(rule.overrideIntervalDays)
        }
        for key in activeListItemKeys {
            hasher.combine(key)
        }
        return hasher.finalize()
    }
}
