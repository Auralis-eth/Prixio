# Image Fixture Test Plan

## Goal
Build two real-image fixture tests that exercise the OCR-to-parser pipeline end to end, then pin the intermediate parser stages so regressions are easy to localize.

## Fixture 1
- Shelf tag image that should resolve to `Cadbury Chocolate Mini Eggs`
- Expected winning price: `17.99`

## Fixture 2
- Second real image you want to use as a regression fixture
- Expected item, price, unit, quantity, and review state still need to be written down before implementation

## Phase 1: Prepare The Fixtures
1. Decide where the fixture images will live.
2. Add both images to the `PrixioTests` bundle, not the main app bundle.
3. Use stable, descriptive filenames.
4. Write down the expected final parse result for each image:
   - item name
   - price
   - unit
   - quantity
   - review state
   - whether Foundation Models should be used
5. Confirm the images are oriented correctly so Vision sees the same pixels every run.

## Phase 2: Build Test Infrastructure
1. Add a small test helper to load `UIImage` or `CGImage` fixtures from the test bundle.
2. Add a helper that runs the same Vision OCR request used by production code.
3. Add a helper that converts `VNRecognizedTextObservation` into `[OCRTextObservation]`.
4. Keep the OCR helper output inspectable so failed tests can print raw lines and bounding boxes.
5. Avoid mocking OCR in the end-to-end fixture tests. We want real Vision output here.

## Phase 3: Capture Baseline OCR Output
1. Run OCR against image fixture 1.
2. Save the raw recognized lines, confidences, and bounding boxes from one known-good run.
3. Repeat for image fixture 2.
4. Review the OCR output manually and note obvious garbage lines, split name fragments, and competing prices.
5. Use this captured output to decide whether additional parser-stage assertions are realistic and stable.

## Phase 4: Add End-To-End Fixture Tests
1. Create a new parser fixture test file in `PrixioTests`.
2. Add one test per image that runs:
   - image fixture load
   - Vision OCR
   - `PriceParsingService.extract(from:)`
3. Assert the final result for each image:
   - `itemNameHint`
   - `price`
   - `unit`
   - `quantity`
   - `review.state`
4. Assert that the top `priceCandidates.first` matches the expected winning price.
5. Assert that `supportingLines` contain the expected shelf-tag evidence and not just packaging noise.

## Phase 5: Add Parser Stage Tests From Captured OCR
1. Take the OCR observations captured from fixture 1 and use them in parser-only tests.
2. Add assertions for snapshot stages:
   - supported observations
   - focused/cleaned observations
   - normalized observations
   - consolidated observations
3. Assert the candidate list shape:
   - expected candidate count
   - expected winning candidate
   - source text for the winner
4. Assert the item-name resolver output before any UI formatting.
5. Repeat for fixture 2.

## Phase 6: Add Failure Localization Tests
1. Add a test that only validates OCR fixture loading.
2. Add a test that only validates Vision OCR returns non-empty observations for each image.
3. Add a test that only validates `PriceParsingSnapshotBuilder` on captured OCR observations.
4. Add a test that only validates `PriceParsingItemNameResolver`.
5. Add a test that only validates `PriceCandidateScorer`.
6. Add a test that only validates final `OCRResult`.

## Phase 7: Make Debugging Cheap
1. Keep a helper that prints OCR lines with bounding boxes in a grep-friendly format.
2. Keep a helper that prints parser stages in order:
   - raw OCR
   - spatial groups
   - cleaned
   - normalized
   - consolidated
   - candidates
   - final result
3. Make sure fixture tests print enough failure context to diagnose the bad stage quickly.
4. Prefer explicit expected values over snapshot-text blobs for core assertions.

## Phase 8: Stabilize The Contract
1. Decide which Vision OCR details are stable enough to assert directly.
2. Avoid over-asserting raw OCR ordering if Vision occasionally reorders equivalent lines.
3. Be stricter on parser outputs than on raw OCR text.
4. If OCR output varies slightly, freeze the parser-stage tests against captured `[OCRTextObservation]` fixtures and keep only a lighter end-to-end Vision smoke test.

## Phase 9: Integrate With Existing Suites
1. Decide whether the new image tests belong in:
   - `ParserEvaluationTests`
   - a new `ImageFixtureParsingTests`
2. Keep true ship-gate coverage small.
3. Put heavier Vision-backed fixture tests in a non-ship-gate suite if runtime becomes annoying.
4. Reuse the existing parser helper seams already exposed under `#if DEBUG`.

## Phase 10: Maintenance Rules
1. Every time a real-world parser bug is found, prefer adding:
   - one image fixture test if the failure starts at OCR or layout geometry
   - one parser-only OCR observation test if the failure starts after OCR
2. Never update expected outputs without reviewing the raw OCR and candidate list.
3. If a fixture starts failing after an iOS/Xcode update, first determine whether Vision changed or the parser regressed.
4. Keep the fixture list small and high-signal. Two or three brutal real images beat twenty vague ones.

## Immediate Next Steps
1. Run the debug build with your Cadbury image and send the console output.
2. Confirm the exact expected final result for image fixture 2.
3. Add both images to the `PrixioTests` bundle.
4. Implement the fixture loader and the first end-to-end Vision test.
5. Freeze captured OCR observations into parser-stage regression tests.
