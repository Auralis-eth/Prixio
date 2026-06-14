# Prixio LLM App Context

This file is the compact, durable app brief for future LLM sessions.

## Short LLM Brief

Prixio is an iOS app for turning messy grocery shelf-tag photos into useful price intelligence. The user captures or imports a photo of a product label, shelf tag, produce sign, or sale card. The app runs OCR, parses the noisy text into an item name, price, unit, quantity, confidence, and review state, lets the user confirm or correct the result, then saves a normalized `PriceEntry` in SwiftData with optional store and location context.

The larger product goal is not just text extraction. Prixio is building a personal grocery price memory: scan prices in the store, compare historical prices across stores, and use that history to make shopping-list and trip decisions. The app currently has three connected flows: `Scan` for capture and confirmation, `Compare` for browsing saved item history and ranked store prices, and `Shopping List` for checklist planning with best-store suggestions and scan-refresh nudges when data is missing or stale.

Technically, Prixio is SwiftUI-first, SwiftData-backed, and heuristic-first in its parsing strategy. Vision/OCR produces raw observations; deterministic parser phases clean, group, score, and resolve the result; Foundation Models are reserved as a narrow assist path for ambiguous cases rather than the default parser. The core engineering theme is honesty under uncertainty: OCR is noisy, grocery signage is inconsistent, and the app should surface ambiguity instead of pretending every filled field is trustworthy.

Future LLM work should preserve these priorities: keep scanner and parser edits tightly scoped, reuse shared pricing logic in `PriceInsightEngine`, reuse item grouping in `ItemKeyNormalizer`, avoid duplicating best-price state outside saved `PriceEntry` records, and add or update parser tests whenever OCR or price heuristics change.

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

The app now has three connected user-facing product flows:

1. `Scan`
   - capture or import a shelf-tag image
   - run OCR and parsing
   - confirm and save a structured `PriceEntry`
2. `Compare`
   - browse tracked items
   - search saved product history
   - inspect per-store ranked prices with staleness cues
3. `Shopping List`
   - build a trip checklist
   - surface best-store suggestions per item
   - recommend a likely winner store for the trip
   - route back into `Scan` when stale or missing data should be refreshed

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
  - app shell and top-level tab navigation
- `AppNavigationModel.swift`
  - shared app-level navigation coordinator
  - owns selected tab state
  - carries pending scan-launch requests from Shopping List back into Scan
- `ScanRootView.swift`
  - scanner entry point and scan experience shell
- `ScanViewModel.swift`
  - orchestrates image capture/import, OCR, parsing, review state, and save flow

### Compare Flow

- `CompareRootView.swift`
  - root browse/search/recent-comparisons screen
- `CompareViewModel.swift`
  - derives search results, recent captures, browse rows, suggestion cards, and item-detail comparison rows
- `ItemDetailView.swift`
  - ranked per-store price view for one item
- `EntryDetailSheet.swift`
  - bottom-sheet-style detail for a selected saved entry
- `StoreComparisonRow.swift`
  - compare-side derived row model

### Shopping List Flow

- `ShoppingListRootView.swift`
  - list shell, trip card, checklist, completed section, and nudge routing
- `ShoppingListViewModel.swift`
  - derives active rows, completed rows, nudge eligibility, and trip recommendation
- `ShoppingListRepository.swift`
  - fetch/create/update/delete layer for shopping lists and items
- `TripRecommendation.swift`
  - derived trip-optimizer outcome enum
- `ShoppingListRowData.swift`
  - derived row model for checklist presentation
- `AddShoppingListItemSheet.swift`
  - add known or freeform shopping-list item
- `ShoppingListItemDetailSheet.swift`
  - top store options for one list item plus scan/delete actions
- `ScanNudgeSheet.swift`
  - refresh-data prompt shown after checking off stale or missing-price items

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
- `ShoppingList`
  - persisted shopping-list container
  - model is multi-list-ready even though the UI exposes one visible default list today
- `ShoppingListItem`
  - persisted checklist row model
- `StalenessBucket`
  - shared freshness vocabulary used in Compare and Shopping List

### Shared Derived Domain

- `ItemKeyNormalizer.swift`
  - one shared normalization rule for item grouping and lookup
- `PriceInsightEngine.swift`
  - shared pure pricing logic
  - owns best-store selection
  - owns staleness bucket logic
  - owns trip winner aggregation

This shared domain matters because Compare and Shopping List intentionally do not each invent their own pricing truth.

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

Compare-side data flow:

1. `CompareRootView` reads `PriceEntry` records through SwiftData.
2. `CompareViewModel` groups entries by normalized item key.
3. Browse rows, recent captures, and suggested comparison cards are derived in memory.
4. `ItemDetailView` builds ranked per-store rows for the selected item.

Shopping List data flow:

1. `ShoppingListRepository` fetches or creates the default visible list.
2. `ShoppingListRootView` reads both `ShoppingList` and `PriceEntry`.
3. `ShoppingListViewModel` derives row suggestions and trip recommendation from shared `PriceInsightEngine` logic.
4. When a stale or missing-data item is checked off, the app may show `ScanNudgeSheet`.
5. `AppNavigationModel` routes the user back into `Scan` with item and optional store prefilled.

## Persistence

SwiftData entities:
- `PriceEntry`
- `StoreChain`
- `StoreLocation`
- `ShoppingList`
- `ShoppingListItem`

Persistence ownership:
- `PrixioApp` creates the model container
- `PriceEntryRepository` translates reviewable parser output into saved records
- `ShoppingListRepository` owns shopping-list persistence operations

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
- `AppNavigationModelTests.swift`
  - cross-tab scan routing and prefill request handling
- `ShoppingListDomainTests.swift`
  - shared shopping/price insight logic and normalization reuse
- `CompareFlowViewModelTests.swift`
  - compare-side derivation logic
- `TripRecommendationTests.swift`
  - trip optimizer rules
- `ShoppingListViewModelTests.swift`
  - checklist derivation, repository behavior, and freshness-loop behavior

Manual QA / release-facing docs:

- `PhysicalDeviceQATestPlan.md`
  - manual physical-device test checklist across Scan, Compare, Shopping List, permissions, routing, and resilience

## Known Gotchas

- OCR output can split prices, units, and names across lines.
- Live OCR can drift slightly between runs; exact assertions should be reserved for deterministic frozen inputs.
- Store detection can be indirectly affected by parser changes, because OCR-derived hints feed store inference.
- The parser is the densest area of the codebase. Tight, phase-specific edits are safer than broad rewrites.
- Compare and Shopping List read price intelligence from `PriceEntry`; do not persist duplicate “best price” state.
- Shopping List defaults to the visible `"This trip"` list, but the persistence model is already multi-list-ready.
- Shopping List scan launches prefer the row’s best-store name first, then fall back to the trip winner if needed.
- Shopping List row distance now depends on real saved store coordinates; rows without coordinates should omit distance instead of showing placeholders.

## Guidance For Future LLM Sessions

- Start with the parser/test boundary before changing heuristics.
- Prefer captured-OCR tests when the bug starts after OCR.
- Prefer real-image fixtures when geometry or OCR quality is part of the bug.
- Do not widen Foundation Models scope unless deterministic parsing has already been tightened first.
- Keep changes local to the pipeline stage that owns the problem.
- Reuse `PriceInsightEngine` and `ItemKeyNormalizer` rather than adding flow-specific copies of pricing or grouping logic.
- If editing Compare or Shopping List behavior, verify both build cleanly because they now share derived price logic.
