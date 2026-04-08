# Prixio LLM App Context

This file is the compact, durable app brief for future LLM sessions.

## What The App Is

Prixio is an iOS grocery price capture app.

Main user flow:
1. Take or import a photo of a shelf tag, produce sign, or pricing label.
2. Run OCR on the image.
3. Parse the OCR into a structured result:
   - item name
   - price
   - unit
   - quantity
   - review state
4. Let the user confirm or adjust the result.
5. Save a normalized price record, optionally tied to a store and location.

The app is trying to turn messy retail signage into defensible grocery price data, not just extract text.

## Product Priorities

- Preserve correct price ownership across noisy shelf tags.
- Be honest about uncertainty.
- Prefer deterministic parsing first.
- Use Foundation Models only as a narrow escalation path for ambiguous cases.
- Keep the confirmation flow strong because OCR is inherently noisy.

## High-Level Architecture

### App Shell

- `PrixioApp.swift`
  - owns the SwiftData container
  - registers the core persisted models
- `MainView.swift`
  - app shell and top-level navigation
- `ScanRootView.swift`
  - scanner entry point and scan experience shell
- `ScanViewModel.swift`
  - orchestrates image capture/import, OCR, parsing, review state, and save flow

### Core Domain Models

- `PriceEntry`
  - persisted grocery price record
- `PriceEntryDraft`
  - editable in-memory result before save
- `StoreChain`
  - normalized chain-level store entity
- `StoreLocation`
  - location-level store entity
- `PriceCandidate`
  - candidate price extracted from OCR
  - includes typed `PriceKind`
- `StoreCandidate`
  - candidate store match during detection
- `UnitType`
  - normalized measurement and unit enum

### OCR Layer

- `OCRService.swift`
  - owns OCR execution
  - image variant generation and selection
  - bounded fallback OCR behavior
  - OCR quality scoring
- `OCRTextObservation.swift`
  - parser-facing OCR observation with text, confidence, and geometry
- `OCRResult.swift`
  - final parser result contract
  - includes review state, support lines, optional OCR quality report, and optional parser decision report

### Price Parsing Layer

`PriceParsingService.swift` is the orchestration boundary. Most parser internals have been split into focused files under `Scanning/Price/Parsing/`.

- `PriceParsingSnapshotBuilder.swift`
  - supported-line filtering
  - observation cleanup and normalization
  - spatial grouping
  - evidence cluster construction
  - scene classification
  - winning-cluster selection
- `PriceCandidateScorer.swift`
  - candidate extraction
  - candidate kind classification
  - ownership-aware ranking
- `PriceParsingUnitResolver.swift`
  - unit detection
  - quantity inference
- `PriceParsingItemNameResolver.swift`
  - item-name extraction
  - canonical name composition
  - grocery-specific OCR repair
- `PriceParsingConfidenceResolver.swift`
  - ambiguity analysis
  - confidence shaping
  - review-state reasons
  - parser decision reporting
- `PriceParsingAssistedExtraction.swift`
  - Foundation Models escalation boundary
  - structured assist prompt and input
  - deterministic skip rules
  - merge policy for assisted results

### Store Layer

- `StoreCatalog.swift`
  - store metadata and reference source
- `StoreDetectionService.swift`
  - store inference and nearby-store matching
- `ScanSessionStore.swift`
  - scan-session-level state for store selection and related context
- `StoreSelectionSheet.swift`
  - UI for confirming or changing inferred store

### Shared UI

- `ConfirmationSheet.swift`
  - final review, edit, and save UI for parsed results
- `ImageViewer.swift`
  - inspect captured or imported image
- `ToastView.swift`
  - lightweight transient messaging
- `ScannerGuideOverlay.swift`
  - camera guidance overlay

## Parser Design Principles

- OCR is noisy and spatially messy.
- Parser behavior should be deterministic where possible.
- Geometry matters; a price should belong to the right product block.
- `Decimal` is used for money and quantity math.
- Confidence and review state should reflect actual uncertainty, not false precision.
- Foundation Models are a tie-breaker, not the primary parser.

## Important Parser Concepts

### Evidence Clusters

The parser groups OCR observations into product-level evidence clusters.

Clusters can act like:
- product text
- price column
- promo banner
- unit detail
- noise

This is how the parser reasons about layouts where the product title and winning price are near each other but not on the same literal line group.

### Scene Classification

The parser classifies the overall scan scene before final confidence assembly.

Current scene classes:
- `singleTag`
- `multiTag`
- `promoCard`
- `receiptLike`
- `unclear`

### Price Kinds

`PriceCandidate` includes a typed `PriceKind`, so the parser can distinguish:
- shelf
- sale
- member
- regular
- save
- deposit
- unit
- unknown

This prevents every numeric-looking token from competing as if it were the same kind of price.

### Review Honesty

The app does not assume a parse is safe just because fields are filled.

`OCRReview` can surface issues like:
- no price candidates
- multiple competing prices
- missing item name
- missing unit
- missing quantity
- low confidence
- sparse OCR
- possible multi-product scan

If ambiguity is severe enough, the result should be reviewed before save.

## Current Data Flow

1. User captures or imports an image.
2. `ScanViewModel` asks `OCRService` for OCR observations.
3. `PriceParsingService.extract(from:)` builds a heuristic snapshot.
4. The parser resolves item name, price, unit, quantity, confidence, and review state.
5. If ambiguity is high enough and skip rules do not apply, the parser may escalate to Foundation Models.
6. The user reviews the result in `ConfirmationSheet`.
7. `PriceEntryRepository` persists the normalized draft into SwiftData.

## Persistence

SwiftData entities:
- `PriceEntry`
- `StoreChain`
- `StoreLocation`

Persistence ownership:
- `PrixioApp` creates the model container
- `PriceEntryRepository` translates reviewable parser output into saved records

## Testing Map

Important test files and what they guard:

- `ImageFixtureParsingTests.swift`
  - real-image OCR-to-parser coverage
- `PriceParsingServiceCapturedOCRTests.swift`
  - deterministic parser behavior from frozen OCR observations
- `PriceParsingServiceSpatialGroupingTests.swift`
  - grouping, evidence clusters, and winning-cluster behavior
- `PriceParsingServiceAmbiguityTests.swift`
  - ambiguity, review-state, and parser honesty rules
- `PriceParsingServiceFoundationModelAssistTests.swift`
  - FM skip rules and assist merge behavior
- `PriceParsingServiceDataSanitation.swift`
  - normalization, risky numeric handling, and candidate typing
- `OCRReviewStateTests.swift`
  - final review-state contracts
- `ParserEvaluationTests.swift`
  - grouped evaluation summaries by failure class
- `ParserShipGateTests.swift`
  - compact release-critical parser gate
- `ScanViewModelTests.swift`
  - scan workflow orchestration

## Known Gotchas

- OCR output can split prices, units, and names across lines.
- Live OCR can drift slightly between runs; exact assertions should be reserved for deterministic frozen inputs.
- Store detection can be indirectly affected by parser changes, because OCR-derived hints feed store inference.
- The parser is the densest area of the codebase. Tight, phase-specific edits are safer than broad rewrites.

## Guidance For Future LLM Sessions

- Start with the parser/test boundary before changing heuristics.
- Prefer captured-OCR tests when the bug starts after OCR.
- Prefer real-image fixtures when geometry or OCR quality is part of the bug.
- Do not widen Foundation Models scope unless deterministic parsing has already been tightened first.
- Keep changes local to the pipeline stage that owns the problem.
