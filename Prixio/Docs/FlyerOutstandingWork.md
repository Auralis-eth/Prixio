# Flyer Outstanding Work

This file replaces `FlyerProcessingPlan.md`, `FlyerSourceDiscoveryHardeningPlan.md`, and `FlyerContentAcquisitionPlan.md`.

It only tracks flyer work that is still genuinely unfinished, undecided, or intentionally deferred. Everything implemented lives in code and tests (`Prixio/Flyers/`, `FlyerDealAdvisory`, the Flyer POC tab, and the flyer test suites).

## Productization

### 1. Move the flow out of the POC tab
Status: Open

The entire discovery → acquire → extract → match → review → save flow lives in the Flyers POC tab. It needs a real user-facing surface.

- Recommended entry point: a "Check Flyers" action in Shopping List, since the list gives a bounded set of products to search for.
- Decide the user-facing label for scraped-price confidence (e.g. "Flyer price", "Member price", "Needs review", "Region unknown").
- Keep expectations modest in copy: "checking flyers" collects candidates; it does not guarantee every retailer is covered.

### 2. Store context and geography
Status: Open

Acquisition runs against a hard-coded default store context (Calgary, T2P 1J9; pcexpress stores 1521/6969).

- Derive the context from user location or an explicit store/postal picker instead.
- Decide v1 geography: all of Alberta, or narrow to Calgary/Edmonton postal contexts first.
- A flyer from the wrong region is worse than no flyer — geography must stay explicit on every surface that shows a flyer price.

## Data Quality

### 3. Extraction enrichment
Status: Deferred (from extraction v1)

The deterministic extractor is deliberately minimal. Remaining upgrades:

- model-assisted enrichment of the messy harvested-text/OCR path (the JSON path does not need it)
- unit-price derivation from package size
- multi-buy parsing ("2 for $5", BOGO, limit quantities)

### 4. Normalizer match recall
Status: Open (residual)

`ItemKeyNormalizer` still has head-noun displacement cases that cost deal-match recall — trailing descriptors can displace the head noun. Needs lexical handling; fix in an enrichment pass, not ad hoc in the shared normalizer.

## Source Robustness

### 5. Endpoint fragility
Status: Open

Both acquisition sources are unofficial internal APIs (Flipp flyers-ng, api.pcexpress.ca) and can rotate or break without notice.

- Add detection/telemetry for when an endpoint starts failing or returning short results, so breakage is visible instead of silently producing zero deals.
- Have a fallback stance decided ahead of time (banner degrades to unsupported vs. re-investigation).

### 6. Unsupported banners
Status: Deferred

- Costco: no accessible public flyer source. Revisit only if one appears.
- Freson Bros.: weekly flyer is an image-only dFlip PDF flipbook. Supporting it would need an image/OCR acquisition path.

### 7. Minor discovery gaps
Status: Deferred

- `FlyerSourceShape` PDF/image classification is unit-tested but has never been exercised against a real PDF/image source.
- The Brave-key-configured search fallback path has never been audited on a real run (only the no-key branch has).
- `responseHeaders`/`contentLengthHeader` on `FlyerFetchedDocument` were deferred.

## Decisions Still Open

### 8. Legal / terms review
Status: Open — required before shipping

Review site terms and robots rules per banner for the endpoints in use, including whether consuming a discovered internal JSON endpoint raises the same concerns as scraping. Keep request rates conservative.

### 9. Storage and provenance
Status: Open

- Should flyer data stay SwiftData-only, or does remote/server storage exist later?
- Should market prices stay separate from user-captured prices forever, or only until reviewed?
- Should acquired payloads/artifacts be persisted for debugging and user trust, or only held transiently until extraction?
- How is a stale or rotated flyer detected at acquisition time (as opposed to record expiry after save)?

## Later Versions

Status: Deferred — do not build until the manual flow has proven reliable

- scheduled daily/weekly refreshes
- watchlist-specific refreshes
- "new low" alerts, sale-ending reminders, nearby-better-price alerts
- multi-buy-beats-history and online-vs-in-store comparisons
- household-specific deal recommendations
- push notifications
- competitor price checks for selected items

Guardrails that must hold when these are built:

- alerts explain source and confidence
- member-only and digital-coupon prices are labeled clearly
- comparisons use normalized unit price when possible
- no automatic alerts from low-confidence extractions
- no background refresh, broad web search, or account-authenticated scraping without an explicit product decision
