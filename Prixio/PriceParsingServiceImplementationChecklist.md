# PriceParsingService Implementation Checklist

This file tracks the parser TODOs in strict sequence. Each step should be completed, tested, and validated before the next one starts.

## Current State

Step 7 is implemented. Build validation succeeds, and the new quantity inference cases were verified in-project, but targeted test validation is still partially blocked by the current Xcode test environment and MCP test execution instability.

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
- Live test diagnostics were previously polluted by a `TestingMacros` plugin path conflict between two local Xcode installs, so targeted test validation still cannot be treated as cleanly complete from the assistant harness

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
Status: Pending

Scope:
- Derive confidence from agreement across snapshot signals and ambiguity analysis
- Add tests for clean, weak, and conflicting scans

## Next Session Handoff

If a new session picks this up, start with Step 8 only.

Do not touch yet:
- candidate ranking rules
- item-name extraction logic
- quantity inference logic
- final confidence calculation

Read first:
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `PrixioTests/PriceParsingServiceDataSanitation.swift`
- `PrixioTests/PriceParsingServiceAmbiguityTests.swift`

Then implement:
- final confidence assembly improvements in `makeOCRResult(from:)`

Then validate in this order:
- file diagnostics for `PriceParsingService.swift`
- `PriceParsingServiceSpatialGroupingTests`
- `PriceParsingServiceAmbiguityTests`
- full project build

## Execution Rule

For every remaining step:
- implement the change
- add or update tests
- run Xcode diagnostics
- run targeted tests
- run a full build
- only then continue
