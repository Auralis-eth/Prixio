# Prixio Project Memory

## Project Overview
Prixio is an iOS grocery price capture app. The app now has three connected product flows:

- `Scan` captures or imports a shelf-tag photo, runs OCR, infers item/price/unit/store, and saves a normalized `PriceEntry`.
- `Compare` turns saved entries into browseable item comparisons and per-store ranking views.
- `Shopping List` turns saved price history into a trip checklist with per-item best-store suggestions and a scan-refresh loop.

## Architecture Decisions
- `PrixioApp` owns the SwiftData container for `PriceEntry`, `StoreChain`, `StoreLocation`, `ShoppingList`, and `ShoppingListItem`.
- `MainView` is the app shell and uses an app-level `AppNavigationModel` to coordinate tab selection and cross-tab scan launches.
- `ScanRootView` remains the scanner workflow entry point.
- `CompareViewModel` and `ShoppingListViewModel` are view-model layers over a shared derived domain.
- `PriceInsightEngine` is the shared pricing logic seam for staleness, best-store selection, trip aggregation, and compare-side ranking inputs.
- OCR parsing is heuristic-first. Vision provides raw text, then deterministic parsing picks likely prices and units before any future Foundation Models enrichment.

## Important Conventions
- SwiftUI-first structure with state-driven flows.
- Prefer async work over callback-heavy APIs.
- Use `Decimal` for price and quantity math.
- Keep scanner/parser changes tight in scope because the OCR and parsing pipeline is already deep.
- Keep Compare and Shopping List price logic in shared pure helpers instead of duplicating it in views.
- Reuse `ItemKeyNormalizer` for anything that needs item-name grouping or lookup.

## Build And Run
- Open the project in Xcode and use the active `Prixio` scheme.
- Build with Xcode or the MCP `BuildProject` tool.
- Unit tests live in `PrixioTests` and use Apple’s `Testing` framework.
- The feature-side regression suite currently lives mostly in:
  - `ShoppingListDomainTests`
  - `TripRecommendationTests`
  - `CompareFlowViewModelTests`
  - `ShoppingListViewModelTests`
- UI smoke tests live in `PrixioUITests`.

## Quirks And Gotchas
- OCR output is noisy, and price fragments can be split across lines.
- Store detection mixes nearby search results with OCR-derived hints, so parser regressions can affect store autofill indirectly.
- Compare and Shopping List intentionally read from `PriceEntry` rather than persisting duplicated pricing intelligence.
- Shopping List is multi-list-ready at the model layer, but the UI currently exposes a single default list.
- Shopping List scan nudges prefill the row's best-store chain first and fall back to the trip winner when needed.
