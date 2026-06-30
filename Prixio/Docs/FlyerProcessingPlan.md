# Flyer Processing Plan

## Purpose

This document tracks the feature direction for Prixio flyer processing: a user-triggered flow that checks online flyers and retailer websites for current prices, extracts structured product data, and folds those prices into Prixio's comparison and shopping intelligence.

This should not run automatically in the background for the first version. The intended product shape is a button or explicit action somewhere in the app that lets a user ask Prixio to refresh available flyer and online prices when they want it.

## Product Thesis

Prixio currently learns prices from user captures: shelf tags, receipts, and saved entries. Flyer processing adds a second kind of memory: public merchant data.

The goal is to turn messy web material into structured grocery intelligence:

- retailer flyers
- sale pages
- product listing pages
- PDF flyers
- flyer images
- online grocery prices
- in-store pricing signals when merchants expose them

The output should become a centralized product repository across merchants and geographies, not just a pile of screenshots. Prixio should understand that the same or equivalent product may appear under different merchant names, flyer layouts, package sizes, and sale labels.

## Intended User Flow

### First Version

Status: Planned

The user manually triggers flyer processing.

Possible entry points:

- a button in Compare for "Check flyers"
- a button in Shopping List for "Find current deals"
- a store-specific action from a merchant detail surface
- a settings or maintenance action for refreshing known public prices

The first version should prefer a clear manual action over automation because:

- web scraping behavior needs explicit user trust and visibility
- retailer pages and flyers can be slow or unreliable
- parsing may need review before prices are treated as trusted
- background refresh creates privacy, battery, and network questions too early

### Later Versions

Status: Deferred

Possible expansions after the manual flow is reliable:

- scheduled daily or weekly refreshes
- watchlist-specific refreshes
- "new low" alerts
- sale-ending reminders
- household-specific deal recommendations
- competitor price checks for selected items

## Core Capability

The system should use agent-style ingestion to search, fetch, scrape, classify, extract, normalize, and store public flyer data.

Examples of relevant agent jobs:

- search known retailer websites for active flyers by geography
- open flyer pages and product listing pages
- fetch PDFs and images when available
- run OCR or computer vision over flyer images
- use NLP to identify product names, sizes, brands, prices, loyalty/member conditions, and sale windows
- normalize package quantity and unit price
- map retailer locations or regions to `StoreChain` and `StoreLocation`
- deduplicate equivalent products across merchants
- produce reviewable structured candidates before saving trusted records

This is similar to competitor-pricing workflows that run daily or weekly, but Prixio should begin with an explicit user button instead of an unattended process.

## Data We Need To Extract

Minimum useful fields:

- merchant name
- store chain match
- geography or region
- source URL or source file reference
- product name as advertised
- normalized item key
- brand when available
- package size
- package quantity
- unit type
- advertised price
- unit price when derivable
- sale or flyer start date
- sale or flyer end date
- loyalty/member-only condition
- online versus in-store signal
- confidence score
- extraction timestamp

Nice-to-have fields:

- product image URL or crop
- promotion label, such as BOGO, multi-buy, member price, or digital coupon
- regular price when shown
- limit quantity
- store pickup/delivery availability
- postal-code-specific availability
- source text snippets for review

## Proposed Architecture

### 1. Manual Trigger Surface

A SwiftUI button starts the flow and shows progress. The first version should keep user expectations modest: "checking flyers" means collecting candidates, not guaranteeing every retailer is covered.

Potential app surfaces:

- Shopping List: strongest fit because users already want current deal discovery for items they plan to buy
- Compare: useful for item-specific price checks
- Settings: useful for developer/admin refreshes, but weaker as a user-facing workflow

Recommendation: start in Shopping List with a focused "Check Flyers" action because the shopping list gives the agent a bounded set of products to search for.

### 2. Flyer Ingestion Coordinator

A coordinator owns the user-triggered job lifecycle:

- receives target geography and optional shopping-list item scope
- chooses retailer sources
- dispatches search/scrape/extract work
- merges results
- returns candidate records for review or save

This should stay separate from `ScanViewModel`. Scanner capture is local evidence. Flyer processing is remote evidence.

### 3. Source Connectors

Start with explicit connectors for known merchants instead of pretending the entire web is uniform.

Each connector should describe:

- retailer identity
- supported regions
- flyer URL discovery rules
- page/PDF/image extraction strategy
- rate limits and failure behavior
- whether prices are online, in-store, or ambiguous

A generic web fallback can come later, but retailer-specific connectors will be easier to test and safer to reason about.

#### Initial Hard-Coded Alberta Banner Set

Status: Planned

Prixio's first flyer-processing implementation should hard-code the Alberta grocery banners below instead of starting with broad web discovery. This gives the system a bounded source list, predictable debugging, and a clearer user promise: Prixio is checking the most relevant Alberta grocery banners first.

| Rank | Grocery banner | Parent / type | Why it matters in Alberta |
| --- | --- | --- | --- |
| 1 | Real Canadian Superstore | Loblaw | Big-format, price-focused, very common in Calgary and Edmonton. |
| 2 | Safeway | Sobeys / Empire | One of Alberta's strongest full-service grocery banners; Safeway's Canadian head office is in Calgary. |
| 3 | Sobeys | Sobeys / Empire | Major full-service national grocery chain; Sobeys owns banners including Safeway, FreshCo, IGA West, Foodland, and Thrifty Foods. |
| 4 | Costco | Costco Wholesale | High grocery volume, especially for families; Costco lists 18 Alberta warehouses. |
| 5 | Walmart Supercentre | Walmart Canada | Major grocery competitor in Alberta, especially for pantry, household, and low-price basics. |
| 6 | No Frills | Loblaw | Key discount banner with a large Alberta footprint. |
| 7 | Save-On-Foods | Pattison Food Group | Strong Western Canada chain; Calgary alone has 10 locations listed by Save-On-Foods. |
| 8 | FreshCo / Chalo! FreshCo | Sobeys / Empire | Discount grocery banner expanding in Alberta, with locations including Calgary, Edmonton, Fort McMurray, Okotoks, and others. |
| 9 | Co-op / Calgary Co-op | Co-operative | Very important locally, especially Calgary and surrounding towns; Calgary Co-op lists locations in Calgary, Airdrie, Cochrane, High River, Okotoks, and Strathmore. |
| 10 | Freson Bros. | Alberta-owned independent | Probably Alberta's most important local independent grocery brand; it describes itself as Alberta grown, Alberta owned, and family operated since 1955. |

Implementation notes:

- Treat each row as a source connector target, even when multiple banners share the same parent.
- Keep banner identity separate from parent identity because flyer URLs, loyalty conditions, and pricing rules can differ by banner.
- Store supported geography as Alberta first, with optional city/postal-code narrowing for flyer selection.
- Keep rank as an implementation priority, not a user-facing quality claim.
- If a banner has no accessible public flyer source, keep the connector stubbed with an explicit unsupported reason instead of silently skipping it.

### 4. Extraction Pipeline

The extraction pipeline should handle three source shapes:

- HTML product listings
- PDF flyers
- image-based flyers

Likely stages:

1. acquire source material
2. classify source type
3. extract text and visual regions
4. identify product blocks
5. extract price, unit, package, brand, and promo terms
6. normalize item identity and unit price
7. attach source provenance and confidence
8. surface candidates for review or persistence

Prixio already has useful pieces for parts of this: item key normalization, unit parsing, price insight logic, and AI-assisted extraction patterns. The flyer pipeline should reuse those where appropriate without mixing web ingestion into the camera scanner path.

### 5. Central Product Repository

Flyer data should not simply become ordinary user-captured `PriceEntry` records without provenance.

Open model question:

- Option A: add source/provenance fields to `PriceEntry`
- Option B: create a separate `MarketPriceEntry` or `FlyerPriceEntry` model
- Option C: store raw flyer candidates separately, then promote reviewed entries into `PriceEntry`

Initial recommendation: create separate flyer/market candidate storage, then promote trusted prices into comparison surfaces with clear source labels. This avoids contaminating user-captured history with scraped data whose availability and geography may be less certain.

## Alerts And Sale Detection

Flyer processing should eventually power sale detection and alerts.

Possible alert types:

- item on shopping list is currently on sale
- item reached a new known low price
- nearby merchant has a better current price
- sale ends soon
- multi-buy offer beats current unit-price history
- online price differs from in-store flyer price

Guardrails:

- alerts should explain source and confidence
- member-only and digital-coupon prices must be labeled clearly
- price comparisons should use normalized unit price when possible
- geography should be explicit; a flyer from the wrong region is worse than no flyer

## Trust, Review, And Provenance

Every extracted flyer price needs provenance.

Minimum provenance contract:

- source merchant
- source URL or document identifier
- date fetched
- flyer validity period when known
- geography or postal-code context
- extraction confidence
- extracted text or visual crop for review

The UI should avoid presenting scraped flyer data as equal to an in-person scan unless the provenance is strong. Suggested labels:

- "Flyer price"
- "Online price"
- "Member price"
- "Needs review"
- "Region unknown"

## Technical Risks

### Retailer Variability

Retailer sites change frequently. Flyer vendors, embedded viewers, PDFs, and lazy-loaded images will vary by merchant.

Mitigation:

- start with a few supported merchants
- keep source connectors isolated
- preserve raw source artifacts for debugging when legally and practically appropriate
- test extraction with real archived samples

### Geography Ambiguity

A price can depend on province, city, postal code, store, loyalty account, or fulfillment mode.

Mitigation:

- always attach geography context
- prefer user-selected postal code or nearby store context for search
- show uncertainty instead of overclaiming current availability

### Legal And Terms Constraints

Scraping and flyer ingestion may be restricted by site terms, robots rules, or anti-bot controls.

Mitigation:

- review target sources before implementation
- prefer public pages, retailer-provided feeds, APIs, PDFs, or partner-compatible data sources
- avoid credentialed scraping in v1
- keep request rates conservative

### Extraction Confidence

Flyer images can combine product photos, promo text, multi-buy pricing, member pricing, and tiny legal conditions.

Mitigation:

- keep candidates reviewable
- store source snippets/crops
- avoid automatic alerts from low-confidence entries
- use deterministic normalization after model extraction

## MVP Scope

A useful first implementation is now split into milestones:

1. Add a manual "Check Flyers" action from the Flyers POC tab. Status: implemented.
2. Hard-code the Alberta banner set listed above as the initial source catalog. Status: implemented.
3. Implement official source connectors in rank order, with URLSession checks and Brave Search fallback limited to official domains. Status: implemented for source discovery.
4. Fetch active flyer pages, product pages, images, or PDFs depending on each connector's source shape. Status: implemented. Content acquisition became its own milestone (`FlyerContentAcquisitionPlan.md`) and ships a per-destination router (`FlyerContentAcquisitionRouter`): static HTML/JSON/PDF/image are processed in-app (`StaticFlyerContentAcquirer`), and only JS-rendered (`dynamicHTML`) sources use an on-device rendered fetch (`WebPageFlyerContentAcquirer`). Both produce flyer text + price-token signals. Per the 2026-06-25 audit all ten banners are currently `dynamicHTML`, so they route to the rendered path today; the static path is ready for any destination that returns processable content.
5. Extract product-price candidates using OCR/NLP/computer vision. Status: implemented (deterministic v1). `FlyerPriceExtractor` turns acquired content into structured `FlyerPriceCandidate`s. Captured flyer JSON (`.endpointJSON`) is mined by a generic recursive walker that finds every object carrying both a name-ish and a price-ish field — handling Flipp/Salesforce/Walmart schemas without hardcoding each — capturing name, brand, sale + regular price, package size, sale dates, and member-only condition (high confidence). Harvested text (`.renderedHTML`/`.imageOCR`/`.staticHTML`) is mined by pairing `$X.XX` tokens with surrounding product text (lower confidence). The POC tab gains an "Extract Price Candidates" phase + per-banner candidate rows; a `[FlyerExtraction]` log trail correlates with discovery/acquisition. 12 unit tests over Flipp/Salesforce/text fixtures. Deferred to later: model-assisted enrichment of the messy text/OCR path, unit-price derivation, and multi-buy parsing.
6. Match candidates against current shopping-list item keys. Status: implemented (engine + POC demo). `FlyerDealMatcher` matches extracted candidates to shopping-list items via `ItemKeyNormalizer.matches(queryKey:entryKey:)` — the same generic-query→specific-product, head-noun-anchored rule `PriceInsightEngine` uses (so "milk" rolls up "Almond Milk"; "daisy sour cream" won't pull in generic "sour cream"). Output is per item, deals sorted best-price-first then confidence then banner rank — naturally a store-to-store comparison. The POC demonstrates it against a fixed sample grocery list (real `ShoppingListItem` wiring lands with the review/save surfaces). Known limitation (shared normalizer, tracked for the enrichment pass): decimal pack-sizes ("1.89 L") and trailing descriptors ("Eggs One Dozen") can displace the head noun and miss a roll-up. 6 matcher unit tests.
7. Show a review list with source, confidence, sale dates, geography, and unit price. Status: implemented. Matching now runs against the user's real default shopping list (active, not-done items) via `ShoppingListRepository`, falling back to the built-in sample list only when the list is empty (POC still demonstrates). The review rows show per-deal provenance — regular price, package size, member-only, sale-end date, and confidence — and label which list was used.
8. Let the user save selected flyer prices or use them for list estimates. Status: implemented. Reviewed deals save into a dedicated `FlyerPriceRecord` SwiftData store (the plan's Option C — separate from user-captured `PriceEntry`) with full provenance (banner, source URL, fetched date, sale window, store context/geography, confidence, member flag, matched list-item key). `FlyerPriceRecordRepository.save` is idempotent on `bannerID|itemKey|price`; the review UI shows a per-deal save/saved (+ / ✓) control backed by the saved-key set. Promotion of saved market prices into Compare/Shopping estimates (with clear "Flyer price" labels) remains future work.

Do not include in MVP:

- automatic background refresh
- broad web search over every grocery retailer
- push notifications
- account-authenticated retailer scraping
- unreviewed writes into long-term price history

## Open Questions

- Should the initial geography be all of Alberta, or should v1 narrow to Calgary/Edmonton postal-code contexts first?
- For each hard-coded banner, what is the preferred public source: retailer flyer page, product listing page, PDF, image viewer, or third-party flyer provider?
- Should flyer data live in SwiftData only, or should remote/server storage exist later?
- Should market prices be separate from user-captured prices forever, or only until reviewed?
- What is the right UI label for scraped flyer confidence?
- How should stale flyer prices disappear from Compare and Shopping List estimates?
- Do we need source artifact storage for debugging and user trust?
- What legal/terms review is required before shipping retailer-specific connectors?

## Tracking Log

### 2026-06-30 - Co-op cracked: direct Flipp flyerkit fetch

The request diagnostics revealed the answer. Every Flipp banner loads items from `dam.flippenterprise.net/flyerkit/publication/<id>/products` with a shared public `access_token` (`b349aa77…`, in every banner's `aq.flippenterprise.net/a/<token>/lib/…` URL) and a per-merchant slug. **Co-op's widget loads only `flyerkit/merchant/coopfood` and never selects a publication**, so it never fetches `/products` — hence 0 candidates.

Fix: `FlippFlyerKitClient` fetches the flyerkit API directly — `publications/<merchant>` → pick the publication whose validity window contains now → `publication/<id>/products` → products JSON (fed to the same extractor). Wired as a deterministic fallback in the rendered acquirer for any Flipp banner with a known merchant slug (`flippMerchant` on `FlyerStorePreparation`) when the capture comes up short of the price threshold. Slugs from diagnostics: Co-op `coopfood`, Sobeys `sobeys`, Walmart `walmartcanada`, Save-On `saveonfoods`, FreshCo `freshco`, Safeway `safeway` (Freson's slug still unknown). This also gives every Flipp banner a reliable, render-free path (capture timing was flaky run-to-run). 6 flyerkit-client tests (URL building, publication selection incl. wrapped/fallback/none, products fetch → extractor); 23 acquisition tests green.

Expected next run: Co-op `phase=flyerkit merchant=coopfood ... prices=N` → candidates. (If the public token/postal is rejected, the `flyerkit-error` line will say so.)

### 2026-06-30 - Co-op items-fetch: request diagnostics + flyer-open click

Working the real Co-op gap (its Flipp **items** fetch never lands in the capture under food.crs). Two changes:
- **Request-URL diagnostics:** the interceptor now `note()`s every data-API-looking request URL (flipp/wishabi/api/graphql/item/product/publication/merchant/flyer/circular) on both fetch and XHR — independent of response shape — collected in `FlyerNetworkCapture.noticedURLs` and logged once per banner as `phase=rendered-requests`. The next device run will show whether Co-op makes an items/backflipp request at all and at what endpoint, which determines the targeted fix (drive a click vs. seed a key vs. hit the endpoint directly).
- **Flyer-open click (general):** Co-op's `/more/foodflyers` rendered only ~665 chars — a flyer *list* page whose Flipp widget never advanced to the item view. The post-load click driver now also matches flyer-open verbs ("view/see/open/shop flyer", "weekly flyer") so it clicks through to the item-level flyer that triggers the items fetch. General to any inline-Flipp banner; low risk (only clicks clearly flyer/store actions). 17 acquisition tests green.

Expected next run: either Co-op opens its flyer and the items JSON is captured (→ candidates), or `phase=rendered-requests` reveals the exact endpoint to target.

### 2026-06-30 - Co-op diagnosed: capture was JavaScript, not data (JSON-only gate)

The zero-candidate diagnostic paid off. Co-op's sample was `(self.webpackChunkFlipp=…)` — **JavaScript**, not flyer data. food.crs is Flipp-powered and the capture was grabbing Flipp's minified **webpack JS chunks** (their source text contains "flipp"/"price"/"product", so they passed `looksFlyer`); Co-op's real item payload was never captured, and the "prices=4" were `$`/`"price"` tokens inside code. So Co-op's 0 candidates was **correct**.

Fix: the network capture now keeps **JSON only** (body's first non-whitespace char is `{`/`[`) — added to both the injected interceptor (`looksJSON`) and a testable Swift guard (`FlyerNetworkCapture.isJSONPayload`). This stops JS/HTML from being mistaken for flyer data anywhere (no more misleading price counts, and the 800 KB budget is reserved for real item fetches). 1 new test (keeps JSON incl. BOM/whitespace, rejects webpack/`!function`/HTML); 17 acquisition tests green.

Remaining Co-op gap (acquisition, not extraction/data-quality): its Flipp **items** fetch is never hooked under food.crs — it loads items via a path our fetch/XHR interceptor doesn't see in budget. That needs per-banner network investigation, logged as future work; the other 6 banners are unaffected (run #N still: Sobeys 146, FreshCo 179, Walmart 121, Save-On 6, RCSS/No Frills 2 — 456 candidates).

### 2026-06-30 - Word-quantity normalizer + Co-op extraction hardening

- **Word-quantity gap closed:** `ItemKeyNormalizer` now strips a spelled-out count before a unit ("One Dozen", "Six Pack") the same way it already stripped "6 pack", so "Eggs One Dozen" → "egg" and rolls up under "eggs". Number words are only dropped when a unit follows, so brands like "One A Day" are preserved. (Covers the gap left by the decimal-size fix.)
- **Co-op 0-candidate payload:** can't inspect its raw JSON from device logs (counts only), so shipped two safe, general improvements: (1) the extractor now finds a price held in a **price-named child object** (`{"name":..,"price":{"value":3.99}}` / `{"pricing":{"current":..}}`) — a common schema the top-level scan missed — guarded to only descend into price-named containers so a `size:{value:500}` object isn't mistaken for a price; (2) a **zero-candidate diagnostic** logs a bounded payload sample when an `endpointJSON` banner extracts nothing, so the next device run reveals Co-op's actual item shape. 4 new tests (nested price found, size object not mistaken, spelled-out quantity, decimal rollup); 47 flyer/normalizer tests green.

### 2026-06-30 - Saved-prices management + normalizer enrichment

Two quality items:
- **Saved flyer prices management:** new `SavedFlyerPricesView` (reached from the Flyer POC's "Manage saved flyer prices" link) lists every saved `FlyerPriceRecord` with full provenance (banner, price + regular strikethrough, member, sale-end, region, confidence, saved date), swipe-to-delete, and Clear All — backed by `FlyerPriceRecordRepository.delete`.
- **Normalizer enrichment (match recall):** `ItemKeyNormalizer` now strips decimal pack sizes ("1.89 L", "454.5 g") *before* the non-alphanumeric fold, fixing the bug where the decimal split into a dangling number that became the head noun ("Almond Milk 1.89L" now matches "milk"). Added `dozen`/`doz` to the removable units. Verified against 64 normalization-dependent tests across normalizer/basket/price-insight/shopping/trip/flyer suites — no regressions. Remaining known gap: word-quantities ("Eggs One Dozen") still displace the head noun; that needs lexical handling, deferred.

### 2026-06-29 - Promotion follow-up: flyer-only items surface in Compare Browse/Search

Fixed the gap where a saved flyer deal was invisible in Compare unless the user had already scanned that item: `CompareViewModel.recompute` now also takes `flyerRecords` and synthesizes Browse rows for items that exist **only** as saved flyer prices (no captured `PriceEntry` for that key), flagged `isFlyerOnly` and labeled "Flyer only · N banners" with the cheapest banner price. These rows are searchable and tappable (the item-detail "Flyer prices" section then shows them). Dedup is by exact normalized key so an item with both a capture and a flyer price isn't double-listed. `CompareRootView` `@Query`s `FlyerPriceRecord`, the empty-state gate now considers flyer records, and the empty "Recent Captures" section is hidden when there are no captures. 3 new tests (flyer-only appears/flagged/cheapest, no dup vs capture, searchable); 7 promotion tests total, build green.

### 2026-06-29 - Promotion: saved flyer prices appear in Compare

Saved `FlyerPriceRecord`s now surface in the Compare item-detail screen as a dedicated, clearly-labeled **"Flyer prices"** section (best price first, with regular-price strikethrough, sale-end date, and member flag). Per the plan's trust guardrails, flyer prices are kept visually and structurally separate from in-person `StoreComparisonRow` captures — never merged into the unit-normalized store comparison — with a footer that they're advertised prices and may differ from an in-store scan. Matching reuses `ItemKeyNormalizer.matches` (same head-noun rollup), via a pure `CompareViewModel.flyerComparisonRows(itemKey:records:)` builder; `ItemDetailView` `@Query`s `FlyerPriceRecord` and recomputes when records change. 4 promotion tests; build green.

Follow-ups: flyer-only items (no captures) don't yet appear in the Compare browse/suggested lists (those are still `PriceEntry`-derived); basket/shopping estimates don't yet factor flyer prices; and a saved-flyer-prices management surface is still pending.

### 2026-06-29 - Steps 7 & 8 (real-list review + save to dedicated store)

Step 7: deal matching now runs against the user's real default shopping list (active items, via `ShoppingListRepository`), falling back to the sample list only when empty. Review rows surface per-deal provenance (regular price, size, member-only, sale-end, confidence) and label which list was matched.

Step 8: saving follows the plan's Option C — a dedicated `FlyerPriceRecord` `@Model` (registered in the app container) separate from user-captured `PriceEntry`, so scraped flyer data never contaminates trusted capture history. `FlyerPriceRecordRepository.save` is idempotent on `bannerID|normalizedItemKey|price` (re-save updates in place), records full provenance (carried onto `FlyerDeal` as `sourceURL`/`fetchedAt`), and the review UI shows a per-deal +/✓ save control backed by the saved-key set. 5 repository tests (provenance, idempotency, distinct-deal separation, saved-key set, delete) + the 6 matcher tests pass; build green.

**MVP steps 1–8 are now all implemented.** Remaining/quality follow-ups: promote saved `FlyerPriceRecord`s into Compare/Shopping estimates with "Flyer price" labels; the shared-normalizer head-noun limitation (decimal sizes / trailing descriptors) for match recall; Co-op's 0-candidate payload; and a saved-prices management surface.

### 2026-06-29 - Candidate-quality hardening + step 6 (deal matching)

Quality pass on the 100+-item banners (Walmart 121 / Safeway 114): hardened the two dominant noise/dupe classes the generic JSON object-scan is prone to — (1) a name must read like a product (≥2 letters) and have a non-empty normalized key, dropping SKU/numeric/unit-only objects the scan also reaches; (2) dedup now keys on normalized item key + price (not also kind/dates), folding the same product appearing across capture sections (main grid, "recommended", related) into one candidate. 3 new tests. Definitive string-level eyeball still wants a device run's sample rows, but the structural inflation sources are now guarded. (The candidate count vs. acquisition `priceSignalCount` gap is expected — the count is full items, the signal a narrow regex.)

Step 6 — `FlyerDealMatcher`: matches candidates to shopping-list items via `ItemKeyNormalizer.matches(queryKey:entryKey:)`, the shared head-noun-anchored rule, returning per-item deals sorted best-price-first (a store-to-store comparison). POC demonstrates it against a fixed sample grocery list with a `[FlyerMatch]` log trail and a "Sample List Deals" section; real `ShoppingListItem` wiring is deferred to the review/save surfaces (step 7+). 6 matcher tests. Surfaced a real shared-normalizer limitation (decimal pack-sizes / trailing descriptors displace the head noun) — logged for the enrichment pass rather than fixed in the shared normalizer now.

### 2026-06-29 - Step 5 device run #2: balanced-object scan validated (247 candidates)

The fix landed. Extraction jumped from 10 total candidates (run #1) to **247** across 5 banners: Walmart **121** (was 0), Safeway **114** (was 0), Save-On **6**, RCSS **3**, No Frills **3**. The balanced-`{ }`-object scanner turned the previously-blind `endpointJSON` banners into the richest sources.

Residuals (neither blocking step 5):
- **Co-op** captured 357 KB / `prices=4` but extracted **0** — its captured payloads appear to be store/publication metadata, not the item list (Co-op has only ever shown the borderline `prices=4`), so 0 is most likely honest rather than a parser miss; confirming needs its raw payload.
- **Sobeys / FreshCo** were `acquiredNoPrices` this run (didn't reach the store-locator) — acquisition-side variance, not extraction; when they capture, the JSON path now mines them (run #9d showed Sobeys at 49 prices).

Follow-ups: spot-check candidate *quality* for the 100+ banners (dedupe/noise), and consider whether the candidate count vs. acquisition `priceSignalCount` gap needs reconciling. Next milestone: step 6 (match candidates against shopping-list item keys — the normalized item key is already on every candidate).

### 2026-06-29 - Step 5 device run #1: JSON path fixed (strict parse → balanced-object scan)

First device run of extraction exposed the core bug: every `endpointJSON` banner extracted **0** candidates (Safeway 41 prices captured → 0, Sobeys 49 → 0, Walmart 8 → 0, Co-op 4 → 0), while the text-path banners worked (RCSS 5, No Frills 5). Cause: captured payloads are **several JSON docs joined by newlines, each individually truncated at the capture byte cap**, so strict `JSONSerialization` (whole-doc and per-line) failed on exactly the priced documents — the `priceSignalCount` regex saw the prices, but the parser couldn't.

Fix: replaced the strict-parse + recursive-walk JSON strategy with a **balanced-`{ }`-object scanner** over raw UTF-8 bytes (tracking string/escape state so braces inside strings are ignored). It recovers intact item objects even when the enclosing document is truncated or concatenated, and skips objects larger than `maxObjectBytes` (containers / the truncated outer doc) so only leaf items are parsed. Two new tests lock it in (truncated+concatenated recovery; braces-inside-strings); 14 extraction tests pass. Next device run should turn Safeway/Sobeys/Walmart/Co-op from 0 → dozens of candidates.

### 2026-06-29 - Step 5: Deterministic Price-Candidate Extraction

Extraction (MVP step 5) is implemented as a deterministic pass over acquired content — `FlyerPriceExtractor` → `[FlyerPriceCandidate]`, wrapped per banner in `FlyerExtractionResult`. Chose deterministic parsing over a FoundationModels pass because the captured payloads are already structured JSON: a generic recursive walker that emits a candidate for any object holding both a name-ish and a price-ish field handles Flipp, Salesforce, and Walmart schemas without hardcoding each, and is reliable, free, and unit-testable. The messy harvested-text path (Loblaw alt-text, OCR) uses `$X.XX`-token-to-line pairing at lower confidence; model-assisted enrichment of that path is the natural later upgrade.

Plumbing change: acquisition discarded the full payload (only a 300-char debug snippet survived), so a bounded `extractionPayload` was added to `FlyerAcquiredContent`, populated by both acquirers, and consumed by the extractor — preserving the doc's "acquisition gets bytes, extraction turns bytes into candidates" boundary. The POC tab gains a third "Extract Price Candidates" phase with per-banner candidate rows and a `[FlyerExtraction]` log trail. 12 extraction unit tests (Flipp/Salesforce/nested/text/dedupe/member/implausible-price/empty); the 16 acquisition tests still pass. Next: device run to see real candidate counts per banner, then step 6 (match candidates against shopping-list item keys).

### 2026-06-24 - Direction Captured

Initial planning doc created for user-triggered flyer processing. The key product decision is that flyer checks should be manually triggered first, likely from Shopping List, and should produce reviewable structured candidates with strong source provenance before any data is treated like trusted price history.

### 2026-06-24 - Alberta Source Catalog Chosen

The first implementation should hard-code an Alberta-focused grocery banner set instead of attempting broad web discovery. The source catalog starts with Real Canadian Superstore, Safeway, Sobeys, Costco, Walmart Supercentre, No Frills, Save-On-Foods, FreshCo / Chalo! FreshCo, Co-op / Calgary Co-op, and Freson Bros. Connectors should be implemented in rank order, with explicit unsupported reasons for banners whose public flyer sources are not accessible enough for v1.

### 2026-06-25 - Source-Shape Audit: All Banners Are JS-Rendered

On-device runs with the price-density-gated classifier showed **every supported Alberta banner classifies `dynamicHTML` with zero (or chrome-noise) static price tokens** — including Save-On-Foods at 1.5 MB. None serve flyer prices in static HTML. This decides the extraction strategy: static HTML parsing is out; the extraction milestone must use a rendered fetch (`WKWebView`), each retailer's client-side flyer JSON/PDF endpoint, or an official flyer-image + OCR path. Recommended next step is to inspect 2–3 banners' client-side network traffic for a stable JSON/PDF endpoint before committing to headless rendering. Full per-banner table and conclusion in `FlyerSourceDiscoveryHardeningPlan.md`.

### 2026-06-25 - Source Shape Classification Added

Discovery moved one step from "URL reachable" toward "source candidate." Added `FlyerSourceShape` and a pure `FlyerSourceShapeClassifier` that labels each fetched document `html`, `pdf`, `image`, `json`, `dynamicHTML`, or `unknown` from MIME type plus simple flyer-term signals. `FlyerFetchedDocument` now also carries a bounded `contentSnippet` and `usefulnessSignals`, the shape rides through to `FlyerDiscoveryResult`, the POC row shows it, and the discovery log records `shape=` per fetch. Six classifier unit tests added (13 flyer tests total, all passing). Remaining hardening work: the full per-attempt audit trail on the result model, plus redirect and failure-reason coverage. See `FlyerSourceDiscoveryHardeningPlan.md`.

### 2026-06-24 - First Real-Network Source Audit Run

Ran the no-key POC against all ten Alberta banners on a physical device. Every banner resolved via official Known URL (`found=10`, `braveKeyConfigured=false`), so the no-key discovery path is confirmed working. All responses were `text/html`. Costco's `/coupons.html` returned only 2,602 bytes and is flagged `weak` (likely a shell/redirect), and Save-On-Foods returned 1.5 MB. Full per-banner results, decisions, and follow-ups are recorded in the audit table in `FlyerSourceDiscoveryHardeningPlan.md`. Remaining before extraction: resolve the Costco source, validate `FlyerSourceShape` against real PDF/image fixtures, and deliberately exercise the missing-key fallback branch.

### 2026-06-24 - Source Discovery POC Implemented

The Flyers POC now has a real source-discovery layer. `FlyerBannerCatalog` owns the Alberta banner list, `FlyerSourceConnectorCatalog` owns official retailer URLs and allowed domains, `FlyerDiscoveryCoordinator` checks official URLs with `URLSession`, and `BraveSearchProvider` provides fallback discovery when `BRAVE_SEARCH_API_KEY` is configured. Third-party flyer sites are intentionally rejected for v1. The UI reports per-banner source status only; product extraction, review, persistence, and alerts remain future milestones.
