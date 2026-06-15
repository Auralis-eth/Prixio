# Prixio Agentic Architecture

A design sketch for reframing Prixio from a deterministic pipeline into an
agent-driven system: one agent takes the captured photo and does the
processing, and additional agents automate or advise on the other screens.

## The Reframe: From Pipeline to Agents

Today Prixio is a deterministic pipeline with FoundationModels reserved as a
narrow tie-breaker. To make it agentic, keep the deterministic parser and
pricing logic as **tools** (agents call them; they do not replace them) and add
reasoning agents that decide *what to do* with uncertain situations and *how to
advise* the user.

Three core agents, one per flow, plus a shared toolbelt:

| Agent | Screen | Job |
|---|---|---|
| **Capture Agent** | Scan | Take the photo → orchestrate OCR/parse → decide confidence, repair, escalation, and what to ask the user |
| **Compare Agent** | Compare | Turn saved `PriceEntry` history into ranked insight, explanations, and "is this a good price" judgments |
| **Planner Agent** | Shopping List | Build/optimize the trip, decide best store per item, decide when to nudge a rescan |

Guardrail: the existing product principle — *honesty under uncertainty* —
becomes the agents' constraint. Tools return structured evidence; the agent
reasons; but it must surface ambiguity rather than fabricate.

---

## Scan Screen — Capture Agent Tools

The agent that "takes the captured photo and does the processing." It already
has `OCRService`, `PriceParsingService`, and the parsing sub-resolvers — expose
those as tools plus a few new reasoning aids.

| # | Tool | What it does | Backed by |
|---|---|---|---|
| 1 | `runOcrAndParse(image)` | Returns the structured `OCRResult` (name, price, unit, qty, review state, decision report) | existing `OCRService` + `PriceParsingService` |
| 2 | `assessScanQuality(image)` | Pre-flight: blur, glare, crop, tag-fully-in-frame — lets the agent ask for a retake *before* OCR | `OCRService` quality scoring + new heuristics |
| 3 | `repairAmbiguousField(field, candidates, context)` | Targeted FM escalation for one weak field (e.g. competing prices, garbled name) instead of re-running everything | `PriceParsingAssistedExtraction` |
| 4 | `inferStoreContext(location, ocrHints)` | Suggests the store/chain so the agent can prefill and confirm | `StoreDetectionService` + `StoreCatalog` |
| 5 | `draftConfirmationPrompt(result)` | Generates the *minimal* human question — only asks about fields the review state flagged, not everything | new, reads `OCRReview` reasons |

---

## Compare Screen — Compare Agent Tools

The agent that provides advice on saved price history.

| # | Tool | What it does | Backed by |
|---|---|---|---|
| 1 | `getItemHistory(itemKey)` | All entries for a normalized item across stores/time | `ItemKeyNormalizer` + SwiftData |
| 2 | `rankStoresForItem(itemKey)` | Best-store ranking with staleness cues | `PriceInsightEngine` (best-store + `StalenessBucket`) |
| 3 | `judgePrice(itemKey, price)` | "Is this a good price?" vs the item's own history (cheap / typical / overpriced + how confident) | new, over `PriceInsightEngine` |
| 4 | `explainComparison(itemKey)` | Natural-language *why* — e.g. "Costco is cheaper but your data is 6 weeks old" | reasoning over tools 1–3 |
| 5 | `flagStaleOrThinData(itemKey)` | Surfaces where the conclusion is weak and a rescan would help — routes into Scan | `StalenessBucket` + entry counts |

---

## Shopping List Screen — Planner Agent Tools

The agent that automates trip planning and rescan nudges.

| # | Tool | What it does | Backed by |
|---|---|---|---|
| 1 | `getListWithBestStores(listId)` | Active rows each annotated with best store + price + freshness | `ShoppingListRepository` + `PriceInsightEngine` |
| 2 | `optimizeTrip(listId, location)` | Recommend the winning store(s), trading off price vs distance vs coverage | `TripRecommendation` + `PriceInsightEngine` + `DistanceFormatter` |
| 3 | `proposeListAdditions(listId)` | Suggest forgotten/recurring items from history ("you usually buy milk") | history over `ItemKeyNormalizer` |
| 4 | `decideScanNudge(item)` | Decide whether checking off a stale/missing-price item should trigger `ScanNudgeSheet`, and prefill it | `ScanNudgeSheet` + staleness logic |
| 5 | `splitTripAcrossStores(listId)` | When no single store wins, propose a 2-stop plan and quantify the savings vs the extra trip | `PriceInsightEngine` trip aggregation |

---

## Design Notes

- **Tools wrap existing deterministic code.** `PriceInsightEngine` and
  `ItemKeyNormalizer` stay the single source of pricing truth — agents *call*
  them, so Compare and Planner do not reinvent price logic (matches the existing
  gotcha about not duplicating best-price state).
- **Each tool returns evidence, not just an answer** (counts, dates, staleness
  bucket, confidence) so the agent can be honest about weak conclusions.
- **A shared `routeToScan(item, store)` tool** (over `AppNavigationModel`) lets
  *any* agent hand off to the Capture Agent when data is missing — this is what
  stitches the three agents into one loop.
- A 4th lightweight **Settings agent** is optional (units, distance prefs, data
  hygiene like "merge duplicate stores"), if you want coverage of that screen.
