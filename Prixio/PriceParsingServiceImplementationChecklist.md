# PriceParsingService Shipping Checklist

The parser feature build is no longer the main problem.

What remains is the work that decides whether this is a clever demo or a reliable product:

1. proving it
2. measuring it
3. learning from it after release
4. cleaning up the app and codebase so the whole scan pipeline feels shippable

This file is now the active checklist for that final stretch.

## Workstreams

### 1. Proof, Measurement, And Learning After Release
Status: Future follow-up

Goal:
- Make parser quality observable and defensible before and after release

Why this matters:
- The parser now has enough functionality to be dangerous in both directions
- It can succeed quietly, but it can also fail plausibly
- Shipping without proof loops means bugs will arrive as anecdotes instead of evidence

Future to-do list:
- Add more truly captured real-world OCR fixtures beyond the current realistic synthetic set
- Expand the evaluation corpus as new failure patterns appear in actual usage
- Revisit parser thresholds and review-state behavior using real saved scan metadata after release
- Decide what product reporting or dashboarding should consume persisted parser review metadata
- Use post-release evidence to decide whether additional Foundation Models coverage is justified
- Promote the current ship-gate suite if future regressions show it is too small
- Periodically refresh the “good enough” release bar based on real parser error patterns instead of pre-release assumptions

How to use this later:
- Treat this section as a future-learning backlog, not active feature work
- Only reopen parser implementation if field evidence, QA review, or new captured fixtures show a real gap
- Prefer evidence-driven changes over speculative heuristic growth

### 2. App And Code Cleanup For Shipping
Status: Wrapped for now

Goal:
- Tighten the codebase so it looks and behaves like release software instead of an active feature branch

Why this matters:
- Shipping quality is not just parser accuracy
- Dead code, stale TODOs, one-off debug paths, and leftover implementation comments make releases harder to trust and harder to maintain

Future to-do list:
- Revisit parser-facing cleanup only if new shipping debt appears during later features
- Keep an eye on parser-related warnings, dead helper seams, and temporary release scaffolding as the app grows
- Reopen this area only if future changes make the parser path noisy or hard to maintain again

## Recommended Execution Order

1. Add more captured OCR fixtures when real scans expose new parser gaps
2. Review persisted parser metadata after real usage starts accumulating
3. Revisit thresholds, review-state behavior, and FM escalation only with evidence
4. Reopen cleanup work only if new code growth creates real maintenance debt

## Current Risks

- Real-world OCR always contains more edge cases than the current fixture set
- Future parser changes could reintroduce noise if they are not kept evidence-driven

## Execution Rule

For each remaining item:
- make the smallest change that closes a real shipping gap
- prefer measurement and observability before more heuristics
- keep parser behavior stable unless evidence says otherwise
- run diagnostics
- run targeted tests when the environment allows it
- run a full build
- update this file and `Journal.md` with the real outcome
