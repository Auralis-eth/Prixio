# PriceParsingService Shipping Checklist

The parser feature build is no longer the main problem.

What remains is the work that decides whether this is a clever demo or a reliable product:

1. proving it
2. measuring it
3. learning from it after release
4. cleaning up the app and codebase so the whole scan pipeline feels shippable

This file is now the active checklist for that final stretch.

## Status

Core parser pipeline status:
- Implemented
- Build-valid
- Review-state integration landed in the scan flow

What is still not fully done:
- Clean, repeatable parser test execution from the current assistant/Xcode harness
- Broader evaluation discipline beyond targeted unit-style fixtures
- Post-save observability for parser uncertainty and assisted parsing
- General app/code cleanup needed to make the project feel production-ready instead of feature-complete

## Workstreams

### 1. Proof, Measurement, And Learning After Release
Status: Active

Goal:
- Make parser quality observable and defensible before and after release

Why this matters:
- The parser now has enough functionality to be dangerous in both directions
- It can succeed quietly, but it can also fail plausibly
- Shipping without proof loops means bugs will arrive as anecdotes instead of evidence

Checklist:
- [ ] Make targeted parser tests run cleanly and repeatably from the current environment
- [ ] Define a small “ship gate” parser suite that must pass before release
- [ ] Add more real captured OCR fixtures, not just synthetic shelf-tag inputs
- [ ] Group fixtures by failure mode: competing prices, multi-product scans, sparse OCR, deposit-heavy tags, flyer noise, noisy branded text
- [ ] Add an evaluation pass that reports parser outcomes across the fixture set instead of only green/red test results
- [ ] Decide which parser outputs matter most to score explicitly:
  - price
  - unit
  - quantity
  - item name
  - review severity
  - Foundation Models usage
- [ ] Add lightweight parser observability so real-world scans can be audited after release
- [ ] Capture review state and severe ambiguity counts so product decisions can be based on real scan behavior
- [ ] Decide whether saved entries should persist parser review metadata for later QA and analytics
- [ ] Define what “good enough to ship” means numerically or operationally, not just intuitively

Definition of done:
- Parser quality can be described with evidence, not vibes
- We have a reliable pre-release validation loop
- We have a concrete way to learn from parser behavior after release

### 2. App And Code Cleanup For Shipping
Status: Complete

Goal:
- Tighten the codebase so it looks and behaves like release software instead of an active feature branch

Why this matters:
- Shipping quality is not just parser accuracy
- Dead code, stale TODOs, one-off debug paths, and leftover implementation comments make releases harder to trust and harder to maintain

Checklist:
- [x] Look for unused parser code, stale helpers, and dead branches left behind by the refactor
- [x] Remove or rewrite development comments, implementation breadcrumbs, and stale TODO-style notes that should not ship as-is
- [x] Audit parser-facing models for fields that are no longer used or no longer pull their weight
- [x] Check for duplicated logic or constants that should be consolidated before release
- [x] Review parser type and helper names for anything that still reflects temporary refactor language instead of stable ownership
- [x] Remove debug-only or one-off verification seams that are no longer earning their keep outside test support
- [x] Check test helpers and `#if DEBUG` entry points to make sure they are intentional and minimal
- [x] Review the scan flow for obvious release rough edges caused by parser integration changes
- [x] Confirm there are no parser-related build warnings, lint issues, or obvious cleanup debt in touched files
- [x] Run a final parser-focused readability cleanup pass without changing behavior
- [x] Build the full project after cleanup changes

Completed in this pass:
- Audited the parser-adjacent app layer for obvious dead imports and stale cleanup debt
- Kept the intentional `#if DEBUG` parser test seams in place, since they are still actively used by the parser test suite and are earning their keep
- Removed an actually unused `MapKit` import from `ScanViewModel`
- Standardized parser-related test files onto a consistent `@MainActor` context to stop Swift 6 actor-isolation warnings from polluting release validation
- Updated `StoreDetectionService` off deprecated `placemark.location` usage and made store-candidate id fallback deterministic when MapKit does not supply an identifier
- Tightened the new review-metadata mapping so it no longer emits actor-isolation warnings during build
- `BuildProject` succeeds after the cleanup pass
- Current build log warning count is now zero

Result:
- This workstream is complete for shipping purposes
- Remaining cleanup from here is optional refinement, not open ship-state debt

Definition of done:
- The parser-related code no longer reads like an in-progress migration
- Obvious dead code and stale development artifacts are gone
- The codebase is clean enough to support release and post-release fixes without unnecessary noise

## Recommended Execution Order

1. Stabilize targeted parser test execution
2. Define the ship-gate parser suite
3. Expand real-world fixture coverage and add evaluation reporting
4. Decide persistence and observability for parser review metadata
5. Finish scan-flow and confirmation-flow cleanup
6. Run final build and release-readiness review

## Current Risks

- Test harness instability still weakens confidence in targeted validation
- Review metadata is visible in the scan flow but not yet persisted for long-term learning
- Real-world OCR always contains more edge cases than the current fixture set
- The app is closer to shippable than before, but still needs a deliberate final cleanup pass

## Execution Rule

For each remaining item:
- make the smallest change that closes a real shipping gap
- prefer measurement and observability before more heuristics
- keep parser behavior stable unless evidence says otherwise
- run diagnostics
- run targeted tests when the environment allows it
- run a full build
- update this file and `Journal.md` with the real outcome
