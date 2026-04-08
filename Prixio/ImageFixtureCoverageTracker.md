# Image Fixture Coverage Tracker

## Goal
Tighten `PrixioTests/ImageFixtureParsingTests.swift` so every real image fixture has a strict parser contract, then add captured-OCR tests for the real failure modes those fixtures expose.

## Status Legend
- `[ ]` not started
- `[-]` in progress
- `[x]` done
- `[!]` blocked

## Current Snapshot
- All live fixtures now have a strict contract entry in code.
- `IMG_0483` has a user-confirmed winning tag: `Comp Butter Salted`, `Product of Canada`, `$5.99`.
- Loose batch tests have been removed.
- Captured OCR coverage now includes Cadbury, mini cucumber, banana wrong-winner, and sparse grower cases.

## V2 Failure-Class Map
- `promoOwnership`
  - `Screenshot 2026-04-02 at 3.53.44 PM`
  - `IMG_0480`
- `depositNoise`
  - `IMG_0482`
- `flyerNoise`
  - `IMG_0476`
  - `IMG_0478`
- `multiProductOwnership`
  - `IMG_0472`
  - `IMG_0483`
- `compactNumericPLUTrap`
  - `IMG_0477`
- `sparseOCR`
  - `IMG_0479`

## Obvious Missing Fixture Classes
- bilingual promo card with side-by-side regular and member prices
- severe glare / washout shelf tag
- rotated or perspective-skewed produce sign
- dense beverage shelf edge with repeated deposit lines
- split title across three lines with package size on a fourth line

## Small Steps

### 1. Lock the last missing live-image contract
- `[x]` Get the exact OCR output and parser result for `IMG_0483`.
- `[x]` Human inspection resolved the intended winning tag:
  - `Comp Butter Salted`, `Product of Canada`, `$5.99`
- `[x]` Record:
  - expected item name
  - expected price
  - expected unit
  - expected quantity
  - expected `review.state`
  - expected `review.usedFoundationModel`
  - optional exact OCR lines if stable
  - optional exact price candidates / supporting lines if stable
- `[x]` Sanity-check whether `IMG_0483` is a multi-product or wrong-winner case worth mirroring in captured-OCR fixtures.

### 2. Replace loose live-fixture tests with strict contracts
- `[x]` Expand `strictFixtureContracts` in `PrixioTests/ImageFixtureParsingTests.swift` to include:
  - `Screenshot 2026-04-02 at 3.53.44 PM`
  - `IMG_0472`
  - `IMG_0473`
  - `IMG_0474`
  - `IMG_0475`
  - `IMG_0476`
  - `IMG_0477`
  - `IMG_0478`
  - `IMG_0479`
  - `IMG_0480`
  - `IMG_0482`
  - `IMG_0483`
- `[x]` For each contract, assert the stable fields:
  - item name
  - price
  - unit
  - quantity
  - `review.state`
  - `review.usedFoundationModel`
- `[x]` Add exact OCR line assertions only where OCR output has proven stable.
- `[x]` Add exact price candidate / supporting line assertions only where they are stable enough to be useful.
- `[x]` Delete the old batch tests:
  - `fixtureBatchA/B/CLoadsAndProducesOCR`
  - `fixtureBatchA/B/CProducesReviewableParse`
  - `cadburyShelfTagImageFixtureStillProducesAReviewableParse`

### 3. Add captured-OCR fixtures for important real failures
- `[x]` Review the live-image contracts and choose the top failure modes that deserve exact captured coverage.
- `[x]` Add new captured fixtures to `PrixioTests/CapturedOCRFixtures.swift` for the highest-value cases.
- `[ ]` Prioritize cases like:
  - multi-product ambiguity
  - wrong winning price candidate
  - wrong winning item name
  - severe packaging noise
  - sparse OCR that still should preserve shelf-price evidence

### 4. Add exact captured-OCR tests
- `[x]` Extend `PrixioTests/PriceParsingServiceCapturedOCRTests.swift`.
- `[x]` For each new captured fixture, add exact tests for at least one of:
  - snapshot stage outputs
  - ambiguity contract
  - final parse result
  - assisted merge behavior
  - supporting lines / candidate ordering
- `[x]` Keep these tests focused on the real bug the fixture is meant to pin.

### 5. Update project docs
- `[x]` Add a `Journal.md` entry describing:
  - why loose “reviewable parse” coverage was insufficient
  - what real regressions the strict contracts are meant to catch
  - what captured-OCR fixtures were added and why
  - any gotchas about OCR stability vs exact assertions

### 6. Validate
- `[x]` Run file diagnostics for edited test files.
- `[!]` Run targeted tests for:
  - `ImageFixtureParsingTests`
  - `PriceParsingServiceCapturedOCRTests`
- `[x]` Build the project.
- `[x]` If targeted test execution is flaky again, record exactly what passed, what timed out, and what still needs a rerun.

## Known Blockers
- `[!]` The local MCP/Xcode test runner has been timing out on image-driven probe runs.
- `[ ]` We still need a reliable way to extract the exact `IMG_0483` contract.

## Fastest Paths For Step 1

### Option A: Stay inside this session
- Use a lightweight local OCR path and then patch the strict contract directly.
- Best when the local runner cooperates.

### Option B: Use ChatGPT web / another vision-capable interface
- Give it `IMG_0483.png` and ask for:
  - all visible product/price labels
  - likely winning shelf tag
  - likely OCR lines for the upper-right and lower-left labels
- Then bring that output back here so I can translate it into exact test expectations and finish the code edits.

### Option C: You inspect the image manually in Xcode/Preview
- If you tell me the intended winning tag for `IMG_0483`, I can finish the strict contracts and keep exact OCR assertions minimal for that fixture.

## Completion Log
- `2026-04-02`: Tracker created so the remaining work can be executed as discrete steps instead of one long stalled pass.
- `2026-04-02`: Live image tests converted from loose sanity checks to strict fixture contracts for all real fixtures.
- `2026-04-02`: Added captured-OCR exact tests for banana wrong-winner and sparse grower failure patterns.
- `2026-04-02`: Fixed the butter shelf wrong-focus bug by making focused group scoring reward recoverable price candidates and penalize description-only groups with no usable price.
- `2026-04-02`: Added a captured butter shelf OCR fixture to pin the `Comp Butter Salted` `$5.99` winner over the larger unsalted cluster.
- `2026-04-02`: Xcode diagnostics were clean for edited files and the project build succeeded.
- `2026-04-02`: Targeted test run still timed out in the MCP harness for `ImageFixtureParsingTests/strictLiveFixtureContracts(case:)` plus the two new captured-OCR tests, so those tests need a local rerun in a more reliable runner.
