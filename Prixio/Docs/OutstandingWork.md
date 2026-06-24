# Outstanding Work

This file replaces the older planning and checklist markdown files.

It only tracks work that is still genuinely unfinished or intentionally deferred.
Anything fully implemented should live in code, tests, `AGENTS.md`, or `Journal.md`, not here.

## Status Summary

- Parser refactor: complete
- OCR pipeline v1: complete
- OCR pipeline v2: implemented in production form
- Compare flow MVP: complete
- Shopping List MVP: complete
- Remaining work: mostly fixture expansion, post-release measurement, small test-tooling cleanup, and a few post-MVP product refinements

## Actually Incomplete

### 1. Image Fixture Coverage Expansion
Status: Open

The current fixture set is useful, but it still does not cover several important failure classes well enough.

Missing or underrepresented fixture classes:
- bilingual promo card with side-by-side regular and member prices
- severe glare or washout shelf tag
- rotated or perspective-skewed produce sign
- dense beverage shelf edge with repeated deposit lines
- split title across three lines with package size on a fourth line
- additional compact-numeric and PLU traps from real captures

What still needs to happen:
- add new real-image fixtures when actual scan failures expose new parser gaps
- mirror the highest-value new image failures into captured-OCR fixtures
- keep fixture additions categorized by failure class so evaluation stays useful

### 2. Targeted Image-Driven Test Validation
Status: Open

Project history shows some image-driven runs timing out in the harness. The docs should not pretend that was fully closed.

What still needs to happen:
- rerun image-heavy targeted tests in a reliable local runner when needed
- record failures as parser regressions versus harness instability instead of lumping them together
- only tighten live-image assertions when OCR behavior is stable enough to deserve exact contracts

### 3. Fixture Utility Cleanup
Status: Open

There is still one small tooling gap around fixture maintenance.

What still needs to happen:
- add a compact helper that prints captured OCR observations in copy/paste fixture format

### 4. Post-Release Parser Measurement
Status: Deferred until real usage

This is real work, but it is not active pre-release implementation work.

What still needs to happen after release:
- expand the evaluation corpus as new failure patterns appear in saved scans
- review parser thresholds and review-state behavior using real scan metadata
- decide what reporting or dashboarding should consume parser review metadata
- revisit Foundation Models coverage only if production evidence shows a justified gap
- promote or expand the ship-gate suite if real regressions prove the current gate is too small

### 5. Compare, Shopping & Scanner Post-MVP Polish
Status: Deferred

The core Compare and Shopping List flows now exist, and saved-entry editing (defect B8)
shipped 2026-06-23. A few deliberate cuts remain:

- Shopping List supports one visible default list even though the data model is multi-list-ready
- Shopping List row distance is not yet surfaced end to end
- the scanner prefill loop is wired, but broader trip-plan breakdown UI is still deferred
- **Generic→specific item rollup (B4) is not applied in the repository fetch methods.**
  `PriceEntryRepository.cheapestEntries`/`priceHistory(for:)` still use exact
  `itemNameNormalized ==` predicates; their only caller is `ItemHistoryTool` (AI grounding), so the
  user-facing Compare/Shopping rollup (which goes through `PriceInsightEngine`/`CompareViewModel`) is
  correct. Advisory: bring these to `ItemKeyNormalizer.matches` parity if the AI tool should also see
  rolled-up history.

### 6. AI Capture Tools Follow-ups
Status: Open

The OCR-to-image-AI migration shipped, but two deliberate gaps remain in the
`Scanning/AI/Tools/` adapters (previously tracked in the now-deleted AIPriceExtractionTools doc):

- `InferStoreContextTool` does not reproduce every guard in `ScanViewModel.matchStoreCandidate`:
  it omits receipt suppression and the >1500 m distance rejection, and only falls back to the
  last store when the candidate pool is empty. This is advisory-only today because the
  authoritative store decision still runs after extraction via `matchStoreCandidate` +
  `applyInferredStore`, but the model can reason over un-suppressed, un-distance-filtered
  suggestions. The current behavior is locked in by `InferStoreContextToolTests`; bring the
  adapter to parity to remove the divergence.
- All four tools (`NormalizeUnitPriceTool`, `ResolveUnitAndQuantityTool`, `InferStoreContextTool`,
  `ItemHistoryTool`) are registered on the Capture `LanguageModelSession` via
  `ScanViewModel.captureTools`. The deterministic pipeline (validate, classify-receipt,
  build-draft, save) still runs unconditionally afterward, so the tools augment rather than
  replace it. Decide whether keeping them on the Capture session is worth the added model
  latency/token cost and the duplicate store-inference path, or whether Capture should use a
  tools-free session and keep the tools only for the future Compare/Planner agents.

### 7. Camera Launch Performance
Status: Open (optimization — the preview/capture path already works)

Migrated from the removed `CameraPerformanceImplementationPlan.md` planning doc. The responsive-capture and
automatic deferred-start work already shipped in `CameraController`/`CameraPreviewView` (recorded in
`LLMAppContext.md` → Camera Layer); the remaining items are measurement, startup sequencing, and
resilience:

- **Launch/capture signposts + Instruments measurement (was Phase 1).** No signposts around the scan
  launch sequence yet (scan task start, auth done, session config start/commit, `startRunning`
  start/done, preview created, capture requested, first delegate callback, deferred start began/done).
  Primary metric: time from entering scan to a visible preview frame. Don't call the perf work done
  until before/after timings exist.
- **Split critical vs deferred scan startup (was Phase 2).** `ScanRootView.task` still does camera
  prep, SwiftData seeding, location auth, and nearby-store loading in one flow. Reorder so camera prep
  is the critical path and location/nearby-store loading runs after preview startup is underway; the
  store chip shows its fallback state until candidates arrive. Avoid overlapping store loads when
  location changes mid-flight (the >250 m cache invalidation in `ScanSessionStore` already helps).
- **Richer readiness modeling (was Phases 4/6) — deferred until a consumer exists.** `isCaptureReady`
  is enough today; only add a `CameraReadiness` enum or `AVCapturePhotoOutputReadinessCoordinator` if
  UI/diagnostics need precise transitions. Emit signposts from the deferred-start delegate callbacks
  once signposts land.
- **System-pressure observation (was Phase 7).** Retain the active device in `CameraController`, log
  `session.hardwareCost`, observe `device.systemPressureState`, and on `.serious`+ defer nonessential
  work. Start conservative (logging + work deferral); only cut frame rate if profiling proves it helps.
- **Real-device timing/thermal validation (was Phase 8).** See the camera-performance cases in
  `PhysicalDeviceQATestPlan.md`.
- **Journal entry.** Add a short `Journal.md` note on the scan-launch sequencing decision when the
  startup-reordering work lands.

Non-goals (locked): do not switch to `AVCaptureVideoDataOutput` or `AVProVideoStorage`; do not gate
the shutter purely on `isCaptureReady` (responsive capture should keep early taps useful); do not
refactor OCR/parsing/compare/shopping as part of this pass.

## Price & Spending Intelligence Roadmap

The Price Capture & Intelligence spine — scanner price/receipt modes, memory experiments 1–7,
receipt ingestion + review, item price history, cheapest-basket builder, manual expenses/income,
and spending intelligence (Phases 1–11) — shipped and is test-covered. The items below are the
remaining roadmap work, migrated from the now-deleted PriceCaptureAndIntelligence doc.

Architectural invariant to preserve: **capture stores evidence; intelligence derives conclusions.**
Keep the price-tag, receipt, expense, and income streams in separate models — do not collapse them
into `PriceEntry`. Price entries are trusted item-price observations; receipts are baskets; expenses
are household spending events; income is context.

### 8. Sale & Flyer Intelligence (largest remaining area)
Status: Open

- store sale price vs regular price as distinct values (today only a parsing heuristic to pick one price)
- member vs non-member price
- multi-buy offers ("2 for $5") surfaced as offers (the parser recognizes the pattern for scoring but does not store/surface it)
- buy-one-get-one (BOGO)
- limited-time validity text
- flyer-style banner rejection (non-product text)
- explicit flyer import / flyer scanning
- deal alerts / "meaningful deal" notifications

### 9. Price History & Capture Refinements
Status: Open

- confidence weighting so low-confidence captures look less trustworthy in history (Phase 8)
- Experiment 1 — explicit "last observed price **and store**" line at scan-review (the usual-price half is covered by `PriceMemoryBadge`; the explicit last-store line is not yet shown)
- scanner mode persistence — `scanMode` resets to `.priceTag`; "remember last mode" is not implemented (deliberate-but-open)

### 10. Receipt Ingestion & Spending
Status: Open

- open-from-Mail share extension for PDF import — today PDF import is in-app document-picker (Files) only
- multi-receipt batch detection within one PDF (deferred; multi-page is composited to a 5-page cap, flagged via `pagesTruncated`)
- per-person income for shared households — income is household-level only (`IncomeEntry`)
- loyalty/member receipt prices mapped into item comparison
- cross-currency conversion — spending math sums only `reportingCurrency` records; foreign-currency receipts/expenses/income are excluded rather than converted (`CurrencyFormatter` still displays one currency app-wide)

### 11. Open Product Questions (decisions, not code)
Status: Open — these are referenced by `CurrencyFormatter`, `IncomeEntry`, `PDFReceiptRenderer`, and `ReceiptCapture`.

- receipt/scan image retention policy — images are kept indefinitely; no cleanup rule decided (`ReceiptCapture.imageData`)
- imported-PDF retention after extraction/review — undefined; pages beyond the 5-page composite cap are dropped (`PDFReceiptRenderer.maxCompositePages`)
- multi-page receipts in v1 — deferred to the composite page cap
- feature-flag receipt mode — not flagged
- per-person vs household-level income for shared homes (`IncomeEntry`)
- how loyalty/member prices from receipts should map into item comparison

## Not In Scope Unless Evidence Demands It

These are explicitly not active engineering tasks right now:
- replacing Vision OCR
- broad UI redesign tied to parser internals
- expanding Foundation Models usage by default
- reopening parser heuristics without a concrete failing fixture or production signal

## Working Rules

When this file changes:
- prefer real evidence over speculative parser work
- add or update tests in the same change
- keep live-image assertions stable-invariant based unless OCR output is truly deterministic
- update `Journal.md` when a non-trivial parser or fixture lesson is learned
