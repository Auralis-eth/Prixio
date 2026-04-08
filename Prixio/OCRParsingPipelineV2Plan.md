# OCR Parsing Pipeline V2 Plan

This document is the concrete execution plan for the next parser-quality push in Prixio after the v1 pipeline refactor.

V1 proved the shape:
- preprocessing belongs before OCR, not inside parser cleanup
- scene classification and evidence clusters improve ownership reasoning
- compact numeric prices need explicit suspicion
- Foundation Models work better as a narrow second opinion than as a cleanup crew

V2 is not another broad rewrite. It is the pass where the pragmatic shortcuts from v1 get replaced with deeper, more explicit parser structure.

## Status

Implemented in pragmatic production form.

Prerequisite:
- the v1 parser pipeline is in production-ready shape and the current test suite is green

Definition of done for any v2 phase:
- tests land first or in the same change
- parser behavior changes are visible in fixtures or diagnostics
- `Journal.md` is updated with what actually changed and what the phase taught us

## V2 Goals

1. Make price ownership explicit enough that cross-column shelf tags stop depending on lucky scoring.
2. Improve OCR quality decisions with measurable preprocessing instead of one-off fallback heuristics.
3. Model price kinds earlier so regular, sale, member, save, and unit prices stop competing as if they are equivalent.
4. Compose better product names from cluster evidence instead of picking one line and hoping it is the right one.
5. Make confidence and review output inspectable enough that regressions can be diagnosed without snippet archaeology.
6. Reduce FM invocation cost by handing the model a tighter, more structured search space.
7. Make parser quality measurable by failure class, not only by pass/fail.

## Non-Goals

- Do not replace Vision OCR in this phase.
- Do not turn the parser into an opaque end-to-end model.
- Do not expand FM usage just because the framework is available.
- Do not mix parser diagnostics with UI redesign work.

## V2 Architecture Direction

The v2 parser should behave more like a structured decision pipeline than a clever ranking pile.

Target direction:
- OCR produces observations plus explicit OCR quality metadata
- observations become typed clusters instead of just grouped lines
- price candidates get typed as shelf, sale, member, regular, save, deposit, unit, or unknown
- the parser chooses a winning product cluster first
- the parser chooses a winning price within that cluster second
- item name, unit, quantity, and review state are derived from the winning cluster and winning price ownership context
- FM only runs when the structured search space is still unresolved

## File Ownership Map

This section exists so implementation can start without guesswork.

- `Prixio/Scanning/OCR/OCRService.swift`
  - image variant generation
  - OCR pass execution
  - OCR quality scoring
  - OCR variant selection

- `Prixio/Scanning/OCR/OCRResult.swift`
  - OCR quality metadata that should survive past the OCR layer
  - compact result-side diagnostics the rest of the app can consume

- `Prixio/Scanning/OCR/OCRTextObservation.swift`
  - observation-level provenance or alternate hypothesis data

- `Prixio/Core/Models/PriceCandidate.swift`
  - typed price kind and candidate-level source metadata

- `Prixio/Scanning/Price/PriceParsingService.swift`
  - orchestration boundary
  - nested cluster/decision-report types
  - final result assembly and FM invocation decisions

- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
  - cluster construction
  - cluster linking
  - scene classification
  - ownership-aware winning cluster and winning price prep

- `Prixio/Scanning/Price/Parsing/PriceCandidateScorer.swift`
  - candidate extraction
  - candidate kind classification
  - ownership-aware candidate ranking

- `Prixio/Scanning/Price/Parsing/PriceParsingItemNameResolver.swift`
  - cluster-local fragment extraction
  - canonical display-name composition
  - lightweight grocery OCR repair

- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
  - structured confidence and review reasons
  - decision diagnostics

- `Prixio/Scanning/Price/Parsing/PriceParsingAssistedExtraction.swift`
  - structured FM hand-off
  - deterministic skip rules
  - tie-break behavior

- `Prixio/PrixioTests/PriceParsingServiceSpatialGroupingTests.swift`
  - cluster shape, roles, links, and ownership tests

- `Prixio/PrixioTests/PriceParsingServiceCapturedOCRTests.swift`
  - captured OCR contract tests for real parser traps

- `Prixio/PrixioTests/PriceParsingServiceDataSanitation.swift`
  - candidate kind, risky numeric, and normalization coverage

- `Prixio/PrixioTests/PriceParsingServiceAmbiguityTests.swift`
  - scene and ownership ambiguity behavior

- `Prixio/PrixioTests/PriceParsingServiceFoundationModelAssistTests.swift`
  - FM skip and tie-break behavior

- `Prixio/PrixioTests/ImageFixtureParsingTests.swift`
  - live OCR fixture invariants and OCR quality coverage

- `Prixio/PrixioTests/ImageFixtureTestSupport.swift`
  - fixture-side OCR evaluation support

- `Prixio/PrixioTests/OCRReviewStateTests.swift`
  - review and confidence contract tests

- `Prixio/PrixioTests/ParserEvaluationTests.swift`
  - category-level evaluation summaries

- `Prixio/PrixioTests/ParserShipGateTests.swift`
  - compact release-critical gate

## Phase 1: OCR Quality And Preprocessing V2

Goal:
- replace "fallback if weak" with measurable OCR quality evaluation and stronger image preparation seams

Why:
- v1 proved the seam is useful, but preprocessing is still shallow
- OCR quality still enters the parser mostly as text confidence instead of a first-class quality signal

Scope:
- keep the two-pass cap
- add explicit OCR quality scoring
- add a real rectification experiment seam
- benchmark image variants against captured fixtures

Concrete work:
- add an `OCRQualityReport` type in the OCR layer
- score OCR output using observation count, price-like evidence count, descriptor density, and confidence spread
- add an experimental rectification path behind a controlled flag or internal option
- measure which preprocessing variant wins per fixture instead of relying on eyeballing logs
- keep the parser aware of OCR quality without coupling parser logic to image APIs

Likely files:
- `Prixio/Scanning/OCR/OCRService.swift`
- `Prixio/Scanning/OCR/OCRResult.swift`
- `Prixio/PrixioTests/ImageFixtureTestSupport.swift`
- `Prixio/PrixioTests/ImageFixtureParsingTests.swift`

Definition of done:
- OCR quality is a typed output, not just debug logging
- fixture tests can show when a fallback variant wins and why
- the parser can distinguish weak OCR from weak parse more explicitly

Implementation sequence:
1. add `OCRQualityReport` to `OCRResult.swift`
2. split `OCRService.swift` into variant generation, OCR execution, and quality scoring
3. expose quality report through `ImageFixtureTestSupport.swift`
4. update `ImageFixtureParsingTests.swift` to assert quality-report presence and variant selection behavior

## Phase 2: Evidence Cluster Model V2

Goal:
- make cluster structure rich enough to represent real shelf-tag layouts instead of simple grouped lines

Why:
- v1 clusters are useful, but still too shallow for cross-column prices, promo cards, and mixed layout scenes

Scope:
- expand cluster roles
- add geometric metadata and ownership hints
- separate product text clusters from price-column clusters and promo/noise clusters

Concrete work:
- introduce richer cluster metadata:
  - bounding region
  - centroid
  - neighboring cluster relationships
  - probable role
  - ownership confidence
- add roles such as:
  - `productText`
  - `priceColumn`
  - `promoBanner`
  - `unitDetail`
  - `noise`
- add cluster-linking logic so a price cluster can belong to a neighboring product cluster
- update scene classification to consume the richer cluster structure

Likely files:
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
- `Prixio/PrixioTests/PriceParsingServiceSpatialGroupingTests.swift`

Definition of done:
- the snapshot can represent product and price evidence that live in separate columns
- cluster ownership is inspectable in tests
- scene classification uses cluster shape, not only line counts and promo markers

Implementation sequence:
1. expand cluster types in `PriceParsingService.swift`
2. split cluster creation and cluster linking in `PriceParsingSnapshotBuilder.swift`
3. add synthetic cross-column cases in `PriceParsingServiceSpatialGroupingTests.swift`
4. add at least one ambiguity test where richer cluster shape changes scene classification

## Phase 3: Price Ownership And Price-Kind Modeling V2

Goal:
- stop letting every price-like token compete in one undifferentiated pool

Why:
- many remaining parser misses are not "wrong extraction"
- they are "wrong type of price won"

Scope:
- classify price candidates earlier
- keep multiple risky hypotheses where useful
- score ownership within a cluster instead of globally first

Concrete work:
- add typed price kinds:
  - `shelf`
  - `sale`
  - `member`
  - `regular`
  - `save`
  - `deposit`
  - `unit`
  - `unknown`
- preserve alternate compact numeric interpretations when the OCR token is risky
- rank within cluster ownership first, then globally only as fallback
- add stronger PLU-vs-price and size-vs-price disambiguation
- make deposit and save amounts non-competing by default unless evidence strongly says otherwise

Likely files:
- `Prixio/Core/Models/PriceCandidate.swift`
- `Prixio/Scanning/Price/Parsing/PriceCandidateScorer.swift`
- `Prixio/Scanning/Price/Parsing/PriceParsingSnapshotBuilder.swift`
- `Prixio/PrixioTests/PriceParsingServiceCapturedOCRTests.swift`
- `Prixio/PrixioTests/PriceParsingServiceDataSanitation.swift`

Definition of done:
- candidate kind is typed and testable
- cross-column shelf price ownership beats global numeric ranking in known fixture cases
- risky compact tokens can be preserved without letting them dominate the final result

Implementation sequence:
1. add `PriceKind` and supporting metadata to `PriceCandidate.swift`
2. classify candidates in `PriceCandidateScorer.swift` before final ranking
3. update `PriceParsingSnapshotBuilder.swift` to prefer ownership-first ranking
4. pin the new behavior in captured and sanitation tests

## Phase 4: Item Name Composition And Repair V2

Goal:
- move from "best line wins" to "compose a product name from the winning cluster"

Why:
- product names still break when OCR splits title, size, brand, and variant across adjacent lines

Scope:
- compose multi-line names
- separate raw OCR evidence from canonical display names
- add light grocery-specific repair without pretending to be a language model

Concrete work:
- build cluster-local item fragments
- add composition rules for:
  - brand + product + variant
  - title + size marker when size belongs in the display name
  - title without package-size junk when size is only quantity context
- add a small repair layer for common OCR drift in grocery names
- preserve both:
  - raw evidence-backed item text
  - cleaned display-oriented item name

Likely files:
- `Prixio/Scanning/Price/Parsing/PriceParsingItemNameResolver.swift`
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `Prixio/PrixioTests/PriceParsingServiceAmbiguityTests.swift`
- `Prixio/PrixioTests/PriceParsingServiceCapturedOCRTests.swift`

Definition of done:
- multi-line product names are composed within the winning cluster
- parser tests distinguish raw evidence text from canonical display text
- neighboring product leakage is reduced without flattening useful size or brand info

Implementation sequence:
1. split raw fragment extraction from canonical naming in `PriceParsingItemNameResolver.swift`
2. feed cluster-local fragments from `PriceParsingSnapshotBuilder.swift`
3. update `PriceParsingService.swift` result assembly if both raw and canonical names need to survive
4. pin split-title and packaging-noise behavior in ambiguity and captured OCR tests

## Phase 5: Confidence, Review, And Diagnostics V2

Goal:
- make parser decisions diagnosable without reading implementation details

Why:
- v1 separated OCR and parse confidence conceptually, but the system still needs better visibility into why a result ended up clean, recommended, or required

Scope:
- expose structured reasons for the winning cluster and winning price
- produce richer debug/evaluation output

Concrete work:
- add a structured parser decision report to the heuristic snapshot or result-building path
- include:
  - chosen cluster id or index
  - chosen price candidate and kind
  - ownership reasons
  - major penalties and boosts
  - review issues by category
- keep the UI-facing `OCRReview` compact, but make evaluation and tests richer

Likely files:
- `Prixio/Scanning/Price/Parsing/PriceParsingConfidenceResolver.swift`
- `Prixio/Scanning/Price/PriceParsingService.swift`
- `Prixio/PrixioTests/OCRReviewStateTests.swift`
- `Prixio/PrixioTests/ParserEvaluationTests.swift`

Definition of done:
- parser decisions can be explained from structured output instead of snippets
- review-state regressions are easier to localize
- evaluation can group errors by failure reason

Implementation sequence:
1. add parser decision report types in `PriceParsingService.swift`
2. emit structured reasons from `PriceParsingConfidenceResolver.swift`
3. thread compact diagnostics into `OCRResult.swift` only if they belong in the app-facing contract
4. update `OCRReviewStateTests.swift` and `ParserEvaluationTests.swift`

## Phase 6: FM Hand-Off V2

Goal:
- make FM invocation cheaper, rarer, and more structured

Why:
- the model should break ties inside a prepared decision space, not rediscover parser structure from scratch

Scope:
- shrink prompt surface
- strengthen no-call rules
- make structured assist inputs line up with v2 cluster and price-kind types

Concrete work:
- hand off only:
  - winning cluster candidates
  - nearby alternate clusters when ambiguity remains
  - typed candidate kinds
  - cluster roles
  - ambiguity reasons
- strengthen skip rules so FM does not run when the deterministic path is already complete and stable
- evaluate FM usage rate by fixture class, not only correctness

Likely files:
- `Prixio/Scanning/Price/Parsing/PriceParsingAssistedExtraction.swift`
- `Prixio/PrixioTests/PriceParsingServiceFoundationModelAssistTests.swift`

Definition of done:
- FM prompts are narrower and more structured than v1
- skip behavior is explicitly tested
- FM is measurably used less on already-stable scans

Implementation sequence:
1. narrow the structured input in `PriceParsingAssistedExtraction.swift`
2. add explicit skip rules in `PriceParsingService.swift` or the assist boundary
3. add skip and tie-break tests in `PriceParsingServiceFoundationModelAssistTests.swift`
4. add one release-critical non-invocation case in `ParserShipGateTests.swift`

## Phase 7: Evaluation And Ship Gates V2

Goal:
- make parser quality measurable by scene and failure class

Why:
- v1 made the parser more testable
- v2 should make parser progress easier to judge without reading every failing test by hand

Scope:
- expand fixture labeling
- add benchmark slices and ship gates
- track parser regressions by category

Concrete work:
- tag fixtures by failure class:
  - multi-tag
  - promo-heavy
  - packaging noise
  - produce card
  - compact numerics
  - PLU collision
  - cross-column shelf price
- update evaluation output to report category summaries
- define a v2 ship gate that covers:
  - one clean single-tag case
  - one promo/sale case
  - one multi-product case
  - one packaging-noise case
  - one compact-numeric/PLU trap

Likely files:
- `Prixio/PrixioTests/ParserEvaluationTests.swift`
- `Prixio/PrixioTests/ParserShipGateTests.swift`
- `Prixio/ImageFixtureCoverageTracker.md`

Definition of done:
- failures are grouped by category instead of only per test
- a small release-critical v2 ship gate exists
- new fixture additions have a clear place in the evaluation surface

Implementation sequence:
1. categorize fixtures in `ImageFixtureCoverageTracker.md`
2. update `ParserEvaluationTests.swift` to report grouped summaries
3. build the compact v2 release gate in `ParserShipGateTests.swift`
4. update `ImageFixtureTestPlan.md` with missing fixture priorities

## Risks

- Overbuilding cluster abstractions before tests prove the ownership model helps
- Spending too much time on image preprocessing when remaining errors are mostly ownership and scene structure
- Letting item-name repair turn into silent hallucination
- Expanding FM scope because it is easier than deepening deterministic structure

## Risk Controls

- keep each phase narrow and fixture-led
- insist on captured OCR tests for every new ownership rule
- compare field correctness and review behavior separately
- do not let FM usage go up without a measurable accuracy reason

## Recommended Execution Order

1. Evidence cluster model v2
2. Price ownership and price-kind modeling v2
3. OCR quality and preprocessing v2
4. Item name composition and repair v2
5. Confidence, review, and diagnostics v2
6. FM hand-off v2
7. Evaluation and ship gates v2

## No-Question Startup Assumptions

If implementation starts without another planning conversation, use these defaults:
- keep Vision as the recognizer
- keep the two-pass OCR cap
- prefer captured OCR fixtures over new synthetic fixtures when either can cover the same case
- preserve current app-facing result shape unless a phase explicitly needs a richer contract
- avoid UI changes unless a parser contract cannot be tested or surfaced otherwise

## Success Criteria

V2 is working if:
- cross-column shelf tags stop depending on lucky global price ranking
- compact numeric traps are explainable instead of surprising
- product names are composed more reliably from local evidence
- parser review output becomes easier to debug
- FM invocation goes down on stable scans
- evaluation results tell us which failure class regressed, not just that something broke
