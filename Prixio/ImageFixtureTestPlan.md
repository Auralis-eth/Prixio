# Image Fixture Test Plan

## Goal
- Build two real-image fixture tests that exercise the OCR-to-parser pipeline end to end.
- Freeze the intermediate parser stages so regressions are fast to localize.

## Status Legend
- `[x]` done
- `[ ]` not done yet

## Fixture 1: Cadbury Shelf Tag
- Image: `Screenshot 2026-04-02 at 3.53.44 PM.png`
- Expected item: `Cadbury Chocolate Mini Eggs`
- Expected price: `17.99`
- Expected unit: `.each`
- Expected quantity: `nil`
- Expected review state right now: `reviewRequired`
- Expected FM usage right now: `true`

## Fixture 2
- [x] Add the second real image to `PrixioTests`
- [x] Write down expected item, price, unit, quantity, review state, and FM usage
- [x] Add Vision-backed test
- [x] Freeze captured OCR observations into parser-stage regression tests
- Image: `IMG_0473.png`
- Expected item: `MINI CUCUMBER`
- Expected price: `4.00`
- Expected unit: `nil`
- Expected quantity: `nil`
- Expected review state right now: `reviewRecommended`
- Expected FM usage right now: `false`

## Phase 1: Prepare The Fixtures
- [x] Decide where the fixture images will live
- [x] Add fixture 1 to `PrixioTests`
- [x] Add fixture 2 to `PrixioTests`
- [x] Use a stable filename for fixture 1
- [x] Write down the expected final parse result for fixture 1
- [x] Write down the expected final parse result for fixture 2
- [x] Confirm fixture 1 orientation is usable by Vision

## Phase 2: Build Test Infrastructure
- [x] Add a test helper to load image fixtures
- [x] Add a helper that runs the same Vision OCR request used by production code
- [x] Add a helper that converts `VNRecognizedTextObservation` into `[OCRTextObservation]`
- [x] Keep OCR helper output inspectable for debugging
- [x] Keep the end-to-end fixture test Vision-backed instead of mocked

## Phase 3: Capture Baseline OCR Output
- [x] Run OCR against fixture 1
- [x] Save the raw recognized lines, confidences, and bounding boxes from fixture 1
- [x] Repeat baseline OCR capture for fixture 2
- [x] Review the OCR output manually for fixture 1
- [x] Use the captured OCR to decide which parser-stage assertions are stable for fixture 1
- [x] Review the OCR output manually for fixture 2
- [x] Use the captured OCR to decide which parser-stage assertions are stable for fixture 2

## Phase 4: Add End-To-End Fixture Tests
- [x] Create a dedicated image fixture test file
- [x] Add one Vision-backed test for fixture 1
- [x] Assert fixture 1 final item name
- [x] Assert fixture 1 final price
- [x] Assert fixture 1 final unit
- [ ] Assert fixture 1 final quantity explicitly in the image test
- [ ] Assert fixture 1 `review.state` explicitly in the image test
- [x] Assert fixture 1 uses Foundation Models
- [x] Assert fixture 1 top candidate is `17.99`
- [x] Assert fixture 1 supporting lines include shelf-price evidence
- [x] Add the second image end-to-end test

## Phase 5: Add Parser Stage Tests From Captured OCR
- [x] Freeze fixture 1 OCR observations into a shared captured fixture
- [x] Add parser-stage regression tests for fixture 1
- [x] Assert fixture 1 cleaned observations retain `1799`
- [x] Assert fixture 1 normalized observations retain `$5.00 ea`
- [x] Assert fixture 1 candidate list keeps `17.99`
- [x] Assert fixture 1 candidate list does not reintroduce fake `8.75`
- [x] Assert fixture 1 item-name resolver output is `Cadbury Chocolate Mini Eggs`
- [x] Assert fixture 1 final parse stays on `17.99`
- [x] Repeat parser-stage freezing for fixture 2

## Phase 6: Add Failure Localization Tests
- [x] Add a test that validates fixture 1 image loading
- [x] Add a test that validates Vision OCR sees key lines for fixture 1
- [x] Add a test that validates `PriceParsingSnapshotBuilder` from captured OCR for fixture 1
- [x] Add a test that validates final `OCRResult` from captured OCR for fixture 1
- [x] Add a dedicated test that validates `PriceParsingItemNameResolver` from captured OCR only
- [x] Add a dedicated test that validates `PriceCandidateScorer` from captured OCR only
- [x] Mirror these failure-localization tests for fixture 2

## Phase 7: Make Debugging Cheap
- [x] Keep parser debug logging that prints raw OCR, groups, cleanup, candidates, and final result
- [x] Keep a Vision-backed helper that can reproduce OCR observations from a fixture image
- [x] Prefer explicit assertions over opaque text snapshots for the Cadbury fixture
- [ ] Add a compact helper that prints captured OCR in copy/paste fixture format automatically

## Phase 8: Stabilize The Contract
- [x] Freeze the parser-stage Cadbury contract against captured OCR observations
- [x] Keep the Vision-backed test lighter than the captured-OCR tests
- [x] Be stricter on parser outputs than on raw Vision ordering
- [ ] Revisit whether the Cadbury image test should assert exact `review.state` after ambiguity tuning is settled

## Phase 9: Integrate With Existing Suites
- [x] Put the Vision-backed fixture test in `ImageFixtureParsingTests`
- [x] Keep heavier Vision-backed coverage out of ship-gate for now
- [x] Reuse existing `#if DEBUG` parser seams
- [ ] Decide later whether the Cadbury fixture should graduate into ship-gate coverage

## Phase 10: Maintenance Rules
- [x] Use a real image fixture when the bug starts at OCR/layout geometry
- [x] Use captured OCR regression tests when the bug starts after OCR
- [x] Review raw OCR and candidate lists before updating expectations
- [x] Keep the fixture list small and high-signal

## Remaining Work For Fixture 1
- [x] Add explicit `review.state` assertion to the Vision-backed test once the ambiguity contract is considered stable
- [x] Add exact parser-stage assertions for the full cleaned, normalized, and consolidated Cadbury line sets
- [x] Add an exact ambiguity-contract assertion for the Cadbury captured OCR fixture
- [x] Add a direct `PriceParsingItemNameResolver` fixture-only test
- [x] Add a direct `PriceCandidateScorer` fixture-only test
- [x] Decide whether `supportingLines` on the assisted result should remain `["1799", "$5.00 ea"]` or become richer

## Fixture 1 Contract Decisions
- `supportingLines` stays narrow for now.
- Reason: `OCRResult.supportingLines` should identify the exact evidence used for the chosen result, while competing or risky context should continue to live in `review.issues` and `ambiguityNotes`.
- Cadbury fixture supporting-lines contract:
  - heuristic path may retain a broader evidence slice during debugging
  - assisted/final contract stays narrow at `["1799", "$5.00 ea"]`
- Cadbury fixture review-state contract:
  - `review.state == .reviewRequired`
  - reason: the parser still sees competing prices plus possible multi-product noise even though the final winner is correct

## Remaining Work For Broader Coverage
- [x] Add the second real image fixture
- [x] Add negative coverage to prove the new save-adjacent penalty does not hurt normal shelf-tag shapes
- [x] Add negative coverage to prove explicit-size implied-currency filtering does not suppress legitimate compact prices
- [x] Add direct tests for helper-level rules that were added during the Cadbury fix
