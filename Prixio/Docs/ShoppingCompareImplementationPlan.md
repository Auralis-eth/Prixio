# Shopping List And Compare Implementation Plan

## Purpose

This document records the recommended implementation strategy for adding the Compare flow and the Shopping List / Trip Optimizer flow to Prixio.

The app already has the important raw material:

- `PriceEntry` persists normalized item keys, normalized unit prices, timestamps, store snapshots, and coordinates.
- The scanner save path already produces the data needed to power comparisons and trip recommendations.
- The current gap is mostly UI, derived-query logic, and a small amount of new persistence for list structure.

## Current Codebase Read

Observed state of the app:

- `Core/MainView.swift` is still scanner-first and uses placeholders for the other tabs.
- `Core/PrixioApp.swift` only registers `PriceEntry`, `StoreChain`, and `StoreLocation` in the SwiftData container.
- `Scanning/Price/PriceEntryRepository.swift` already saves:
  - normalized item keys
  - normalized unit prices
  - normalized unit types
  - store chain and store location IDs
  - store snapshot names
  - store coordinates
  - parser metadata
  - photo path references

Conclusion:

- Compare and Shopping List should be implemented primarily as read/query layers on top of the existing `PriceEntry` data.
- New persistence is needed only for shopping-list structure and app-level navigation state.

## Recommended Product Structure

Recommended tab structure:

- `Scan`
- `Compare`
- `Shopping List`
- `Settings`

Recommended MVP decisions:

- Keep `Settings` as the fourth tab.
- Support delete in Compare item detail; defer edit unless it is already being added elsewhere.
- Support a single active list in the UI for MVP.
- Keep the data model archive-capable so multi-list support can be added later without rewriting persistence.
- When Shopping List launches Scan, prefill the row's best-store chain first and use the trip-winner chain only as a fallback.

## Architecture

The cleanest implementation is three coordinated additions:

1. Compare feature
2. Shopping List feature
3. A tiny app-level navigation model for cross-tab launches

### Guiding Principle

Keep price intelligence derived, keep list structure persisted, and keep cross-tab launching centralized.

### New Core Types

Recommended persisted models:

- `ShoppingList`
- `ShoppingListItem`

Recommended derived or in-memory types:

- `StalenessBucket`
- `ComparisonDisplayMode`
- `BestStoreSuggestion`
- `StoreComparisonRow`
- `TripRecommendation`
- `ShoppingListRowData`
- `ScanLaunchRequest`
- `AppNavigationModel`

### Recommended Folder Layout

- `Prixio/Core/Models/`
- `Prixio/Core/Navigation/`
- `Prixio/Core/Derived/`
- `Prixio/Compare/`
- `Prixio/Shopping/`

## Phase Plan

## Phase 1: App Shell And Navigation

Goal:

- Replace placeholders with real tabs.
- Add a cross-tab launch path so Shopping List can send the user into Scan with prefilled context.

Implementation:

- Replace placeholder tabs in `Core/MainView.swift` with:
  - `ScanRootView`
  - `CompareRootView`
  - `ShoppingListRootView`
  - `PlaceholderTabView` or real `Settings` later
- Add `AppNavigationModel` with:
  - `selectedTab`
  - `pendingScanLaunchRequest`
- Inject `AppNavigationModel` from `Core/PrixioApp.swift`
- Expand `.modelContainer(for:)` to include `ShoppingList` and `ShoppingListItem`

Recommended types:

```swift
enum AppTab {
    case scan
    case compare
    case shopping
    case settings
}

struct ScanLaunchRequest: Equatable {
    let itemName: String
    let preferredChainName: String?
}
```

Scanner integration:

- Extend `ScanViewModel` with an API that applies a `ScanLaunchRequest`
- In `ScanRootView`, observe the app navigation model
- When a pending launch request exists:
  - switch to Scan
  - prefill draft item name
  - prefill preferred store chain if present
- Do not auto-trigger capture
- Do not auto-open confirmation UI

Why this matters:

- The Shopping List spec requires "Scan now" to open the scanner with item and optional store prefilled.
- Doing that without an app-level coordinator would create brittle tab coupling.

## Phase 2: Shopping List Persistence

Goal:

- Add the minimal persisted structure required for lists while keeping all price intelligence derived.

Add:

- `Core/Models/ShoppingList.swift`
- `Core/Models/ShoppingListItem.swift`

Recommended persisted fields:

### ShoppingList

- `id: UUID`
- `name: String`
- `createdAt: Date`
- `updatedAt: Date`
- `isArchived: Bool`
- `items: [ShoppingListItem]`

### ShoppingListItem

- `id: UUID`
- `itemKey: String`
- `displayName: String`
- `quantityNote: String?`
- `isDone: Bool`
- `doneAt: Date?`
- `createdAt: Date`

Recommendation:

- Use a SwiftData relationship from `ShoppingList` to `ShoppingListItem`
- Do not persist derived fields like best store, best price, or staleness
- Use a helper or repository to fetch-or-create the single default list: `"This trip"`

## Phase 3: Shared Derived Pricing Domain

Goal:

- Centralize the pricing, staleness, store suggestion, and trip recommendation logic so both features use the same rules.

Add shared logic for:

- `StalenessBucket`
- `ageDays(from:)`
- `stalenessBucket(for:)`
- price display formatting for normalized and package modes
- distance calculation
- best-store selection per item
- trip winner aggregation
- comparison row building for Compare item detail

Important rule:

- Do not place this logic inside SwiftUI views.
- Keep it as pure structs and functions so it is testable.

Recommended shared APIs:

- `computeBestStoreForItem(itemKey:allEntries:now:)`
- `computeTripWinner(suggestions:totalItems:)`
- `buildComparisonRows(entries:mode:userLocation:now:)`

### Shared Staleness System

Buckets:

- `fresh`: 0...7 days
- `aging`: 8...30 days
- `stale`: 31...90 days
- `veryStale`: 90+ days

This exact system should be reused across Compare and Shopping List.

## Phase 4: Compare Flow

Goal:

- Turn saved `PriceEntry` records into a browse/search/detail flow.

Add:

- `Compare/CompareRootView.swift`
- `Compare/CompareViewModel.swift`
- `Compare/ItemDetailView.swift`
- `Compare/StoreComparisonRow.swift`
- `Compare/StoreRowView.swift`
- `Compare/SuggestedComparisonCard.swift`
- `Compare/EntryDetailSheet.swift`

### Screen B: Compare Root

Use:

- `@Query(sort: \PriceEntry.capturedAt, order: .reverse)` for recent entries
- in-memory grouping for:
  - suggested comparison cards
  - recent captures
  - all tracked items
  - search filtering

Behavior:

- No entries: show empty state with scan CTA
- Search active: show live filtered results
- Search empty:
  - suggested comparison cards
  - recent captures
  - browse list

Search rules:

- filter on `itemNameNormalized`
- optionally match `itemNameRaw`
- debounce in view model

### Screen C: Item Detail

Use:

- query all entries for selected item key
- build `StoreComparisonRow` values in memory
- segmented control for:
  - `perUnit`
  - `perPackage`

Default sort:

1. staleness bucket
2. price ascending
3. `capturedAt` descending

Important implementation note:

- Prefer store snapshot names and coordinates from `PriceEntry`
- Use `StoreChain` / `StoreLocation` lookups as enrichment, not as a hard requirement

Trend rules:

- compare the latest two comparable entries for the same store and display mode
- apply a 2% deadband
- return up / down / flat state

Entry detail sheet should show:

- image preview
- captured timestamp
- normalization breakdown when available
- delete action
- edit action can be deferred

## Phase 5: Shopping List Flow

Goal:

- Add a working trip-oriented checklist powered by derived `PriceEntry` intelligence.

Add:

- `Shopping/ShoppingListRootView.swift`
- `Shopping/ShoppingListViewModel.swift`
- `Shopping/ShoppingListRowData.swift`
- `Shopping/TripRecommendation.swift`
- `Shopping/TripOptimizerCard.swift`
- `Shopping/ShoppingListRowView.swift`
- `Shopping/ShoppingListItemDetailSheet.swift`
- `Shopping/AddShoppingListItemSheet.swift`
- `Shopping/ScanNudgeSheet.swift`
- `Shopping/ShoppingListRepository.swift`

### Root Data Strategy

Recommended fetch shape:

- fetch the active default list
- split items into active and completed
- fetch recent `PriceEntry` records once
- filter matching item keys in memory
- recompute derived rows in memory

Recommended time window:

- fetch last 90 days of `PriceEntry`
- allow older display fallback only if the item has no recent entry

### Important Mapping Rule

Do not use `zip(items, suggestions)` when building list rows.

Reason:

- items without suggestions would be dropped
- row ordering could become incorrect

Instead:

- build a lookup keyed by `itemKey`
- map every list item to a row
- allow suggestion to be `nil`

### Checklist Row Data Should Include

- underlying `ShoppingListItem`
- optional `BestStoreSuggestion`
- display price string
- store display name
- age display
- staleness bucket
- faded / warning flags
- optional distance display
- optional quantity note
- scan-nudge eligibility

### Trip Optimizer Logic

Algorithm:

- compute best-store suggestion for each active item
- group winners by store chain
- count wins
- count stale items separately

Display rules:

- strong winner when the top chain wins at least 60% of active items
- otherwise show split-trip state
- if too little useful data exists, show insufficient-data state

Recommended insufficient-data rule:

- require at least 2 active items
- require at least 2 items with valid suggestions
- otherwise render the card as insufficient data

### Completed Section

Use:

- `DisclosureGroup`
- collapsed by default

Optional MVP add-on:

- `Clear completed`

### Add Item Sheet

Requirements:

- typeahead over existing tracked items from `PriceEntry`
- support selection of known item keys
- support freeform entry
- optional quantity note

Important rule:

- freeform item creation must use the same normalization logic as `PriceEntry` saving
- do not duplicate item-key normalization rules in multiple places

## Phase 6: Scan Nudge Loop

Goal:

- Turn list completion into a data-refresh loop without blocking the user.

Recommended behavior:

- when a user checks off an item:
  - mark it done immediately
  - then decide whether to present a scan nudge
- if price data is fresh, do nothing beyond haptics
- if price data is stale or missing, show the nudge sheet

Recommended logic:

```swift
let shouldNudge = suggestion.map {
    $0.ageDays > 30 || $0.stalenessBucket == .veryStale
} ?? true
```

Important note:

- the fallback must be `true`, not `false`, because missing price data should also trigger the nudge path

When the user taps `Scan now`:

- dismiss the nudge sheet
- switch to the Scan tab
- send a `ScanLaunchRequest`
- prefill item name
- prefill best-store chain if available
- otherwise prefill trip-winner chain if available

## Phase 7: Shared Normalization Cleanup

Before or during feature work, centralize two cross-cutting rules:

1. item-key normalization
2. staleness rules

Recommended extraction:

- `ItemKeyNormalizer.normalize(_:)`
- `StalenessPolicy.ageDays(from:now:)`
- `StalenessPolicy.bucket(for:)`

Source of current duplication risk:

- `Scanning/Price/PriceEntryRepository.swift` currently normalizes item names locally
- Compare and Shopping List will need the exact same logic

Reason to centralize:

- avoids subtle mismatches between saved entries, search, add-item, and trip recommendation behavior

## Phase 8: Testing

Testing should focus on domain correctness first, then view-model behavior.

Recommended new test files:

- `ShoppingListDomainTests.swift`
- `TripRecommendationTests.swift`
- `CompareFlowViewModelTests.swift`
- `ShoppingListViewModelTests.swift`

Recommended test coverage:

- item-key normalization reuse
- staleness thresholds
- best-store selection in normalized mode
- best-store selection in package mode
- recent-vs-stale fallback behavior
- recency tiebreaker behavior
- mixed unit-family behavior
- trip winner at exactly the 60% threshold
- split-trip behavior
- insufficient-data behavior
- row construction when no suggestion exists
- scan nudge for stale item
- scan nudge for missing data
- search matching
- trend deadband behavior
- distance omission when location is unavailable

Recommendation:

- prioritize unit and view-model tests
- defer UI automation until the domain contracts are stable

## File Delivery Map

### Existing Files To Modify

- `Prixio/Core/PrixioApp.swift`
- `Prixio/Core/MainView.swift`
- `Prixio/Scanning/ScanRootView.swift`
- `Prixio/Scanning/ScanViewModel.swift`
- `Prixio/Scanning/Price/PriceEntryRepository.swift`

### New Persisted Model Files

- `Prixio/Core/Models/ShoppingList.swift`
- `Prixio/Core/Models/ShoppingListItem.swift`

### New Shared Logic Files

- `Prixio/Core/Models/StalenessBucket.swift`
- `Prixio/Core/Navigation/AppNavigationModel.swift`
- `Prixio/Core/Derived/ItemKeyNormalizer.swift`
- `Prixio/Core/Derived/PriceInsightEngine.swift`

### New Compare Files

- `Prixio/Compare/CompareRootView.swift`
- `Prixio/Compare/CompareViewModel.swift`
- `Prixio/Compare/ItemDetailView.swift`
- `Prixio/Compare/StoreComparisonRow.swift`
- `Prixio/Compare/StoreRowView.swift`
- `Prixio/Compare/SuggestedComparisonCard.swift`
- `Prixio/Compare/EntryDetailSheet.swift`

### New Shopping Files

- `Prixio/Shopping/ShoppingListRootView.swift`
- `Prixio/Shopping/ShoppingListViewModel.swift`
- `Prixio/Shopping/ShoppingListRowData.swift`
- `Prixio/Shopping/TripRecommendation.swift`
- `Prixio/Shopping/TripOptimizerCard.swift`
- `Prixio/Shopping/ShoppingListRowView.swift`
- `Prixio/Shopping/ShoppingListItemDetailSheet.swift`
- `Prixio/Shopping/AddShoppingListItemSheet.swift`
- `Prixio/Shopping/ScanNudgeSheet.swift`
- `Prixio/Shopping/ShoppingListRepository.swift`

## Recommended Delivery Order

This is the order that keeps each milestone coherent and reduces rework:

1. Add shopping-list models and register them in the model container.
2. Add the app navigation model and replace placeholder tabs.
3. Build the shared derived pricing and staleness engine with tests.
4. Build the Compare root and item detail flow on top of that engine.
5. Build the Shopping List root, add flow, and completed-items flow.
6. Add trip optimization and scan nudge.
7. Wire cross-tab scanner launch and prefill.
8. Update `Journal.md` as the implementation reveals architectural or product gotchas.

## Open Product Decisions

Only a few decisions still need explicit confirmation:

1. Should the tab bar now be `Scan / Compare / Shopping List / Settings`?
2. For Compare row detail, is delete-only enough for MVP, or should edit be included immediately?
3. Should the UI remain single-list for MVP while the data model is prepared for future multi-list support?
4. When Shopping List launches Scan, should the prefilled store prefer the row's best store over the trip winner when they differ?

Recommended answers:

1. Yes
2. Delete-only for MVP
3. Yes
4. Prefer row best-store first, trip winner second

## Summary

The app already has the hard part of the data foundation. The implementation should avoid inventing separate pricing logic in Compare and Shopping List, and instead build both flows on one shared derived-insight layer that reads from `PriceEntry`. The only new persisted domain should be shopping-list structure and the minimal app-level navigation state required to support the scan-refresh loop.
