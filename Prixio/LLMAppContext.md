# Prixio LLM App Context

This file is the compact, durable app brief for future LLM sessions.

## Short LLM Brief

Prixio is an iOS app for turning grocery shelf-tag photos into useful price intelligence. The user captures or imports a photo of a product label, shelf tag, produce sign, or sale card. On iOS 27+ a multimodal on-device `SystemLanguageModel` reads the photo and returns structured fields directly — item name, price, unit, quantity, a list of price candidates, scene kind, and model-reported issues. Deterministic app code then validates that output, builds an editable draft, lets the user confirm or correct it, and saves a normalized `PriceEntry` in SwiftData with optional store and location context.

The larger product goal is not just text extraction. Prixio is building a personal grocery price memory: scan prices in the store, compare historical prices across stores, and use that history to make shopping-list and trip decisions. The app currently has three connected flows: `Scan` for capture and confirmation, `Compare` for browsing saved item history and ranked store prices, and `Shopping List` for checklist planning with best-store suggestions and scan-refresh nudges when data is missing or stale.

Technically, Prixio is SwiftUI-first and SwiftData-backed. The Vision OCR pipeline that previously repaired noisy text fragments has been removed; the image-AI flow (`UIImage.extractPriceInformation`) is now the single extraction front door. The deterministic layer owns everything that must never be guessed: validation/cross-checking the model's own output, unit-price math, receipt suppression, store matching, draft building, and persistence. The core engineering theme is honesty under uncertainty: grocery signage is inconsistent, and the app should surface ambiguity instead of pretending every filled field is trustworthy.

Future LLM work should preserve these priorities: keep scanner and pipeline edits tightly scoped, reuse shared pricing logic in `PriceInsightEngine`, reuse item grouping in `ItemKeyNormalizer`, avoid duplicating best-price state outside saved `PriceEntry` records, and update the pipeline/tool tests whenever extraction or price logic changes.

## What The App Is

Prixio is an iOS grocery price capture app. The base runtime is iOS 27.0.

Main user flow:
1. Take or import a photo of a shelf tag, produce sign, or pricing label.
2. Run the image-AI extractor on the photo (`UIImage.extractPriceInformation`).
3. Receive a structured `LLMOCRResult`:
   - item name
   - price (and a list of price candidates)
   - unit
   - quantity
   - scene kind and model-reported issues
4. Validate the result deterministically and build a draft (price, unit, quantity, review state).
5. Let the user confirm or adjust the result.
6. Save a normalized price record, optionally tied to a store and location.

The app now has three connected user-facing product flows:

1. `Scan`
   - capture or import a shelf-tag image
   - run image-AI extraction and deterministic validation
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
- Trust the model to read, then verify deterministically — nothing is saved on model output alone.
- Keep extraction (model) and decision-making (deterministic app code) cleanly separated.
- Keep the confirmation flow strong because retail signage is inherently messy.

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
  - orchestrates image capture/import, image-AI extraction, validation, review state, and save flow

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
  - candidate price (one of the model's enumerated prices, mapped into the draft)
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

### AI Extraction Layer (`Scanning/AI/`)

The single extraction front door. A multimodal `SystemLanguageModel` reads the photo and returns structured grocery-price fields directly; there is no Vision OCR step.

- `ImagePriceExtractor.swift`
  - `UIImage.extractPriceInformation(context:)`
  - gated on `SystemLanguageModel.default.availability`; returns `nil` when unavailable or on failure
- `LLMOCRResult.swift`
  - the `@Generable` model output: `relevantText`, `scene` (`LLMSceneKind`), `priceCandidates` (`LLMPriceCandidate`), item/brand/price/unit/quantity/saleEndsOn, and `issues` (`LLMExtractionIssue`)
- `ScanReview.swift`
  - `OCRReview` / `OCRReviewIssue` / `OCRReviewState` — Prixio's review model. `usedFoundationModel` is metadata only, NOT a review trigger.
- `TextObservation.swift`
  - source-agnostic `protocol TextObservation` + `PlainTextObservation`, so the surviving scorers re-read the model's own transcription instead of Vision observations
- `Pipeline/` (deterministic, always run — never model-callable)
  - `PriceExtractionValidator.swift` — re-reads the model's `relevantText`/candidates, cross-checks the chosen primary price for grounding, maps model issues, and produces the `OCRReview`
  - `ReceiptCaptureClassifier.swift` — `scene == .receiptLike` or text heuristic suppresses store autofill
  - `PriceDraftBuilder.swift` — maps `LLMOCRResult` → `PriceEntryDraft` (candidate priority follows list order, confidence 1.0, no source-line indexes)
- `Tools/` (`FoundationModels.Tool` conformances)
  - `NormalizeUnitPriceTool`, `ResolveUnitAndQuantityTool`, `InferStoreContextTool`, `ItemHistoryTool`
  - compiled as shared adapters for future Compare/Planner agents; NOT registered on the single-photo Capture session

### Price Domain Layer (`Scanning/Price/`)

After the OCR → image-AI migration this layer no longer parses pixels. It holds source-of-truth domain logic over already-clean fields, plus the small text helpers the validator's deterministic re-read uses.

- `PriceParsingService.swift`
  - unit-price math (`normalize`, `unitPrice`)
  - receipt detection (`looksLikeReceipt`)
  - shared regex/token vocabulary and text predicates (`containsPriceSignal`, `isLikelyShelfCode/SKU`, `containsExplicitSizeToken`, `isDescriptiveObservation`)
- `Parsing/PriceCandidateScorer.swift`
  - candidate extraction and kind classification over `[any TextObservation]` (used by the validator re-read)
- `Parsing/PriceParsingUnitResolver.swift`
  - unit detection and quantity inference (text + observation methods)
- `Parsing/PriceParsingItemNameResolver.swift`
  - item-name extraction and canonical name composition
- `Parsing/PriceParsingConfidenceResolver.swift`
  - the surviving pure helpers: `sourceLineIndexes`, `isProductDescriptor`, `containsPhoneNumber`, `looksLikeDateLine`
- `PriceEntryRepository.swift`
  - translates a reviewable draft into a saved `PriceEntry`; runs `normalize` + `ItemKeyNormalizer.normalize`, persists photo + review metadata

### Store Layer

- `StoreCatalog.swift`
  - store metadata and reference source
- `StoreDetectionService.swift`
  - store inference and nearby-store matching (MapKit)
- `ScanSessionStore.swift`
  - scan-session-level state for store selection and related context
- `StoreSelectionSheet.swift`
  - UI for confirming or changing inferred store

### Camera Layer (`Scanning/Camera/`)

- `CameraController.swift`
  - owns `AVCaptureSession`, `AVCapturePhotoOutput`, the torch, startup, and still capture on a private `sessionQueue`
  - launch-performance features adopted from the WWDC 2026 "responsive camera" guidance: automatic deferred start (`session.automaticallyRunsDeferredStart`, `photoOutput.isDeferredStartEnabled` when supported), responsive capture (`isResponsiveCaptureEnabled`), `maxPhotoQualityPrioritization = .quality`, duplicate-shutter suppression while a capture continuation is in flight, and `isCaptureReady` published after `sessionDidRunDeferredStart`
  - the torch is owned here (real hardware state), not optimistic view state; the shutter is intentionally NOT gated on `isCaptureReady` so responsive capture keeps early taps useful
- `CameraPreviewView.swift`
  - hosts `AVCaptureVideoPreviewLayer` (`resizeAspectFill`), kept non-deferred (`isDeferredStartEnabled = false`); Prixio does not use `AVCaptureVideoDataOutput`
- Remaining camera-performance work (launch/capture signposts + Instruments measurement, splitting camera prep from store/location loading on the scan-startup critical path, system-pressure observation, and real-device timing/thermal validation) is tracked in `OutstandingWork.md`.

### Shared UI

- `ConfirmationSheet.swift`
  - final review, edit, and save UI for the extracted result
- `ImageViewer.swift`
  - inspect captured or imported image
- `ToastView.swift`
  - lightweight transient messaging
- `ScannerGuideOverlay.swift`
  - camera guidance overlay

## Pipeline Design Principles

- The model reads the image; deterministic app code decides whether the result is safe to save.
- Validation re-reads the model's OWN structured output (transcription + candidates) for internal consistency — it does not re-examine the original pixels.
- Geometry is gone; the model emits flat fields + `relevantText`, not bounding boxes.
- `Decimal` is used for money and quantity math.
- Confidence and review state should reflect actual uncertainty, not false precision.

## Important Pipeline Concepts

### Price Candidates Are An Evidence List

`LLMOCRResult` is contracted to enumerate *every* distinct price (regular, sale, member, per-unit, deposit, multi-buy) as a separate candidate. So 2–5 candidates is the **normal, clean** case — candidate count alone is NOT competition. Genuine competition routes to review only via the model's own `.multipleCompetingPrices` / `.priceOwnershipUncertain` issues.

### Grounding Cross-Check

`PriceExtractionValidator` flags the chosen primary price only when it is **ungrounded** — absent from both the model's own candidates and the deterministic `PriceCandidateScorer` re-read of `relevantText`. It can also clear `.missingUnit` when the model dropped a unit that a unit token in its own transcription recovers.

### Price Kinds

`PriceCandidate` includes a typed `PriceKind`, so prices can be distinguished:
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

The app does not assume a parse is safe just because fields are filled. `OCRReview` can surface issues like:
- no price candidates
- multiple competing prices
- missing item name
- missing unit
- missing quantity
- low confidence

Severe issues (no price, competing prices, possible multi-product scan) force `reviewRequired`; non-severe issues are `reviewRecommended`; an empty issue set is `clean` — even though the image-AI path always records `usedFoundationModel = true` for audit.

## Current Data Flow

1. User captures or imports an image.
2. `ScanViewModel` calls `image.extractPriceInformation(context:)`, which returns an `LLMOCRResult` (or `nil` if the model is unavailable, surfaced as a toast).
3. `PriceDraftBuilder.makeDraft` maps the result into a `PriceEntryDraft`, attaching the review produced by `PriceExtractionValidator`.
4. `ReceiptCaptureClassifier` decides whether to suppress store autofill; `matchStoreCandidate` / `applyInferredStore` set the store context.
5. The user reviews the result in `ConfirmationSheet`.
6. `PriceEntryRepository` persists the normalized draft into SwiftData.

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
- `PriceEntryRepository` translates reviewable extraction output into saved records
- `ShoppingListRepository` owns shopping-list persistence operations

## Testing Map

Extraction and pricing are tested with fixed `LLMOCRResult` fixtures — automated tests never depend on live model extraction (model availability and sampling are not stable CI inputs). Live image-AI extraction is covered by manual/device QA.

Important test files and what they guard:

- `PriceExtractionValidatorTests.swift`
  - review-state outcomes from `LLMOCRResult` fixtures: clean single/multi-candidate, missing price, model-reported competition, ungrounded primary, parser-recovered unit
- `PriceDraftBuilderTests.swift`
  - field copy, candidate mapping (priority order, confidence 1.0, empty source indexes), attached review
- `ReceiptCaptureClassifierTests.swift`
  - scene + text receipt suppression
- `ParserEvaluationTests.swift`
  - fixture-driven end-to-end evaluation of draft/review outcomes by failure class
- `PriceParsingServiceDataSanitation.swift`
  - `PriceCandidateScorer` candidate typing / save-penalty behavior over `PlainTextObservation`
- `PriceToolTests.swift`
  - `NormalizeUnitPriceTool` math, `ResolveUnitAndQuantityTool` phrases, `ItemHistoryTool` count/median/newest over an in-memory SwiftData container
- `OCRReviewStateTests.swift`
  - `OCRReview.state` contracts (usedFoundationModel is metadata, severity mapping)
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
- `CapturedOCRFixtures.swift` / `ImageFixtureTestSupport.swift`
  - shared fixtures: `LLMOCRResult.fixture` factory, `PlainTextObservation` helpers, and image loading retained for manual/device QA

Manual QA / release-facing docs:

- `PhysicalDeviceQATestPlan.md`
  - manual physical-device test checklist across Scan, Compare, Shopping List, permissions, routing, and resilience

## Known Gotchas

- The model is the only extractor; if `SystemLanguageModel` is unavailable, extraction returns `nil` and the scan ends with an "unavailable" toast (no Vision fallback exists).
- Multiple price candidates is the normal clean case — do not treat candidate count as competition.
- Store detection can be indirectly affected by extraction, because the model's `relevantText` feeds store inference and receipt suppression.
- Compare and Shopping List read price intelligence from `PriceEntry`; do not persist duplicate "best price" state.
- Shopping List defaults to the visible `"This trip"` list, but the persistence model is already multi-list-ready.
- Shopping List scan launches prefer the row's best-store name first, then fall back to the trip winner if needed.
- Shopping List row distance depends on real saved store coordinates; rows without coordinates should omit distance instead of showing placeholders.
- `CurrencyFormatter.shared.string` inserts a grouping separator for values ≥ 1000, which `PriceEntryDraft.parsedPrice` then rejects — a pre-existing edge case for ≥ $1000 prices.

## Guidance For Future LLM Sessions

- Keep extraction (model) and decision-making (deterministic app code) separate; add new guardrails in the `Pipeline/` steps, not in the model prompt alone.
- Use `LLMOCRResult` fixtures for automated tests; reserve live extraction for manual/device QA.
- The four `Tool` adapters are shared infrastructure for future agents — wire them into agent sessions, not the single-photo Capture flow.
- Reuse `PriceInsightEngine` and `ItemKeyNormalizer` rather than adding flow-specific copies of pricing or grouping logic.
- If editing Compare or Shopping List behavior, verify both build cleanly because they now share derived price logic.
