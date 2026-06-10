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

### 5. Compare And Shopping Post-MVP Polish
Status: Deferred

The core Compare and Shopping List flows now exist, but a few deliberate MVP cuts remain:

- Compare item detail is delete-only; entry editing is still deferred
- Shopping List supports one visible default list even though the data model is multi-list-ready
- Shopping List row distance is not yet surfaced end to end
- the scanner prefill loop is wired, but broader trip-plan breakdown UI is still deferred

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
