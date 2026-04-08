# OCR Parsing Pipeline V2 Checklist

This is the active implementation checklist for the next parser-quality push.

Use it as the execution companion to [OCRParsingPipelineV2Plan.md](/Users/danielbell/Dev/Prixio/Prixio/OCRParsingPipelineV2Plan.md).

## Working Rules

For each phase:
- add or update tests first or in the same change
- keep changes tight to the phase
- run targeted tests for the touched parser area
- update `Journal.md`
- do not move to the next phase until the current phase has a clear result

## Phase Checklist

### Phase 1. Evidence Cluster Model V2
Status: Pending

Coding tasks by file:
- `Prixio/Scanning/Price/PriceParsingService.swift`
  - expand `EvidenceClusterRole`
  - add richer `EvidenceCluster` fields for region, centroid, linked cluster indexes, and ownership confidence
  - add any new nested types needed for cluster relationships
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
  - split cluster creation into:
    - raw spatial groups
    - typed cluster classification
    - cluster linking and ownership inference
  - add product-text vs price-column vs promo/noise classification
  - update `winningClusterIndex` logic to work through linked ownership rather than simple score only
  - update scene classification to consume the richer cluster model
- `Prixio/PrixioTests/PriceParsingServiceSpatialGroupingTests.swift`
  - add tests for cross-column product-text plus price-column ownership
  - add tests for promo banner isolation
  - add tests for unit-detail clusters not winning product ownership
- `Prixio/PrixioTests/PriceParsingServiceAmbiguityTests.swift`
  - add at least one case where richer cluster shape changes scene classification honestly

Ship gate:
- `PriceParsingServiceSpatialGroupingTests`
- at least one captured or synthetic cross-column ownership fixture

### Phase 2. Price Ownership And Price-Kind Modeling V2
Status: Pending

Coding tasks by file:
- `Prixio/Core/Models/PriceCandidate.swift`
  - add a typed `PriceKind`
  - preserve enough source metadata to explain why a candidate received that kind
- `Prixio/Scanning/Price/Parsing/PriceCandidateScorer.swift`
  - split extraction from classification from ranking
  - assign `PriceKind` before final ranking
  - add ownership-first scoring using linked clusters
  - keep alternate compact numeric interpretations when tokens are risky
  - make deposit/save/member/regular/unit candidates non-equivalent by default
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
  - rank within winning-cluster ownership first
  - only fall back to broader/global candidates when ownership is unresolved
- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
  - incorporate typed price-kind ambiguity into review decisions
- `Prixio/PrixioTests/PriceParsingServiceCapturedOCRTests.swift`
  - add or update PLU trap, Cadbury promo/save, and cross-column shelf-price cases
- `Prixio/PrixioTests/PriceParsingServiceDataSanitation.swift`
  - add tests for price-kind classification and risky numeric preservation

Ship gate:
- `PriceParsingServiceCapturedOCRTests`
- `PriceParsingServiceDataSanitation`
- at least one PLU trap, one promo/save trap, one cross-column shelf-price case

### Phase 3. OCR Quality And Preprocessing V2
Status: Pending

Coding tasks by file:
- `Prixio/Scanning/OCR/OCRResult.swift`
  - add a typed `OCRQualityReport`
  - include selected variant metadata and quality summary
- `Prixio/Scanning/OCR/OCRService.swift`
  - separate variant generation from OCR execution from quality scoring
  - add a rectification experiment seam
  - score candidate OCR passes and choose the winner through `OCRQualityReport`
  - keep the two-pass cap explicit
- `Prixio/Scanning/OCR/OCRTextObservation.swift`
  - carry any per-pass provenance needed for diagnostics without bloating parser-facing APIs
- `Prixio/PrixioTests/ImageFixtureTestSupport.swift`
  - expose OCR variant/quality info for fixtures
- `Prixio/PrixioTests/ImageFixtureParsingTests.swift`
  - add assertions for OCR quality report presence
  - add at least one fixture proving a fallback variant wins for a measurable reason

Ship gate:
- `ImageFixtureParsingTests`
- targeted fixture support proving OCR quality output is populated and stable

### Phase 4. Item Name Composition And Repair V2
Status: Pending

Coding tasks by file:
- `Prixio/Scanning/Price/Parsing/PriceParsingItemNameResolver.swift`
  - split raw fragment extraction from canonical display-name composition
  - add cluster-local multi-line name assembly
  - add light grocery OCR repair rules
- `Prixio/Scanning/Price/PriceParsingService.swift`
  - update result shape if needed to preserve both evidence-backed and canonical item name outputs
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
  - hand cluster-local item fragments into the resolver instead of only loose lines
- `Prixio/PrixioTests/PriceParsingServiceAmbiguityTests.swift`
  - add packaging-noise and split-title cases that pin name composition
- `Prixio/PrixioTests/PriceParsingServiceCapturedOCRTests.swift`
  - add captured OCR cases where canonical name differs from raw evidence text

Ship gate:
- `PriceParsingServiceAmbiguityTests`
- `PriceParsingServiceCapturedOCRTests`
- at least one packaging-noise and one split-title fixture

### Phase 5. Confidence, Review, And Diagnostics V2
Status: Pending

Coding tasks by file:
- `Prixio/Scanning/Price/PriceParsingService.swift`
  - add a structured parser decision report type or equivalent snapshot/result diagnostic payload
- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
  - emit structured reasons for review state and confidence shaping
  - distinguish OCR weakness, ownership weakness, and candidate-kind weakness
- `Prixio/Scanning/OCR/OCRResult.swift`
  - carry compact parser decision diagnostics if they belong on the final OCR result surface
- `Prixio/PrixioTests/OCRReviewStateTests.swift`
  - add tests that assert decision-report reasons, not just final review enum values
- `Prixio/PrixioTests/ParserEvaluationTests.swift`
  - consume the new diagnostic output in evaluation summaries

Ship gate:
- `OCRReviewStateTests`
- `ParserEvaluationTests`

### Phase 6. FM Hand-Off V2
Status: Pending

Coding tasks by file:
- `Prixio/Scanning/Price/Parsing/PriceParsingAssistedExtraction.swift`
  - shrink the FM input surface to winning cluster, nearby alternates, typed price kinds, and ambiguity reasons
  - strengthen deterministic skip rules
  - make FM tie-break responsibilities explicit
- `Prixio/Scanning/Price/PriceParsingService.swift`
  - thread the v2 structured search space into the assist hand-off
- `Prixio/PrixioTests/PriceParsingServiceFoundationModelAssistTests.swift`
  - add skip tests for stable deterministic parses
  - add tie-break tests for structured ambiguous cases only
- `Prixio/PrixioTests/ParserShipGateTests.swift`
  - add one release-critical case proving FM is not used on a stable parse

Ship gate:
- `PriceParsingServiceFoundationModelAssistTests`
- at least one case proving FM is skipped for a stable deterministic parse

### Phase 7. Evaluation And Ship Gates V2
Status: Pending

Coding tasks by file:
- `Prixio/PrixioTests/ParserEvaluationTests.swift`
  - add fixture category labels and category-level summaries
  - report failures by class instead of only per case
- `Prixio/PrixioTests/ParserShipGateTests.swift`
  - define a compact v2 release gate with one case per critical failure class
- `Prixio/ImageFixtureCoverageTracker.md`
  - map current fixtures to v2 failure classes
  - list the obvious missing fixture categories
- `Prixio/ImageFixtureTestPlan.md`
  - update fixture acquisition priorities so new captures feed the v2 benchmark buckets

Ship gate:
- `ParserEvaluationTests`
- `ParserShipGateTests`
- updated `ImageFixtureCoverageTracker.md`

## V2 Release Gate

Do not call v2 complete until these are true:
- the v2 phase ship gates are green
- the full parser-related test suite is green
- the v2 release gate in `ParserShipGateTests` is green
- `OCRParsingPipelineV2Plan.md` reflects what actually landed
- `Journal.md` explains the major takeaways, not just the code changes

## Recommended First Pull Requests

If the work lands incrementally, the cleanest early PR order is:

1. `Phase 1A`
- cluster role/type expansion in `PriceParsingService.swift`
- cluster-building split in `PriceParsingSnapshotBuilder.swift`
- new spatial grouping tests

2. `Phase 1B`
- cluster linking and cross-column ownership
- winning-cluster selection through ownership links
- captured/synthetic cross-column tests

3. `Phase 2A`
- `PriceKind` in `PriceCandidate.swift`
- candidate classification in `PriceCandidateScorer.swift`
- sanitation tests for candidate kinds

4. `Phase 2B`
- ownership-first ranking in `PriceParsingSnapshotBuilder.swift`
- captured OCR contract updates for PLU, save, and cross-column traps
