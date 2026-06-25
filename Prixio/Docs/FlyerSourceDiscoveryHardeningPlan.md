# Flyer Source Discovery Hardening Plan

## Purpose

This document defines the work needed to finish the current flyer source-discovery POC before moving to flyer asset fetching and product-price extraction.

The key upgrade is to move discovery from "URL reachable" to "source candidate audit." A reachable URL only proves a server responded. A source candidate audit proves the app found an official, useful, diagnosable source that the next phase can classify, fetch, and extract from.

## Testing We Need

### 1. Unit Coverage For Existing Discovery Rules

Keep the current `FlyerDiscoveryTests` coverage and expand it around the richer audit contract.

Existing coverage already proves:

- Alberta banners are listed in rank order.
- Connector URLs stay inside official allowed domains.
- Known official URLs are tried before search fallback.
- Brave Search fallback can select official-domain results.
- Missing `BRAVE_SEARCH_API_KEY` is reported clearly.
- Third-party flyer sites are rejected.
- The POC view model summarizes discovery results.

Additional unit tests needed:

- Redirects preserve both attempted URL and final URL.
- Non-2xx responses are captured as diagnostics instead of disappearing.
- Empty bodies are rejected with a specific reason.
- HTML shells with no useful flyer terms are marked reachable but weak.
- PDF responses are classified as PDF source candidates.
- Image responses are classified as image source candidates.
- Official-domain search results that fail fetch are reported with failure details.
- Third-party search results are recorded as rejected diagnostics without being fetched.
- Multiple failed known URLs are preserved in the result detail.
- Unsupported connectors return their explicit unsupported reason without network work.

### 2. Real-Network Connector Audit

Run the POC against all ten Alberta banners using real network responses. This should be a deliberate audit pass, not just a casual button tap.

Record for each banner:

| Field | Why It Matters |
| --- | --- |
| Banner | Keeps the source tied to the catalog entry. |
| Attempted URL | Shows which seed or search result was tested. |
| Final URL | Captures redirects and regional routing. |
| HTTP status | Separates reachable, redirected, blocked, and failed sources. |
| MIME type | Helps classify HTML, PDF, image, or unknown source shape. |
| Byte count | Catches empty responses and suspiciously tiny shells. |
| Source shape | Tells the next phase which extractor family is needed. |
| Geography signal | Notes whether the page is Alberta, city, postal-code, or store-specific. |
| Useful flyer signal | Confirms whether the page appears to contain active flyer/deal material. |
| Extraction risk | Flags dynamic JS, store selection gates, account prompts, PDFs, image viewers, or anti-bot behavior. |
| Decision | `accepted`, `weak`, `unsupported`, or `needs manual source research`. |

### 3. UI Smoke Test

Run the app in simulator or on device and validate the Flyers POC tab.

Checklist:

- The Flyers tab opens cleanly.
- `Check Flyers` starts a visible loading state.
- The button disables while discovery is running.
- Every banner receives a result row.
- Result rows show enough detail to debug failures.
- Missing Brave credentials produce a clear fallback-unavailable message, not a generic failure.
- Network failures do not leave the spinner stuck.
- Long URLs wrap without breaking the row layout.
- VoiceOver reads each row as a coherent status summary.

### 4. API Key Path Test

Run discovery twice:

- without `BRAVE_SEARCH_API_KEY`
- with `BRAVE_SEARCH_API_KEY` configured through the existing local secrets path or scheme environment

Expected behavior without key:

- Known URLs are still checked.
- Fallback is reported as unavailable only after known URLs fail.
- The run completes for all banners.

Expected behavior with key:

- Search queries are attempted only when known URLs fail or are weak.
- Official-domain search results can be accepted.
- Flipp, Flyers Online, and other third-party domains are rejected and recorded as diagnostics.
- Search API errors are surfaced with enough detail to reproduce.

### 5. Retailer-By-Retailer Source Audit

The first audit should produce a table like this in the implementation notes or a follow-up source-audit doc:

First real-network run recorded 2026-06-24 (no Brave key; `braveKeyConfigured=false`). All ten banners resolved via official Known URL — `found=10 fallbackUnavailable=0 failed=0 unsupported=0`. "Decision" below is the next-phase extraction judgment, which is separate from the discovery state of `Found`.

| Rank | Banner | Known URL (final) | HTTP | MIME | Bytes | Decision | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Real Canadian Superstore | /en/print-flyer | 200 | text/html | 39,198 | accepted (verify) | Confirm whether print-flyer HTML holds extractable content or is a dynamic shell. |
| 2 | Safeway | /flyer | 200 | text/html | 322,021 | accepted (verify) | Large HTML; verify geography/store-selection gating. |
| 3 | Sobeys | /flyer | 200 | text/html | 320,276 | accepted (verify) | Large HTML; verify store-selection and shared Empire flyer behavior. |
| 4 | Costco | — | — | — | — | **unsupported** | Removed 2026-06-25. Original `/coupons.html` returned only 2.6 KB (JS coupon shell, no grocery flyer). Connector now stubbed `unsupported` with an explicit reason. |
| 5 | Walmart Supercentre | /en/flyer | 200 | text/html | 95,130 | accepted (verify) | Verify whether flyer items require rendered JS or location context. |
| 6 | No Frills | /en/print-flyer | 200 | text/html | 39,300 | accepted (verify) | Redirect `/print-flyer` → `/en/print-flyer` captured correctly. |
| 7 | Save-On-Foods | /circular | 200 | text/html | **1,529,685** | accepted (verify) | Very large HTML (1.5 MB); confirm circular is inline HTML vs embedded viewer/API before bulk fetching. |
| 8 | FreshCo / Chalo! FreshCo | /flyer | 200 | text/html | 229,797 | accepted (verify) | Verify region-specific flyer behavior. |
| 9 | Co-op / Calgary Co-op | /food/flyers/ | 200 | text/html | 59,005 | accepted (verify) | Calgary Co-op chosen as the Alberta v1 source. |
| 10 | Freson Bros. | /weekly-flyer/ | 200 | text/html | 97,405 | accepted (verify) | Confirm whether weekly flyer exposes PDF/image assets for extraction. |

#### Source-Shape Audit (2026-06-25)

Re-ran on device after adding `FlyerSourceShape` classification with visible-text term matching and a price-density gate (`.html` requires ≥5 `$X.XX` tokens in stripped visible text). Result: **every supported banner classifies `dynamicHTML`** — none serve flyer prices in static HTML.

| Rank | Banner | Shape | Visible price tokens | Notes |
| --- | --- | --- | --- | --- |
| 1 | Real Canadian Superstore | dynamicHTML | 0 | Pure SPA shell; no flyer words in visible text either. |
| 2 | Safeway | dynamicHTML | 0 | Flyer vocabulary only in nav/meta chrome. |
| 3 | Sobeys | dynamicHTML | 0 | Same Empire SPA pattern as Safeway/FreshCo. |
| 4 | Costco | unsupported | — | Stubbed unsupported (see above). |
| 5 | Walmart Supercentre | dynamicHTML | 1 | Single chrome `$` token, below threshold. |
| 6 | No Frills | dynamicHTML | 0 | Pure SPA shell (Loblaw). |
| 7 | Save-On-Foods | dynamicHTML | 0 | 1.5 MB of HTML, zero static prices — all JS bundle. |
| 8 | FreshCo / Chalo! FreshCo | dynamicHTML | 0 | Empire SPA. |
| 9 | Co-op / Calgary Co-op | dynamicHTML | 2 | Two chrome `$` tokens, below threshold. |
| 10 | Freson Bros. | dynamicHTML | 0 | Independent, but still JS-rendered flyer. |

**Conclusion — extraction strategy is decided by this audit:** static HTML parsing is a dead end for all ten Alberta banners. The extraction milestone must use one of:

1. a **rendered fetch** (e.g. `WKWebView`) that runs the page's JavaScript before reading content, or
2. each retailer's **flyer JSON/PDF endpoint** — the data the SPA itself fetches client-side (inspect network calls per banner), or
3. a **third-party/official flyer-image source** processed via OCR (revisits the v1 "official sources only" constraint).

Recommended next step before building extraction: pick 2–3 representative banners and inspect their client-side network traffic to see whether a stable flyer JSON/PDF endpoint exists, since that is cheaper and more reliable than headless rendering.

Audit follow-ups before extraction:

- Costco (rank 4): **resolved 2026-06-25** — no accessible public grocery flyer source for v1, so the connector is now stubbed `unsupported` (it returns `phase=unsupported` with an explicit reason and does no network work).
- `FlyerSourceShape` PDF/image classification paths are unit-tested but have not been exercised against a real PDF/image source (none of the ten banners serve those at the entry URL).
- The no-key fallback branch (`search-unavailable reason=missing-api-key`) was **confirmed 2026-06-25** via a temporary forced known-URL failure on device: every supported banner attempted all known URLs first, then reported `Fallback unavailable` (`found=0 fallbackUnavailable=9 unsupported=1`). The temporary force-failure flag has been removed.

## Debugging Improvements Needed

### Preserve Attempt Diagnostics

`FlyerDiscoveryResult` should stop reporting only the selected URL and one message. It needs an audit trail.

Suggested model additions:

- attempted known URLs
- attempted search queries
- search result URLs considered
- search result URLs rejected by domain filter
- fetch status per attempted URL
- final redirected URL per attempt
- failure reason per attempt
- response MIME type and byte count
- source shape guess
- source usefulness score or confidence

### Add `FlyerSourceShape`

Add a lightweight source-shape enum so the next phase can choose the right extractor path.

Suggested cases:

```swift
enum FlyerSourceShape: String, Equatable {
    case html
    case pdf
    case image
    case json
    case dynamicHTML
    case unknown
}
```

The first classifier can be simple:

- MIME type `application/pdf` -> `.pdf`
- MIME type beginning with `image/` -> `.image`
- MIME type containing `json` -> `.json`
- HTML with useful flyer/deal terms -> `.html`
- HTML that looks like an app shell with little useful text -> `.dynamicHTML`
- everything else -> `.unknown`

### Extend `FlyerFetchedDocument`

The fetcher should return enough lightweight metadata to judge usefulness without storing full source artifacts yet.

Suggested additions:

- `contentSnippet: String?`
- `contentLengthHeader: Int?`
- `responseHeaders: [String: String]` if useful for debugging
- `sourceShape: FlyerSourceShape`
- `usefulnessSignals: [String]`

Keep the snippet bounded. A short text sample is useful for debugging; storing full pages belongs to a later artifact-storage decision.

### Improve Failure Reasons

Avoid silently continuing after failed attempts. The coordinator can still keep trying, but it should remember what happened.

Useful failure categories:

- non-HTTP response
- timeout
- network unavailable
- blocked or forbidden
- not found
- empty response
- unsupported MIME type
- domain rejected
- missing API key
- search provider error
- reachable but weak source

### Update The POC Row

`FlyerDiscoveryResultRow` should expose debug details without turning the UI into a wall of text.

Recommended UI shape:

- top line: banner, status, selected source shape
- second line: selected or best attempted URL
- detail disclosure: attempts, statuses, MIME type, byte count, final URL, rejected search results
- message: human-readable summary

Accessibility requirement: the collapsed row should still read a meaningful status, such as "Safeway, fallback unavailable, official URLs failed, Brave key missing."

## Completion Criteria

Source discovery is complete enough to move to flyer asset extraction when all of these are true:

- All ten Alberta banners produce either an accepted official source candidate or an explicit unsupported decision.
- Every accepted source has banner identity, selected URL, final URL, source shape, MIME type, byte count, and discovery method.
- Every failed or unsupported source has an actionable reason.
- Redirects and rejected third-party search results are visible in diagnostics.
- Known URL discovery works without a Brave key.
- Brave fallback works when a key is configured and never accepts third-party domains.
- The UI can be used to debug a real run without Xcode logs.
- Unit tests cover redirects, unusable HTML shells, PDFs, images, rejected domains, and failure reasons.
- A real-network audit has been run and recorded for all ten banners.
- The next phase can consume a stable source candidate contract without depending on POC-only UI state.

## Next Engineering Step

The most useful next change is to upgrade discovery from "URL reachable" to "source candidate audit."

Concretely:

1. Extend `FlyerFetchedDocument` with bounded `contentSnippet` or equivalent lightweight metadata. **Done 2026-06-25** — added `sourceShape`, bounded `contentSnippet` (≤300 chars, from a ≤256 KB decoded prefix), and `usefulnessSignals`. `responseHeaders`/`contentLengthHeader` remain deferred.
2. Add `FlyerSourceShape` and classify sources from MIME type plus simple content signals. **Done 2026-06-25** — `FlyerSourceShape` (`html`/`pdf`/`image`/`json`/`dynamicHTML`/`unknown`) plus a pure `FlyerSourceShapeClassifier` (MIME first, then flyer-term signals; HTML without useful terms → `dynamicHTML`). Six classifier unit tests added.
3. Add attempt diagnostics so `FlyerDiscoveryResult` can explain every URL and search result it considered. **Pending** — `FlyerDiscoveryResult` now carries `sourceShape`, but the full per-attempt audit trail (all attempted URLs, rejected results, final URLs) is still only in the console log, not the result model.
4. Update `FlyerProcessingPOCRootView` to show debug details in each result row. **Partial 2026-06-25** — rows now show the source shape; full attempt diagnostics still pending step 3.
5. Add tests for redirects, unusable HTML shells, PDFs, images, rejected domains, and failure reasons. **Partial 2026-06-25** — PDF/image/JSON/HTML/dynamic-shell classification and rejected domains are covered; redirects and non-2xx failure-reason mapping still pending.
6. Run the POC against the real ten Alberta banners.
7. Record the source decisions and extraction risks before starting product-price extraction.

## Phase Boundary

Do not start OCR, NLP, image analysis, product matching, review persistence, or shopping-list deal matching until source discovery produces stable source candidates. Extraction work built on weak source discovery will waste time debugging retailer routing, missing geography, JavaScript shells, and rejected domains inside the wrong layer.
