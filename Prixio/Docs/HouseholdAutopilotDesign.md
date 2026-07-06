# Household Autopilot — Design

*Drafted 2026-07-05. Status: Phases 1–4 done — `ConsumptionCadenceEngine` +
`RestockRule` (1); "Probably running low" shopping-list section with durable
dismissal, deduped against the older capture-rhythm "Suggested" section (2);
`BuyAheadAdvisor` + "Buy ahead" section (3); `WeeklyBriefEngine`, "This Week" card
on the Spending tab, and a quiet weekly notification via *provisional* authorization
scheduled at each launch (4 — 37 autopilot tests passing). Phase 4 deliberately ships
without BGAppRefreshTask: the pending notification's content is "as of the last app
run"; adding the background-refresh capability (Info.plist identifier + Background
Modes) is the known follow-up. Phase 5 (household sharing) remains.*

## Positioning

Wealthy households pay house managers and concierge services to do the "Prixio job":
know what the household consumes, keep it stocked without being asked, don't let
vendors overcharge, don't waste the principal's time. The premium version of Prixio is
not a savings app — it is a **digital house manager**. The pitch shifts from
"save $4 on butter" to "your household runs itself and never overpays."

Three features carry that identity, in dependency order:

1. **Household Stock Autopilot** — infer per-item consumption cadence from receipt
   history, auto-draft the shopping list, and use the flyer pipeline as a *timing*
   engine ("you'll need detergent in ~10 days; it's 40% off at RCSS until Thursday —
   buy early").
2. **Weekly household briefing** — a once-a-week, on-device-generated summary:
   spend vs. normal, overpaid items, upcoming lows, probably-running-low list.
3. **Multi-person household mode** — shared shopping list + shared price memory +
   "partner already bought this" dedup. Also the organic growth loop.

## Grounding findings (from the codebase)

- **Consumption is evidenced by receipts, not `PriceEntry`.** `ReceiptCapture` is
  deliberately "a basket, not a price"; lines are only promoted to `PriceEntry`
  selectively (`ReceiptLineItem.promotedPriceEntryId`). `PriceEntry` also contains
  shelf-price scans, which are *observations*, not purchases. Cadence inference must
  therefore read reviewed `ReceiptCapture`s + `ReceiptLineItem`s. Receipts already
  carry `purchaseDate` (distinct from scan date), per-line `quantityValue`, and a
  `reviewState` gate — no schema change needed for v1.
- **Grouping must use exact `itemNameNormalized`, not `ItemKeyNormalizer.matches`.**
  The rollup rule is directional (generic query → specific entry) and would merge
  "Almond Milk" and "2% Milk" clocks, which are independent. Head-noun machinery
  re-enters at deal-matching time, where it already lives.
- **The suggested/confirmed/dismissed lifecycle already exists**
  (`RecurringRuleStatus`, `RecurringExpenseRule`): suggestions are never auto-applied
  and dismissals suppress. `RestockRule` clones this shape.
- **Deal timing ingredients all exist**: `FlyerPriceRecord.saleStartDate/saleEndDate`,
  `PriceInsightEngine.classifyAnomaly` (usual-band vocabulary), `FlyerDealMatcher`.
- **The brief's honesty contract exists**: `InsightEvidence`/`InsightExplainer` —
  engines compute facts, the on-device model only phrases them, and every digit-run
  in the prose must literally appear in a fact.
- **SwiftData cannot do multi-user sharing.** `ModelConfiguration.cloudKitDatabase`
  is single-user private-database sync only; `CKShare` collaboration is exposed only
  through Core Data (`NSPersistentCloudKitContainer` zone sharing) or raw CloudKit.
  Household mode must share a narrow subset via CloudKit directly rather than
  migrating persistence.

## 1. `ConsumptionCadenceEngine` (Core/Derived)

Pure `enum` of static functions in the `PriceInsightEngine` house style: models in,
value types out, `now` injected, conservative minimums.

Algorithm:

1. Filter to `reviewState == .reviewed` receipts; event date =
   `purchaseDate ?? capturedAt`. Skip lines with `needsReview` or no
   `itemNameNormalized`.
2. Group by exact `itemNameNormalized`.
3. Collapse to purchase events: one event per (key, calendar day), summing
   `quantityValue` (nil → 1). Two milk lines on one receipt = one event.
4. Intervals between consecutive events: **median** + **MAD** (median absolute
   deviation), so one vacation gap or stock-up doesn't wreck the estimate — same
   robustness instinct as the median-based usual band in `computeItemHistory`.
5. Confidence gate — never surface a guess:
   - `high`: ≥ 5 events and MAD/median ≤ 0.35
   - `medium`: ≥ 3 events and MAD/median ≤ 0.6
   - otherwise: no cadence at all.
6. Quantity scaling: predicted interval = median interval × (last event quantity ÷
   median event quantity), clamped to 0.5…3× so one odd receipt can't push the
   prediction months out.
7. `predictedRunOutDate = lastPurchase + predictedInterval`. Urgency:
   `probablyOut` (past a 2-day grace), `dueSoon` (within 3 days), `stocked`.
8. Lapse guard: overdue by more than 3 median intervals → the household has probably
   stopped buying it (brand switch, seasonal); suppress from suggestions.

**`RestockRule`** (`@Model`, Core/Models): per-item-key user decision, reusing
`RecurringRuleStatus`. Dismissed = permanently suppress ("we don't buy this on a
schedule"). Confirmed may carry `overrideIntervalDays` replacing the inferred one.

**Surfacing (Phase 2)**: a "Probably running low" section pinned atop the shopping
list — name + why ("every ~6 days · last bought 8 days ago") + one-tap add. The
insert creates a `ShoppingListItem` with the same `itemKey`, which immediately flows
through `FlyerDealMatcher`, `computeBasketEstimate`, and trip-winner logic with zero
new plumbing. The autopilot feeds the existing procurement machine.

## 2. Buy-ahead timing (`RestockTimingAdvisor`, Phase 3)

Pure composition of three existing pieces. Surface an advisory only when **all** hold:

- run-out predicted within a ~14-day lookahead;
- the deal price classifies `.belowUsual` or better vs. the item's history median
  (`PriceInsightEngine.classifyAnomaly`);
- `FlyerPriceRecord.saleEndDate` expires **before** the predicted run-out — the
  window closes before the household would naturally shop. That condition is what
  turns a coupon into procurement strategy.

```
BuyAheadAdvisory { cadence, deal, anomaly, dealEndsBeforeRunOut }
```

## 3. `WeeklyBriefEngine` (Phase 4)

```
HouseholdBrief {
    weekSpend            // SpendingInsightEngine receipt totals, this week
    spendVsUsual         // vs trailing 8-week median
    overpaidItems        // this week's entries classifying .aboveUsual or worse
    restockSuggestions   // top 3 by urgency
    buyAheadAdvisories   // top 2 by savings
    evidence             // InsightEvidence facts for the explainer
    fingerprint          // "did anything change" identity, as InsightEvidence does
}
```

Rendering: deterministic card (each fact is a UI-ready sentence) + optional one-line
model narration over it, guarded by the existing digit-run validator. Delivery:
`BGAppRefreshTask` computes the brief and schedules a `UNCalendarNotificationTrigger`
local notification (e.g. Sunday 5pm) whose body uses only deterministic facts — no
model call at notification time, fully on-device. The card also lives on `MainView`
so the notification and the app agree.

## 4. Household mode (Phase 5)

Constraint: no SwiftData `CKShare`. Design around it:

- Share a narrow, purpose-built subset via **raw CloudKit zone sharing**:
  `ReceiptCapture` summaries (store, date, line keys/quantities — enough for cadence
  and dedup), `ShoppingList`/`ShoppingListItem`, promoted `PriceEntry`s. Images,
  expenses, and income stay private — the household shares the *procurement* layer,
  not the finances.
- Incoming shared records land as local SwiftData rows tagged with a
  `householdMemberID`; every engine gets household-wide data for free (pure functions
  over arrays — they don't care who scanned the receipt).
- "Partner already bought it" dedup: a synced receipt line whose `itemNameNormalized`
  matches an open `ShoppingListItem.itemKey` (rollup via `ItemKeyNormalizer.matches`
  is correct *here*: a "milk" list item is satisfied by "2% Milk") within N days →
  confirm-to-check-off toast, never auto-done.

Largest lift and only piece with real platform risk (sharing UI, acceptance flow,
conflicts, zone limits). Phases 1–3 work single-user and improve when this lands.

## Phasing

| Phase | Deliverable | Size |
|---|---|---|
| 1 | `ConsumptionCadenceEngine` + `RestockRule` + Swift Testing suite | Small — pure logic |
| 2 | Restock section in shopping list, one-tap add, dismiss lifecycle | Small–medium |
| 3 | `RestockTimingAdvisor` + advisory row in Check Flyers / list | Small — composition |
| 4 | `WeeklyBriefEngine`, brief card, BGTask + local notification | Medium |
| 5 | Household sharing via CloudKit zone share + dedup toast | Large, separate track |

Open risk for Phase 1: whether real receipt-scanning frequency yields ≥ 3 reviewed
events per item fast enough. Validate against real usage before building UI; if too
slow, `ShoppingListItem.doneAt` (checked-off = bought) is a second, weaker purchase
signal that could pad event counts.

## Outstanding follow-ups (from Phases 1–4)

1. **BGAppRefreshTask for fresh notification content.** Today `MainView`'s launch
   task composes the brief and schedules the Sunday-5pm notification, so its content
   is "as of the last app run". To freshen it in the background:
   - Add the *Background Modes* capability (Background fetch) to the Prixio target
     and a `BGTaskSchedulerPermittedIdentifiers` Info.plist entry (e.g.
     `com.prixio.weekly-brief-refresh`).
   - Register a `BGAppRefreshTask` at launch; the handler re-runs the same
     `WeeklyBriefEngine.compose` + `WeeklyBriefNotifier.scheduleNextBrief` path that
     `MainView.scheduleWeeklyBrief()` uses, then re-submits the next refresh request
     (aim for Saturday night/Sunday morning).
   - Deferred deliberately: capability + Info.plist edits are project-file changes
     that deserve their own review.

2. **`InsightExplainer` narration over the "This Week" card.** The card renders
   `HouseholdBrief.facts` deterministically. An optional model-written one-liner on
   top should copy the `ShoppingListViewModel` pattern exactly: build
   `InsightEvidence(facts: brief.facts)`, gate on `facts.count >= 2`, cache by
   `brief.fingerprint` so unchanged evidence never re-generates, clear the prose the
   moment the fingerprint changes, and rely on the explainer's digit-run validator
   to reject any invented number. Notification body stays deterministic regardless.

3. **Confirm-with-interval-override UI for `RestockRule`.** Model and engine are
   already wired: a `confirmed` rule with `overrideIntervalDays` replaces the
   inferred interval (and lifts confidence to `high`) in
   `ConsumptionCadenceEngine.restockSuggestions`; `RestockSuggestionsTests` covers
   it. Missing is the surface: tapping a "Probably running low" row should open a
   small sheet showing the inferred rhythm ("about every 7 days from 6 purchases")
   with a stepper to correct the interval; saving writes/upserts the confirmed rule
   via `RestockRuleRepository` (add a `confirm(itemKey:displayName:overrideIntervalDays:)`
   sibling of `dismiss`).
