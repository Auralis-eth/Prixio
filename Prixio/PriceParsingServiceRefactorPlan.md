# PriceParsingService Refactor Plan

This document is the execution plan for refactoring `Prixio/Scanning/Price/PriceParsingService.swift` after the parser feature push.

The parser behavior is already in a good place. The point of this plan is not to change what the parser *does*. The point is to make the code easier to reason about, easier to test, and safer to extend before the next Foundation Models rollout work.

## Refactor Goals

1. Preserve current parser behavior.
2. Reduce the mental load of working in `PriceParsingService.swift`.
3. Create cleaner seams for:
   - snapshot preparation
   - candidate extraction and ranking
   - item-name extraction
   - quantity inference
   - confidence assembly
   - assisted/Foundation Models flow
4. Make prompt construction for assisted parsing leaner and easier to evolve.
5. Keep regression risk low by moving one concern at a time.

## Status

Implementation complete.

The parser has now been split into the planned `Parsing/` subfolder, with `PriceParsingService.swift` reduced to orchestration, shared parser types/constants, and test helper entry points.

Files added by the refactor:
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
- `Prixio/Scanning/Price/Parsing/PriceCandidateScorer.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingUnitResolver.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingItemNameResolver.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingAssistedExtraction.swift`

## Working Decisions

These decisions are now fixed for the refactor unless the team explicitly changes them later:

1. Delivery style
- Implement the refactor as multiple small ticket-sized passes, not one large rewrite.

2. Folder structure
- Move extracted parser code into a dedicated subfolder:
  - `Prixio/Scanning/Price/Parsing/`

3. Foundation Models placement
- Move assisted/Foundation Models code into a separate file during the refactor.
- Do not leave the FM path embedded inside the main service once the extracted seam exists.

## Non-Goals

- Do not redesign parser heuristics during the refactor.
- Do not expand Foundation Models responsibilities during the refactor.
- Do not change UI behavior during the refactor.
- Do not rewrite tests just to match a new file layout unless behavior requires it.

## Refactor Strategy

The safest approach is a staged extraction, not a rewrite.

Treat the existing file like a crowded garage that already contains working machinery. We are not replacing the machinery. We are labeling shelves, moving tools into drawers, and making sure the chainsaw does not live next to the cereal.

Each ticket below should:
- make one structural move
- preserve behavior
- keep the project building
- keep parser tests green when the environment allows them

## Proposed Target Structure

The exact names can shift slightly if the code suggests better boundaries, but the architecture should roughly land here:

- `PriceParsingService.swift`
  - public orchestration entry point
  - top-level parser flow
  - escalation boundary into assisted parsing

- `Parsing/PriceParsingSnapshotBuilder.swift`
  - supported-line filtering
  - reading-order sorting
  - spatial grouping
  - fallback ladder
  - normalization pipeline
  - snapshot assembly

- `Parsing/PriceCandidateScorer.swift`
  - candidate extraction helpers if still local to parsing
  - candidate ranking logic
  - competing-candidate detection helpers

- `Parsing/PriceParsingUnitResolver.swift`
  - unit detection
  - quantity detection
  - quantity inference from promo and pack notation

- `Parsing/PriceParsingItemNameResolver.swift`
  - item-name candidate scoring
  - product-line selection

- `Parsing/PriceParsingConfidenceResolver.swift`
  - ambiguity penalties
  - heuristic confidence assembly
  - merge-confidence helpers for assisted parsing

- `Parsing/PriceParsingAssistedExtraction.swift`
  - `@Generable` response types
  - prompt models
  - prompt builder
  - `LanguageModelSession` call
  - merge policy for assisted results

The goal is to land on separate files in the `Parsing/` subfolder. If one intermediate pass temporarily uses same-file private namespaces while extracting behavior safely, that is acceptable, but the end state should still be file-based ownership in the subfolder.

## Dependency Rules

These rules matter more than the filenames:

1. Snapshot building should not know about UI or persistence.
2. Item-name extraction should not know how Foundation Models work.
3. Confidence assembly should consume parser outputs and ambiguity, not recreate parsing logic.
4. Assisted parsing should consume prepared context, not reach back into raw OCR plumbing.
5. Shared regex/constants should live where ownership is obvious, not in a random dumping ground.

## Execution Order

Do the refactor in this order:

1. Snapshot builder extraction
2. Candidate scoring extraction
3. Unit and quantity extraction
4. Item-name extraction
5. Confidence assembly extraction
6. Assisted/Foundation Models extraction
7. Constant cleanup and naming pass
8. Final test/documentation pass

This order works because it moves the deterministic pipeline first, then the assisted path last. That reduces the chance that prompt construction or merge logic gets broken while the deterministic seams are still shifting.

## Delivery Model

This refactor should be delivered as multiple small structural passes.

Preferred implementation rhythm:
- one ticket at a time
- build after every ticket
- validate touched parser tests when the environment allows
- avoid bundling unrelated structural moves into one change

Why this is the right model here:
- `PriceParsingService.swift` already works, so the main risk is regression, not missing functionality
- small passes make it easier to isolate structural mistakes from heuristic mistakes
- the Foundation Models path will be safer to move after deterministic seams have settled

## Ticket Backlog

### Ticket 1: Baseline the current parser before moving code

Goal:
- Create a clear pre-refactor baseline for behavior and touched areas.

Tasks:
- Read `PriceParsingService.swift` top to bottom and map concerns into rough sections.
- Record which tests currently cover:
  - spatial grouping
  - ambiguity
  - normalization
  - item-name extraction
  - quantity inference
  - assisted merge behavior
- Capture the current file diagnostics and build status.
- Add a short “refactor baseline” note to `Journal.md`.

Definition of done:
- We have a written baseline of what behavior must not move.
- We know which tests guard which parser phase.

Risk:
- Low.

### Ticket 2: Extract snapshot construction into a dedicated builder seam

Goal:
- Move snapshot preparation out of the orchestration path without changing behavior.

Scope:
- `buildHeuristicSnapshot(from:)`
- supported-line filtering
- reading-order sorting
- spatial grouping
- fallback ladder
- normalization application
- snapshot field assembly

Tasks:
- Create the `Prixio/Scanning/Price/Parsing/` subfolder if it does not already exist.
- Introduce a snapshot builder type or same-file private namespace.
- Move the implementation of `buildHeuristicSnapshot(from:)` into that builder.
- Keep `PriceParsingService.extract(from:)` as the orchestration entry point.
- Preserve the `HeuristicExtractionSnapshot` type unless the refactor naturally suggests a safer equivalent.

Definition of done:
- The high-level parser flow reads like orchestration, not plumbing.
- Snapshot-building helpers are grouped together and no longer scattered.
- The extracted snapshot code lives in `Parsing/PriceParsingSnapshotBuilder.swift` by the end of the ticket or the immediately following cleanup pass.

Risk:
- Medium, because many later phases depend on snapshot output.

### Ticket 3: Extract price candidate extraction and ranking

Goal:
- Isolate candidate work so price logic is not mixed with unrelated parser phases.

Scope:
- candidate extraction
- inline candidate parsing
- candidate ranking
- competing-price detection

Tasks:
- Move candidate parsing helpers into a dedicated scorer/parser seam.
- Keep the public shape of `PriceCandidate` unchanged unless forced by the refactor.
- Keep ranking rules identical during extraction.
- Preserve the top-candidate semantics currently used by the rest of the parser.

Definition of done:
- Price candidate logic is owned by one coherent section or type.
- It is obvious where to change ranking vs extraction in future work.
- The extracted code lives in `Parsing/PriceCandidateScorer.swift`.

Risk:
- Medium.

### Ticket 4: Extract unit and quantity resolution into one owned area

Goal:
- Group all unit and quantity logic under one coherent resolver.

Scope:
- unit detection
- base quantity detection
- pack-count inference
- promo quantity inference
- quantity context selection around the chosen candidate

Tasks:
- Move unit and quantity helpers into a dedicated resolver.
- Keep the behavior from Steps 5 and 7 unchanged.
- Make the boundary explicit:
  - inputs: observations, price candidates, fallback text
  - outputs: detected unit, resolved quantity

Definition of done:
- Unit and quantity logic are no longer split across unrelated helper sections.
- Future promo work has a single place to land.
- The extracted code lives in `Parsing/PriceParsingUnitResolver.swift`.

Risk:
- Medium.

### Ticket 5: Extract item-name resolution into its own resolver

Goal:
- Separate product-name scoring from the rest of the parser.

Scope:
- item-name candidate filtering
- item-name scoring
- SKU/receipt/promo rejection helpers related to name selection

Tasks:
- Move `extractItemNameHint(...)` and its related helpers into an item-name resolver.
- Keep the current brand/size-preserving behavior intact.
- Keep the scoring inputs explicit and narrow.

Definition of done:
- Item-name extraction is understandable without paging through unit or candidate code.
- The extracted code lives in `Parsing/PriceParsingItemNameResolver.swift`.

Risk:
- Medium.

### Ticket 6: Extract confidence and ambiguity resolution

Goal:
- Separate “what the parser found” from “how sure the parser is.”

Scope:
- ambiguity analysis
- heuristic confidence assembly
- confidence penalties
- merge-confidence helpers for assisted output

Tasks:
- Move `analyzeAmbiguity(in:)`, `assembleHeuristicConfidence(...)`, `confidencePenalty(...)`, and merge-confidence helpers into a dedicated resolver area.
- Keep ambiguity definitions stable during extraction.
- Ensure `makeOCRResult(from:)` reads like final assembly, not a decision tree.

Definition of done:
- Confidence logic is easy to inspect independently from extraction heuristics.
- The extracted code lives in `Parsing/PriceParsingConfidenceResolver.swift`.

Risk:
- Medium.

### Ticket 7: Extract assisted/Foundation Models flow into a dedicated seam

Goal:
- Keep the FM path explicit, small, and easy to evolve.

Scope:
- `@Generable` response types
- prompt context types
- prompt builder
- model call
- assisted merge logic

Tasks:
- Move assisted extraction types and helpers out of the main deterministic parser section.
- Keep the current second-pass behavior intact.
- Make it obvious which data gets sent to the model and why.
- Ensure assisted merge policy stays close to assisted extraction, not mixed back into deterministic snapshot logic.
- Land the assisted path in a dedicated file instead of leaving it embedded in `PriceParsingService.swift`.

Definition of done:
- Foundation Models code is isolated enough that future rollout work does not require spelunking through the full parser.
- The extracted code lives in `Parsing/PriceParsingAssistedExtraction.swift`.

Risk:
- Medium-high, because it touches prompt and merge behavior together.

### Ticket 8: Consolidate constants, regexes, and naming

Goal:
- Clean up the global top-of-file constant sprawl.

Scope:
- regex constants
- marker/token lists
- naming consistency for helper methods and result types

Tasks:
- Group constants by ownership:
  - price parsing
  - unit/quantity
  - item-name filtering
  - receipt/noise detection
  - assisted parsing
- Rename helpers only where the new names materially improve clarity.
- Avoid churn-only renames that create noise without better structure.

Definition of done:
- Constants are no longer an unstructured wall at the top of the file.

Risk:
- Low to medium.

### Ticket 9: Add a parser-internal code map comment or mini-doc

Goal:
- Leave the parser easier for the next person to navigate.

Tasks:
- Add a short top-level comment in `PriceParsingService.swift` describing the flow:
  - snapshot
  - ambiguity
  - heuristic result
  - assisted escalation
  - merge
- Optionally add one short comment per extracted helper type if needed.

Definition of done:
- A new reader can locate the major parser phases quickly.

Risk:
- Low.

### Ticket 10: Final regression and documentation pass

Goal:
- Lock the refactor down and update project memory.

Tasks:
- Run file diagnostics on touched parser files.
- Run targeted parser tests when the environment allows.
- Run a full build.
- Update `PriceParsingServiceImplementationChecklist.md`.
- Update `Journal.md` with refactor lessons and any gotchas.

Definition of done:
- Refactor is documented as structural, not behavioral.
- Build still succeeds.
- The next FM rollout phase has a cleaner launch point.

Risk:
- Low.

## Validation Matrix

Use this matrix while refactoring:

- `PriceParsingServiceSpatialGroupingTests`
  - guards snapshot grouping and fallback behavior

- `PriceParsingServiceAmbiguityTests`
  - guards ranking, ambiguity detection, and confidence outcomes

- `PriceParsingServiceDataSanitation`
  - guards normalization, unit/item/quantity behavior

- `PriceParsingServiceFoundationModelAssistTests`
  - guards assisted merge behavior

- `ConsolidateObservationsTests`
  - guards observation consolidation behavior

## Suggested Execution Notes

- Do not move everything in one pass.
- Prefer extract-and-delegate over rewrite-and-replace.
- Keep public behavior stable first, then clean naming second.
- If a move forces heuristic changes, split that into a separate ticket.
- If a helper has too many parameters after extraction, that is a sign it needs an owned context type.

## Open Questions

The main structural questions are now answered. Remaining questions are execution-level only:

1. Should each ticket land as its own commit, or should a few tightly related structural tickets be batched together?
2. Should shared parser-internal types remain nested under `PriceParsingService`, or should some be promoted to file-private top-level types once extracted?
3. Do we want a final umbrella cleanup pass for naming/style after all extractions are done, or should naming be normalized inside each ticket?

## Recommended First Ticket

Start with `Ticket 2: Extract snapshot construction into a dedicated builder seam`.

Why:
- It creates the cleanest foundation for every later extraction.
- It reduces the size of the orchestration path immediately.
- It also gives the upcoming Foundation Models work a cleaner snapshot object and smaller prompt-construction surface.
