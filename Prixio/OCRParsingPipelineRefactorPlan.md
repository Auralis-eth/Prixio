# OCR Parsing Pipeline Refactor Plan

This document is the concrete execution plan for the next parser-quality push in Prixio.

The trigger for this plan is simple: the current parser is good enough to expose its own limits clearly. We now have real and captured OCR fixtures, stable parser seams, and enough war stories to stop guessing. The next step is not "add more regex." The next step is to make the OCR-to-parse pipeline more explicit, more spatially aware, and less dependent on any single top-1 OCR guess.

This plan borrows the useful ideas from systems like EasyOCR, Tesseract, and PaddleOCR without turning Prixio into a general-purpose OCR framework:
- preserve structured OCR evidence
- treat layout and segmentation as first-class inputs
- separate recognition confidence from parse confidence
- classify the scene before trusting the parse
- keep the deterministic parser strong before asking Foundation Models to help

## Status

V1 implemented.

This document is now a record of the first parser pipeline expansion, not the active proposal for new work.

Verification status:
- targeted parser suites passed during implementation
- the full local suite later passed end to end
- `Journal.md` was updated throughout the rollout

The active next-step planning now lives in:
- [OCRParsingPipelineV2Plan.md](/Users/danielbell/Dev/Prixio/Prixio/OCRParsingPipelineV2Plan.md)
- [OCRParsingPipelineV2Checklist.md](/Users/danielbell/Dev/Prixio/Prixio/OCRParsingPipelineV2Checklist.md)

## V1 Outcome Summary

The first parser pipeline refactor landed in pragmatic form.

What shipped:
- a real `OCRService` seam with bounded preprocessing and fallback OCR behavior
- explicit scene classification
- first-class evidence clusters
- stronger price ownership scoring
- cluster-aware item-name selection
- clearer OCR-vs-parse confidence behavior
- tighter Foundation Models hand-off rules
- alternate OCR hypothesis preservation for risky numeric tokens
- stronger captured-fixture coverage and less brittle live OCR contracts

What v1 intentionally left shallow:
- full perspective rectification and richer preprocessing benchmarks
- stronger cross-column cluster ownership
- earlier price-kind modeling
- canonical item-name repair beyond heuristic line selection
- richer parser diagnostics and benchmark reporting

## V1 Architectural Takeaway

The biggest change in v1 was not "more OCR." It was better traffic control.

The pipeline now has clearer contracts:
- OCR can be preprocessed and retried in a bounded way before parsing
- the scene gets classified before downstream ambiguity logic has to guess
- prices can be judged with more local ownership context
- evidence can be grouped into clusters instead of drifting around as loose lines
- Foundation Models get narrower, better-scoped work

That means v2 should deepen these same ideas instead of reopening the whole parser shape.

## Why This Refactor Exists

The current pipeline already does several hard things well:
- preserves OCR line geometry
- performs spatial grouping
- extracts and ranks price candidates
- resolves item names, units, quantities, and review state
- escalates to Foundation Models when the heuristic path looks risky

The remaining problems are not random. They are patterned:
- a plausible but wrong OCR token can win too early
- the parser sometimes treats line text as the main truth and geometry as supporting evidence, when grocery tags often require the reverse
- scene-level ambiguity gets discovered late instead of early
- `supportingLines` can end up reflecting model-selected breadcrumbs instead of a stable evidence contract
- top-1 OCR output is sometimes too brittle for shelf prices, PLUs, and compact size tokens

## Refactor Goals

1. Improve parser correctness on ambiguous shelf tags without replacing Apple Vision.
2. Make scene classification explicit before price and item ranking.
3. Strengthen spatial ownership: a price should have to "belong" to a product cluster.
4. Preserve richer OCR evidence so later stages can recover from bad top-1 text.
5. Keep Foundation Models as an escalation tool, not a crutch for weak deterministic structure.
6. Expand the test suite in ways that localize failures cheaply.

## Non-Goals

- Do not replace Vision OCR with EasyOCR, Tesseract, or PaddleOCR in this phase.
- Do not redesign the app UI around parser internals.
- Do not collapse parser heuristics into an opaque end-to-end model.
- Do not make the pipeline "smart" by hiding uncertainty; the review system should stay honest.

## External Takeaways To Apply

### From EasyOCR
- Preserve per-detection structure instead of flattening too early.
- Keep bounding box, confidence, and raw text available through more of the pipeline.
- Consider keeping alternate OCR interpretations for high-risk tokens such as prices, PLUs, and unit markers.

### From Tesseract
- Segmentation assumptions matter.
- A parser should know whether it is looking at one tag, two tags, promo copy, or noisy junk before interpreting price lines.
- Preprocessing and document shape assumptions are not optional details; they are part of accuracy.

### From PaddleOCR
- Orientation and rectification deserve first-class handling.
- Detection, line construction, recognition, and downstream understanding should stay modular.
- System quality improves when each stage has a narrow contract and measurable output.

## Proposed Target Architecture

The goal is not more files for their own sake. The goal is clearer ownership.

- `Prixio/Scanning/OCR/OCRTextObservation.swift`
  - keep raw recognized text, confidence, and geometry
  - consider adding optional alternate token hypotheses for high-risk numeric OCR

- `Prixio/Scanning/OCR/OCRService.swift`
  - own image preprocessing before Vision runs
  - keep OCR invocation isolated from parser orchestration
  - support multiple OCR-ready image variants when the default pass is weak

- `Prixio/Scanning/Price/PriceParsingService.swift`
  - remain the orchestration boundary
  - own the high-level flow and escalation decisions

- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
  - continue to build the heuristic snapshot
  - expand to include scene classification and evidence-group metadata

- `Prixio/Scanning/Price/Parsing/PriceCandidateScorer.swift`
  - require stronger spatial ownership between candidate prices and product groups
  - score candidates against scene type and local tag membership

- `Prixio/Scanning/Price/Parsing/PriceParsingItemNameResolver.swift`
  - resolve item names within the selected product cluster
  - reduce leakage from descriptive card copy and neighboring product tags

- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
  - separate OCR weakness from parser weakness
  - compute review state using scene-level evidence, not only final field completeness

- `Prixio/Scanning/Price/Parsing/PriceParsingAssistedExtraction.swift`
  - consume prepared cluster and ambiguity context
  - stop asking Foundation Models to compensate for deterministic context we could provide directly

## New Concepts To Introduce

### 1. Scene Classification

Add a lightweight scene classifier before final ranking.

Proposed cases:
- `singleTag`
- `multiTag`
- `promoCard`
- `receiptLike`
- `unclear`

Inputs:
- number of spatial groups
- overlap between descriptive lines and price lines
- count and spread of price candidates
- presence of promo markers
- receipt-like markers

Likely home:
- `PriceParsingSnapshotBuilder`

Why:
- this is the parser equivalent of choosing the right page-segmentation mode
- multi-tag and promo-card scans should not be scored like clean single tags
- `unclear` should be the conservative default until the observed evidence strongly supports a narrower class

### 2. Evidence Clusters

Formalize product-level clusters instead of relying on loose line arrays.

Each cluster should capture:
- observations
- local price candidates
- local item-name candidates
- local unit signals
- local quantity signals
- cluster score
- cluster role hints such as `primaryProduct`, `secondaryProduct`, `promoCopy`, `noise`

Likely home:
- new nested types under `PriceParsingService`
- assembled in `PriceParsingSnapshotBuilder`

Why:
- the parser currently has the ingredients for this but not the explicit contract
- making clusters real simplifies downstream reasoning and tests
- scene classification and cluster structure should be sketched together even if they land in separate implementation phases

### 3. OCR Risk Buckets

Add a small concept for text that is structurally risky even when confidence looks high.

Examples:
- compact numeric prices like `299`, `1799`, `599`
- mixed PLU/price lines like `PLU 4011`
- unit-like fragments such as `/ Kg`
- OCR variants with digit-letter substitution

Use this to:
- preserve alternates where possible
- add scoring penalties when a risky token is the only evidence
- improve review-state honesty

Likely home:
- `PriceParsingSnapshotBuilder`
- `PriceCandidateScorer`
- `PriceParsingConfidenceResolver`

### 4. Stable Evidence Contracts

Clarify what `supportingLines` means.

Proposed rule:
- `supportingLines` should represent the final evidence slice supporting the winning product/result
- it does not need to be identical to every model-selected line index
- live model-path tests should assert stable invariants, not exact breadcrumb ordering, unless the merge input is deterministic

Why:
- this avoids test contracts that accidentally pin model randomness instead of parser correctness

## Implementation Phases

## Phase 1: Image Preprocessing

Goal:
- improve OCR quality before text ever reaches the parser

Why this comes first:
- a better parser cannot recover evidence that OCR never saw
- shelf tags are unusually sensitive to angle, glare, color contrast, and partial perspective distortion
- this is the highest-leverage place to borrow from traditional OCR stacks without replacing Vision

Scope:
- keep Vision as the recognizer
- improve the image handed to Vision
- keep preprocessing modular and measurable
- keep the first implementation tightly time-boxed

Concrete implementation tasks for `OCRService.swift`:
- stop putting the full OCR pipeline directly inside `UIImage.extractOCR()`
- introduce an `OCRService` type that owns:
  - image preprocessing
  - Vision request construction
  - OCR observation extraction
  - parser hand-off
- add an internal preprocessing pipeline that can produce one or more OCR-ready image variants:
  - original image
  - normalized-orientation image
  - high-contrast variant
  - optional grayscale variant
- add a lightweight preprocessing configuration type so experiments stay explicit instead of turning into hidden image mutations
- add a preprocessing result type that records:
  - which variant was used
  - whether orientation normalization ran
  - whether contrast enhancement ran
  - image size used for OCR
- add an explicit seam for perspective rectification:
  - start with a no-op/default implementation if needed
  - allow later injection of rectangle detection and warp logic without rewriting the OCR call site
- add an explicit seam for contrast enhancement:
  - evaluate CLAHE-style contrast improvement or the closest Core Image equivalent available on-device
  - keep it optional and fixture-benchmarked
- run Vision against the default preprocessed image first
- define fallback conditions for trying a secondary variant:
  - very low OCR line count
  - no price-like tokens found
  - confidence distribution far below normal expectations
- keep fallback behavior bounded:
  - no unbounded retry ladder
  - start with a hard maximum of two total OCR passes per image
  - Phase 1 is not complete if it requires more than one fallback variant to look useful
- preserve observation geometry correctly for whichever image variant was recognized
- avoid mixing preprocessing heuristics into parser logic

Supporting tasks around `OCRService.swift`:
- add focused tests for orientation normalization and variant selection behavior where practical
- add fixture-based evaluation notes for which preprocessing variants help or hurt existing images
- add debug logging in `#if DEBUG` so fixture runs can report which OCR variant produced the final observations

Recommended helper seams under `OCRService.swift`:
- `normalizedImageForOCR()`
- `ocrImageVariants()`
- `performVisionOCR(on:)`
- `shouldTrySecondaryOCRVariant(...)`
- `extractTextObservations(from:)`

Candidate implementation building blocks:
- `CIImage` / Core Image for contrast and grayscale transforms
- Vision rectangle detection or platform rectangle utilities for perspective experiments
- `CGImagePropertyOrientation` or equivalent orientation normalization before OCR

Target files:
- `Prixio/Scanning/OCR/OCRService.swift`
- `Prixio/Scanning/OCR/OCRTextObservation.swift`
- `PrixioTests/ImageFixtureParsingTests.swift`
- `PrixioTests/ImageFixtureTestSupport.swift`

Definition of done:
- OCR can run through a documented preprocessing path before Vision
- preprocessing choices are inspectable in debug runs
- the fixture suite can measure whether preprocessing improved or harmed recognition
- the implementation stays within the initial pass budget of one primary pass plus at most one fallback pass

## Phase 2: Baseline And Instrumentation

Goal:
- make current parser decisions easier to inspect before changing behavior

Tasks:
- add a short snapshot debug description for scene type, cluster count, and chosen cluster
- document current ambiguity triggers and where they are calculated
- formalize the `supportingLines` contract for deterministic vs model-assisted paths
- update unstable live model-path tests to assert stable invariants instead of exact breadcrumb arrays
- add or strengthen fixture coverage for:
  - single clean tag
  - multi-tag confusion
  - promo-card text leakage
  - wrong-price compact numeric OCR

Target files:
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingAssistedExtraction.swift`
- `PrixioTests/PriceParsingServiceCapturedOCRTests.swift`
- `PrixioTests/ParserEvaluationTests.swift`

Definition of done:
- current decisions are inspectable without stepping through the whole parser manually
- the test suite no longer pins live model randomness where the contract should only pin stable invariants

## Phase 3: Add Scene Classification

Goal:
- make scene type explicit before price resolution

Tasks:
- introduce a scene classification type
- compute scene classification in the snapshot builder
- expose scene classification in the heuristic snapshot
- use scene classification to influence ambiguity and review-state analysis

Target files:
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
- new tests in `PrixioTests/PriceParsingServiceAmbiguityTests.swift`

Definition of done:
- multi-product and promo-heavy scans stop looking identical to clean single-tag scans at the scoring level

## Phase 4: Promote Product Clusters To First-Class Data

Goal:
- make "this price belongs to this product block" a concrete parser decision

Tasks:
- define a product/evidence cluster type
- associate observations, prices, and text candidates within each cluster
- select a winning cluster before selecting a final price
- keep fallback behavior when the scene is too sparse to cluster confidently

Target files:
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
- `Prixio/Scanning/Price/Parsing/PriceCandidateScorer.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingItemNameResolver.swift`

Definition of done:
- the parser can explain which cluster won and why
- nearby but unrelated prices lose more often

## Phase 5: Tighten Price Ownership And Compact-Price Handling

Goal:
- reduce cases where `299`, `599`, `1799`, or `4011` get interpreted without enough local evidence

Tasks:
- introduce explicit compact-price risk scoring
- penalize candidate prices that are not locally aligned with the winning cluster
- treat PLU-like tokens and price-like tokens as competing interpretations when appropriate
- add tests around compact numeric ambiguities and save-adjacent price fragments

Target files:
- `Prixio/Scanning/Price/Parsing/PriceCandidateScorer.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
- `PrixioTests/PriceParsingServiceCapturedOCRTests.swift`
- `PrixioTests/ParserShipGateTests.swift`

Definition of done:
- compact numeric values stop winning on strength of shape alone

## Phase 6: Resolve Item Names Inside The Winning Cluster

Goal:
- stop item-name assembly from reaching too far outside the chosen product evidence

Tasks:
- restrict item-name candidate assembly to the winning cluster by default
- allow carefully-scored secondary fragment merging only when overlap or size/pack evidence justifies it
- continue filtering marketing copy and receipt-like language

Target files:
- `Prixio/Scanning/Price/Parsing/PriceParsingItemNameResolver.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
- `PrixioTests/ImageFixtureParsingTests.swift`
- `PrixioTests/PriceParsingServiceCapturedOCRTests.swift`

Definition of done:
- descriptive copy helps context without becoming product identity

## Phase 7: Separate OCR Confidence From Parse Confidence

Goal:
- make the final confidence and review state more honest

Tasks:
- distinguish:
  - OCR quality problems
  - parser ambiguity problems
  - scene complexity problems
- use scene type, cluster clarity, and risky-token dependence in confidence assembly
- review whether new review issues should be added or whether current issues can represent the signals cleanly

Target files:
- `Prixio/Scanning/OCR/OCRResult.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
- `PrixioTests/OCRReviewStateTests.swift`

Definition of done:
- confidence no longer means "the parser filled fields"
- review recommendations map better to actual risk

## Phase 8: Improve The Foundation Models Hand-Off

Goal:
- ask the model narrower, better questions

Tasks:
- pass scene type and candidate-cluster context into the assisted prompt
- prefer cluster-scoped line indexes over raw global line selection
- keep FM merge behavior deterministic where inputs are deterministic
- update tests so exact evidence arrays are only pinned in deterministic merge cases
- add an explicit guardrail that skips FM escalation when the heuristic path already produced a complete result with high cluster confidence and no severe ambiguity

Target files:
- `Prixio/Scanning/Price/Parsing/PriceParsingAssistedExtraction.swift`
- `PrixioTests/PriceParsingServiceFoundationModelAssistTests.swift`
- `PrixioTests/PriceParsingServiceCapturedOCRTests.swift`

Definition of done:
- the model works as a tie-breaker inside a structured search space instead of a rescue rope for fuzzy context
- at least one targeted test proves the FM path is not invoked for a high-confidence, single-cluster heuristic result

## Phase 9: Optional OCR Enrichment Experiments

Goal:
- explore richer OCR evidence without committing to a production OCR engine swap

Tasks:
- evaluate whether Vision can expose alternate candidates useful for high-risk tokens
- if not, prototype parser-side alternates for compact numeric price recovery
- keep this work behind test-only seams until it proves value

Target files:
- `Prixio/Scanning/OCR/OCRService.swift`
- `Prixio/Scanning/OCR/OCRTextObservation.swift`
- test-only helpers as needed

Definition of done:
- we have evidence for or against alternate-token preservation

## Test Strategy

This refactor should stay evidence-driven.

### Must Keep
- live image fixture coverage in `ImageFixtureParsingTests.swift`
- captured OCR parser-stage coverage in `PriceParsingServiceCapturedOCRTests.swift`
- ship-gate sanity checks in `ParserShipGateTests.swift`

### Must Add
- scene-classification tests
- cluster-selection tests
- compact-price ambiguity tests
- confidence/review-state tests tied to scene complexity
- deterministic merge tests for cluster-scoped FM behavior

### Test Rule
- if a behavior depends on live OCR or live model output, assert stable invariants
- if a behavior is deterministic from frozen inputs, assert exact contracts

## Delivery Order

Implement in this order:

1. Image preprocessing
2. Baseline and instrumentation
3. Scene classification
4. Evidence clusters
5. Price ownership and compact-price handling
6. Cluster-scoped item naming
7. Confidence/review-state separation
8. Foundation Models hand-off cleanup
9. Optional OCR enrichment experiments

This order matters. Better OCR input should land before parser-quality judgments, and scene/cluster structure should get stronger before touching the FM path, or the model layer will keep absorbing problems that belong in deterministic parsing.

## Risks

- Overfitting to current fixtures instead of general shelf-tag behavior
- Detection:
  review failures by scene type and regularly add fixtures from newly observed failure classes
- Making clustering too rigid for sparse scans
- Detection:
  keep sparse-fixture coverage and verify that fallback behavior still produces reviewable results instead of collapsing to nil fields
- Adding too many new abstractions before the tests prove they help
- Detection:
  each phase should land with targeted tests and measurable debug output before the next abstraction is added
- Confusing review-state changes with parser-quality improvements when the difference is only stricter honesty
- Detection:
  compare field-level correctness and review-state distribution separately in fixture evaluation

## Execution Rules

For each phase:
- update tests first or in the same change
- keep changes tight to the phase
- prefer captured OCR fixtures for parser behavior
- use live image tests when geometry or OCR layout is part of the bug
- build and run targeted tests when the environment allows
- record the outcome in `Journal.md`

## Success Criteria

This refactor is working if:
- wrong compact-price winners happen less often
- multi-tag scans are classified earlier and more honestly
- item names stay tied to the winning product block
- Foundation Models get used for narrower, better-scoped ambiguity
- test failures localize to a parser stage instead of "something changed somewhere"
## Where V2 Starts

V1 proved that the parser benefits from explicit stages, scene awareness, and cluster-aware reasoning.

V2 should focus on the places where v1 is still pragmatic rather than complete:
- richer cluster topology and price ownership across columns
- deeper preprocessing and OCR quality scoring
- stronger price-kind modeling for sale, regular, member, unit, and save amounts
- canonical item-name composition and repair
- more inspectable confidence and review diagnostics
- narrower and cheaper FM usage
- benchmark and ship-gate expansion

The active v2 documents are:
- [OCRParsingPipelineV2Plan.md](/Users/danielbell/Dev/Prixio/Prixio/OCRParsingPipelineV2Plan.md)
- [OCRParsingPipelineV2Checklist.md](/Users/danielbell/Dev/Prixio/Prixio/OCRParsingPipelineV2Checklist.md)

