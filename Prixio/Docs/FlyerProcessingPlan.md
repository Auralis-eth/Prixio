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
4. Fetch active flyer pages, product pages, images, or PDFs depending on each connector's source shape. Status: source availability check implemented; asset extraction still pending.
5. Extract product-price candidates using OCR/NLP/computer vision. Status: pending.
6. Match candidates against current shopping-list item keys. Status: pending.
7. Show a review list with source, confidence, sale dates, geography, and unit price. Status: pending.
8. Let the user save selected flyer prices or use them for list estimates. Status: pending.

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
