# PriceParsingService Implementation Checklist

This file originally tracked the parser TODOs in strict sequence. That eight-step parser pass is now complete.

The file now serves as the handoff for the next phase of work around parser reliability, maintainability, and integration.

## Current State

The parser implementation checklist is complete.

What is done:
- Spatial grouping
- Sparse OCR fallback
- Snapshot normalization expansion
- Price candidate scoring
- Unit detection hardening
- Item-name extraction
- Quantity inference
- Final confidence assembly

What is not done:
- Clean, repeatable targeted test execution from the assistant/Xcode harness
- Broader real-world OCR fixture coverage
- Downstream scan-flow review for low-confidence and ambiguous parser results
- A deliberate Foundation Models rollout plan beyond the current second-pass prototype

What already changed:
- `OCRTextObservation` now carries an optional `boundingBox`.
- Vision OCR now passes `VNRecognizedTextObservation.boundingBox` into `OCRTextObservation`.
- `buildHeuristicSnapshot` now orders observations in reading order.
- `buildHeuristicSnapshot` now groups nearby observations into `spatialGroups`.
- The snapshot now focuses parsing on the strongest spatial group instead of all supported lines.
- Multi-product detection still works by checking `snapshot.spatialGroups` in `looksLikeMultiProductScan`.
- Bounding boxes are preserved through sanitization, normalization, and consolidation paths where line identity survives.
- `buildHeuristicSnapshot` now uses a deterministic fallback ladder when strict filtering starves sparse OCR.
- The fallback prefers cleaned focused evidence first, then broader cleaned inputs, and only falls back to minimally sanitized observations as a last resort.
- Snapshot normalization now repairs comma-decimal price variants, split price tokens, and merged price/unit lines before extraction.
- Snapshot price candidates are now re-ranked with deterministic context scoring after extraction.
- Candidate scoring now rewards proximity to descriptive product text, promo markers, and unit labels.
- Candidate scoring now penalizes regular-price fallback lines and deposit/fee lines so they do not crowd the primary shelf price.
- Added competing-candidate tests covering nearby-vs-distant price lines, sale-vs-regular price lines, and deposit fee lines.

Files touched through Step 4:
- `Prixio/Scanning/OCR/OCRTextObservation.swift`
- `Prixio/Scanning/OCR/OCRService.swift`
- `Prixio/Scanning/OCR/Array+OCRTextObservation.swift`
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `PrixioTests/PriceParsingServiceSpatialGroupingTests.swift`
- `PrixioTests/PriceParsingServiceDataSanitation.swift`
- `PrixioTests/PriceParsingServiceAmbiguityTests.swift`

Validation already done:
- `PriceParsingService.swift` file diagnostics are clean
- `BuildProject` now succeeds from the MCP harness
- A targeted `RunSomeTests` invocation reported `No result` for the selected parser tests
- A follow-up targeted `RunSomeTests` invocation timed out after 120 seconds
- Step 5 targeted tests initially surfaced two real regressions, both of which were fixed in `PriceParsingService.swift`
- After the Step 5 fixes, follow-up `RunSomeTests` invocations failed with incomplete Xcode result bundles instead of parser assertions
- `ExecuteSnippet` verification now confirms the new Step 5 cases for mixed-unit labels, split `price per` OCR, and multi-pack/count-pack signals inside the project context
- Step 6 introduced a scored item-name extractor and new branded-name fixtures
- Step 6 snippet verification confirms branded names with numbers and size markers now survive snapshot extraction, promo-only lines no longer win by default, and short unit-only fragments no longer beat the product line
- Step 6 `RunSomeTests` and `ExecuteSnippet` attempts hit harness timeouts before the final smaller in-project snippet verification succeeded
- Step 7 introduced candidate-aware quantity inference for multi-buy offers, BOGO-style promos, and pack/count notation
- Step 7 snippet verification confirms `2/$5` resolves quantity `2`, `Buy One Get One Free` resolves quantity `2`, and pack/count notation resolves per-each quantities like `12` and `6`
- Step 8 replaced raw top-candidate confidence with assembled result confidence derived from snapshot agreement and ambiguity penalties
- Step 8 snippet verification confirms clean scans score high confidence, weak single-line scans score low confidence, and conflicting scans land in between
- Live test diagnostics were previously polluted by a `TestingMacros` plugin path conflict between two local Xcode installs, so targeted test validation still cannot be treated as cleanly complete from the assistant harness

## Completed Parser Work

1. Spatial line grouping in `buildHeuristicSnapshot`
Status: Complete

2. Sparse OCR fallback in `buildHeuristicSnapshot`
Status: Complete

3. Snapshot normalization expansion
Status: Complete

4. Price candidate scoring
Status: Complete

5. Unit detection hardening
Status: Complete

6. Item-name extraction
Status: Complete

7. Quantity inference
Status: Complete

8. Final confidence assembly in `makeOCRResult`
Status: Complete

## Next Phase

This section replaces the old sequential parser TODO list. The parser feature push is done. The next work should happen in this order.

1. Validation hardening
Status: Next

Scope:
- Make targeted parser tests run cleanly and repeatably from the current Xcode/tooling environment
- Diagnose whether the remaining failures are `TestingMacros`, result-bundle corruption, timeouts, or test-plan/configuration issues
- End this phase with reliable targeted runs for:
  - `PriceParsingServiceSpatialGroupingTests`
  - `PriceParsingServiceAmbiguityTests`
  - `PriceParsingServiceDataSanitation`

Definition of done:
- Targeted parser tests run without `No result`, incomplete result bundles, or repeated harness timeouts
- Full project build still succeeds
- The validation story no longer relies on snippet verification as the primary fallback

2. Parser refactor
Status: Complete; build-validated

Scope:
- Break up `PriceParsingService.swift` without changing parser behavior
- Separate snapshot prep, candidate scoring, item-name extraction, quantity inference, and confidence assembly into clearer helper seams or types
- Preserve current test coverage and behavior while reducing file density and coupling

Completed work:
- Split parser concerns into `Prixio/Scanning/Price/Parsing/`
- Kept `PriceParsingService.swift` as the orchestration entry point plus shared parser types/constants
- Moved snapshot construction into `PriceParsingSnapshotBuilder.swift`
- Moved candidate extraction/ranking into `PriceCandidateScorer.swift`
- Moved unit/quantity logic into `PriceParsingUnitResolver.swift`
- Moved item-name extraction into `PriceParsingItemNameResolver.swift`
- Moved ambiguity/confidence/result assembly into `PriceParsingConfidenceResolver.swift`
- Moved assisted/Foundation Models flow into `PriceParsingAssistedExtraction.swift`

Definition of done:
- `PriceParsingService.swift` is materially easier to navigate
- Existing parser behavior remains stable
- No checklist-era heuristics are lost during extraction

3. Real-world OCR fixture coverage
Status: Next

Scope:
- Add more fixtures that look like actual shelf tags instead of only narrow synthetic inputs
- Cover sale tags, deposit-heavy beverage tags, side-by-side products, weird pack notation, and noisy flyer/receipt edge cases
- Prefer regression-style fixtures that preserve bugs we already learned from

Definition of done:
- Parser coverage better reflects real shelf-tag failure modes
- At least a few new regression fixtures come from real captured OCR patterns

4. Scan-flow integration review
Status: Pending

Scope:
- Review how `ScanViewModel` and the scanner UI consume low-confidence, ambiguous, or assisted parser results
- Check whether confidence, quantity, and item-name improvements are surfaced clearly in the confirmation flow
- Look for places where parser uncertainty should drive different UI behavior

Definition of done:
- Parser confidence meaning is reflected coherently in the scan flow
- Ambiguous parses do not silently look “done” in the UI

5. Foundation Models rollout
Status: Pending

Scope:
- Keep Foundation Models as a constrained second-pass parser, not the primary parser
- Expand the current assisted extraction path deliberately instead of letting it grow ad hoc
- Use guided generation with typed `@Generable` responses and keep prompts/session state small

Implementation order:
1. Stabilize the current assisted extraction path
2. Improve prompt/schema quality before expanding responsibilities
3. Expand model responsibilities only where heuristics remain structurally weak
4. Add explicit validation for heuristic-vs-assisted agreement

Phase 1: Stabilize current assisted extraction
- Keep the current trigger boundary: only escalate when `analyzeAmbiguity(in:)` says the heuristic parse is weak or ambiguous
- Audit `AssistedExtractionResponse`, `AssistedExtractionResult`, `buildAssistedExtractionPrompt(...)`, and `mergeAssistedExtraction(...)`
- Make sure the model is only selecting among existing OCR lines and existing price candidates
- Add regression coverage for:
  - assisted line selection
  - assisted candidate classification
  - assisted item-name normalization
  - confidence changes when assisted output agrees or disagrees with heuristics

Phase 2: Tighten prompt/schema design
- Keep `LanguageModelSession` single-turn for this parser flow unless there is a proven benefit to multi-turn context
- Keep instructions short to reduce token/context pressure
- Continue using guided generation with `@Generable` output instead of raw string parsing
- Prefer explicit field semantics over long narrative prompts
- If needed, split one large assisted task into smaller single-purpose model calls rather than growing one oversized prompt

Phase 3: Expand only the right model responsibilities
- Good next uses:
  - classify existing price candidates as sale, regular, unit price, deposit, noise, or unknown
  - select which OCR lines belong to the target product when nearby tags compete
  - normalize a final canonical item name from messy OCR evidence
  - interpret promo semantics when deterministic quantity rules remain insufficient
- Lower-priority uses:
  - line-by-line OCR repair, only if real fixtures prove deterministic normalization has hit a ceiling
- Avoid:
  - inventing new prices, units, quantities, or line indexes
  - replacing deterministic parsing for clean single-tag scans
  - turning model output into the sole confidence source

Phase 4: Confidence and merge policy
- Keep final confidence derived from agreement between heuristic parsing and assisted parsing
- Reward assisted output when it agrees with strong heuristic signals
- Penalize or ignore assisted output when it conflicts with strong deterministic evidence
- Treat low-confidence model output as advisory, not authoritative

Tool-calling rule:
- Do not add Foundation Models tool calling by default
- If tool calling is introduced later, limit it to deterministic helpers such as known-brand lookup, normalization helpers, or catalog-backed disambiguation
- Do not use tools for side effects in the parser path

Definition of done:
- The assisted path is explicitly scoped and documented
- Prompt/schema design is lean and testable
- Assisted extraction improves real ambiguous scans without regressing clean heuristic-only scans
- Confidence and merge behavior are covered by tests or deterministic in-project verification

## Sequential Plan

1. Spatial line grouping in `buildHeuristicSnapshot`
Status: Complete

Completed work:
- Threaded OCR bounding boxes into `OCRTextObservation`
- Ordered lines by reading order
- Grouped nearby lines into product-level clusters
- Focused the snapshot on the strongest cluster while preserving enough metadata for ambiguity detection
- Added tests for side-by-side shelf tags

Known follow-up:
- The Step 1 TODO comment still exists in `PriceParsingService.swift`. Remove or rewrite it only when the team is satisfied with the current spatial grouping behavior.

2. Sparse OCR fallback in `buildHeuristicSnapshot`
Status: Complete

Completed work:
- Added `shouldFallbackFromFocusedObservations(...)` to detect when strict filtering starved the snapshot
- Added `makeFallbackObservationSet(...)` and `bestAvailableObservations(...)` to apply a deterministic fallback ladder
- Added `minimallySanitizedObservations(...)` as the last-resort evidence-preservation path
- Added tests covering implied-price recovery, sparse single-tag recovery, and healthy focused-group non-regression

Goal:
- Add a fallback path when strict filtering leaves too little evidence
- Prefer degraded-but-usable input over an empty or starved snapshot
- Keep the new spatial grouping behavior intact

Start here:
- `buildHeuristicSnapshot(from:)` in `Prixio/Scanning/Price/PriceParsingService.swift`
- Focus on the transition from:
  - `supportedObservations`
  - `spatialGroups`
  - `focusedObservations`
  - `cleanedObservations`
  - `normalizedObservations`

Problem to solve:
- The snapshot currently commits to the strongest spatial group first, then applies `removeObviousNoise`.
- If that focused group is sparse or noisy, `cleanedObservations` can become too small and the parser has no recovery path.
- Step 2 should recover evidence before later phases like normalization, candidate scoring, and ambiguity analysis try to reason over an underfed snapshot.

Recommended implementation order for Step 2:
- Add a small helper that decides whether the focused group survived filtering well enough.
- If not, retry with a broader fallback input instead of immediately accepting the filtered result.
- Keep the fallback deterministic and local to snapshot preparation.
- Do not change candidate scoring, unit detection, item-name extraction, or confidence assembly in this step.

Recommended fallback ladder:
- First choice: cleaned focused group
- Second choice: cleaned full strongest spatial group before any aggressive narrowing
- Third choice: cleaned `supportedObservations`
- Last resort: minimally sanitized observations if every stricter pass collapses

Suggested helper seams:
- `shouldFallbackFromFocusedObservations(...)`
- `makeFallbackObservationSet(...)`
- `bestAvailableObservations(...)`

Minimum test coverage to add in Step 2:
- A blurry or partial tag where filtering drops the only useful price line
- A sparse single-tag case where fallback keeps one usable descriptive line and one usable price line
- A case proving fallback does not collapse back into mixing two side-by-side products when the focused group is already healthy

Existing tests to keep green while doing Step 2:
- `PriceParsingServiceSpatialGroupingTests`
- `PriceParsingServiceAmbiguityTests`
- `ConsolidateObservationsTests`

Definition of done for Step 2:
- The snapshot retains usable evidence in sparse OCR cases
- Existing spatial grouping behavior still passes
- No regression in multi-product ambiguity detection
- Build succeeds

3. Snapshot normalization expansion
Status: Complete

Completed work:
- Added deterministic price-token normalization ahead of contextual token repair
- Repaired comma-decimal price variants like `1,29/lb` into canonical currency text
- Repaired split price tokens like `1 29 /lb` before candidate extraction
- Repaired merged price/unit lines like `S299ea` so the existing price and unit parsers can consume them
- Added test coverage for the new normalization behaviors

Scope:
- Improve OCR repair for merged tokens, missing currency symbols, and decimal/comma variants
- Keep corrections deterministic and test-driven

4. Price candidate scoring
Status: Implemented; build-validated, test execution still blocked in harness

Completed work:
- Re-ranked extracted candidates using snapshot-local context instead of raw extraction priority alone
- Added deterministic boosts for nearby descriptive product text, promo markers, and unit labels
- Added deterministic penalties for regular-price fallback lines and deposit/fee lines
- Added competing-candidate coverage in `PriceParsingServiceAmbiguityTests`

Scope:
- Rank candidates using proximity to product text, promo markers, and sale-vs-regular hints
- Add tests for competing candidate scenarios

5. Unit detection hardening
Status: Complete; build-validated, snippet-verified, test runner still unstable in harness

Scope:
- Handle compound units, multi-pack signals, and split “price per” phrases
- Add targeted unit parsing fixtures

Completed work:
- Replaced the snapshot unit detector’s first-match substring checks with scored unit evidence
- Prefer direct rate-unit signals over package-size text when mixed-unit labels appear on the same shelf tag
- Preserve standalone unit tokens like `lb` during noise filtering so split `price per` OCR still resolves a unit
- Preserve multi-pack size lines like `12 x 355 mL` and count-pack lines like `6 pk` instead of misclassifying them as SKU noise
- Added targeted fixtures covering mixed-unit labels, split `price per` phrases, multi-pack package sizing, and count-pack labels

6. Item-name extraction
Status: Complete; build-validated, snippet-verified, test runner still unstable in harness

Scope:
- Replace the first-match shortcut with a scored extractor
- Keep branded names even when they contain numbers or size markers

Completed work:
- Replaced the first acceptable-line shortcut with a scored item-name extractor inside `buildHeuristicSnapshot(from:)`
- Score item-name candidates using descriptive-token density, proximity to the top price candidate, confidence, and penalties for promo-only or receipt-like text
- Relaxed SKU-style rejection when a line carries explicit size tokens so branded names like `7UP Zero Sugar 2L` survive
- Added targeted fixtures covering branded names with numbers and sizes, promo-only competing lines, and short unit fragments that should not become the item name

7. Quantity inference
Status: Complete; build-validated, snippet-verified, test runner still unstable in harness

Scope:
- Infer quantities from multi-buy offers, BOGO-style promos, and pack notation
- Tie quantity selection back to the chosen candidate and detected unit

Completed work:
- Added a single snapshot quantity-inference helper that starts with the chosen price candidate instead of guessing from the entire OCR blob
- Preserve explicit candidate quantities for direct multi-buy offers like `2/$5` and `3 for $10`
- Infer BOGO-style quantities from nearby promo lines tied to the selected price candidate
- Infer per-each quantities from multi-pack and count-pack notation like `12 x 355 mL` and `6 pk`
- Added targeted fixtures covering multi-buy, BOGO, multi-pack, and count-pack quantity resolution

8. Final confidence assembly in `makeOCRResult`
Status: Complete; build-validated, snippet-verified, test runner still unstable in harness

Scope:
- Derive confidence from agreement across snapshot signals and ambiguity analysis
- Add tests for clean, weak, and conflicting scans

Completed work:
- Replaced the raw top-candidate confidence shortcut in `makeOCRResult(from:)` with assembled heuristic confidence
- Added confidence boosts for signal agreement across price, item name, unit, quantity, and OCR support density
- Added confidence penalties for ambiguity weaknesses like missing fields, sparse OCR, competing prices, and multi-product scans
- Added focused tests for clean, weak, and conflicting confidence outcomes

## Next Session Handoff

If a new session picks this up, start with `Validation hardening`.

Read first:
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `PrixioTests/PriceParsingServiceDataSanitation.swift`
- `PrixioTests/PriceParsingServiceAmbiguityTests.swift`
- `PrixioTests/PriceParsingServiceSpatialGroupingTests.swift`

Then focus on:
- making targeted parser tests reliable before broader fixture expansion
- keeping any future Foundation Models expansion constrained to second-pass ambiguity resolution

## Execution Rule

For each next-phase item:
- make the smallest change that resolves the actual blocker
- prefer validation and regression coverage before further heuristics
- run Xcode diagnostics
- run targeted tests when the harness allows it
- run a full build
- update this file and `Journal.md` with the real outcome
