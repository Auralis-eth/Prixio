# Shopping Compare Execution Checklist

## Locked Product Decisions

These decisions are now fixed for implementation unless explicitly changed later:

- Tab bar: `Scan / Compare / Shopping List / Settings`
- Compare MVP detail actions: delete only
- Shopping data model: multi-list-ready from day one
- Shopping List -> Scan prefill: row best-store first, trip winner fallback

## Delivery Strategy

Build order is optimized for:

- smallest possible integration risk
- reuse of one shared pricing insight layer
- early compileable milestones
- milestone-level verification instead of one giant end-state merge

Each milestone below is intended to be buildable before moving to the next one.

## Exact File Creation Order

Create files in this order unless a discovered compiler dependency forces a minor adjustment.

1. `Prixio/Core/Models/ShoppingList.swift`
2. `Prixio/Core/Models/ShoppingListItem.swift`
3. `Prixio/Core/Models/StalenessBucket.swift`
4. `Prixio/Core/Derived/ItemKeyNormalizer.swift`
5. `Prixio/Core/Derived/PriceInsightEngine.swift`
6. `Prixio/Core/Navigation/AppNavigationModel.swift`
7. `Prixio/Compare/StoreComparisonRow.swift`
8. `Prixio/Compare/CompareViewModel.swift`
9. `Prixio/Compare/SuggestedComparisonCard.swift`
10. `Prixio/Compare/StoreRowView.swift`
11. `Prixio/Compare/EntryDetailSheet.swift`
12. `Prixio/Compare/ItemDetailView.swift`
13. `Prixio/Compare/CompareRootView.swift`
14. `Prixio/Shopping/TripRecommendation.swift`
15. `Prixio/Shopping/ShoppingListRowData.swift`
16. `Prixio/Shopping/ShoppingListRepository.swift`
17. `Prixio/Shopping/ShoppingListViewModel.swift`
18. `Prixio/Shopping/TripOptimizerCard.swift`
19. `Prixio/Shopping/ShoppingListRowView.swift`
20. `Prixio/Shopping/ShoppingListItemDetailSheet.swift`
21. `Prixio/Shopping/AddShoppingListItemSheet.swift`
22. `Prixio/Shopping/ScanNudgeSheet.swift`
23. `Prixio/Shopping/ShoppingListRootView.swift`
24. `PrixioTests/ShoppingListDomainTests.swift`
25. `PrixioTests/TripRecommendationTests.swift`
26. `PrixioTests/CompareFlowViewModelTests.swift`
27. `PrixioTests/ShoppingListViewModelTests.swift`

## Milestone 1: Data Foundation

### Goal

Add the persisted list models and shared derived domain needed by both Compare and Shopping List.

### Files Created

- `Prixio/Core/Models/ShoppingList.swift`
- `Prixio/Core/Models/ShoppingListItem.swift`
- `Prixio/Core/Models/StalenessBucket.swift`
- `Prixio/Core/Derived/ItemKeyNormalizer.swift`
- `Prixio/Core/Derived/PriceInsightEngine.swift`

### Files Modified

- `Prixio/Core/PrixioApp.swift`
- `Prixio/Scanning/Price/PriceEntryRepository.swift`

### Implementation Tasks

- Add `ShoppingList` SwiftData model
- Add `ShoppingListItem` SwiftData model
- Make model multi-list-ready:
  - `ShoppingList` owns items via relationship
  - include `isArchived`
  - include timestamps
- Extract item normalization into `ItemKeyNormalizer`
- Replace inline normalization in `PriceEntryRepository` with shared normalizer
- Add `StalenessBucket`
- Add shared staleness age calculation
- Add shared insight engine with pure functions for:
  - best store per item
  - trip winner
  - comparison row assembly support
- Register `ShoppingList` and `ShoppingListItem` in the app model container

### Milestone Acceptance Criteria

- Project builds with the new SwiftData models registered
- `PriceEntryRepository` uses shared normalization instead of its own local logic
- Shared staleness logic exists in one place only
- Shared insight engine is pure and view-independent
- No UI is required yet

### Acceptance Tests

- `ShoppingListDomainTests`
  - item-key normalization is stable and reused
  - staleness thresholds map correctly:
    - 0...7 => `fresh`
    - 8...30 => `aging`
    - 31...90 => `stale`
    - 91+ => `veryStale`
  - best-store selection prefers normalized pricing when available
  - package-mode fallback works when normalized price is absent
  - recent entries beat stale entries when both exist
  - recency breaks ties
  - missing entries return `nil`

## Milestone 2: App Shell And Cross-Tab Navigation

### Goal

Replace placeholders with real destinations and create the cross-tab launch mechanism needed by Shopping List.

### Files Created

- `Prixio/Core/Navigation/AppNavigationModel.swift`

### Files Modified

- `Prixio/Core/MainView.swift`
- `Prixio/Core/PrixioApp.swift`
- `Prixio/Scanning/ScanRootView.swift`
- `Prixio/Scanning/ScanViewModel.swift`

### Implementation Tasks

- Add `AppNavigationModel`
- Add selected-tab state and pending scan launch request
- Update `MainView` to use:
  - `ScanRootView`
  - `CompareRootView`
  - `ShoppingListRootView`
  - `PlaceholderTabView` for Settings if Settings is not implemented
- Inject the navigation model from the app root
- Extend `ScanViewModel` to apply a pending scan launch request
- In `ScanRootView`, consume pending requests and prefill:
  - item name
  - preferred chain name

### Milestone Acceptance Criteria

- App launches with four real tabs
- Compare and Shopping List tabs are routable even if their UI is still skeletal
- A pending scan launch request can switch to Scan and prefill draft state
- Scan prefill does not auto-trigger capture or confirmation flow

### Acceptance Tests

- `ShoppingListViewModelTests` or dedicated navigation tests
  - scan launch request stores item name
  - preferred chain is optional
  - applying a launch request updates scan draft correctly
  - launch request clears after consumption

## Milestone 3: Compare Domain And View Model

### Goal

Build the compare-side row derivation, search behavior, and item-detail ranking logic before styling the screen fully.

### Files Created

- `Prixio/Compare/StoreComparisonRow.swift`
- `Prixio/Compare/CompareViewModel.swift`

### Files Modified

- `Prixio/Core/DistanceFormatter.swift`
- `Prixio/Core/CurrencyFormatter.swift` if shared display helpers are needed

### Implementation Tasks

- Add compare display mode enum if not included in shared domain
- Build compare root view model that derives:
  - search results
  - recent captures
  - browse rows
  - suggested comparison cards
- Build store comparison rows for item detail
- Add trend calculation with deadband
- Add mixed-unit-family detection
- Add distance display derivation when location exists

### Milestone Acceptance Criteria

- Compare view model can derive all root-screen sections from `PriceEntry`
- Item detail row ranking works for both per-unit and per-package modes
- Stale rows are identifiable and sortable
- Distance is omitted when location is unavailable
- Trend indicator suppresses noise within deadband

### Acceptance Tests

- `CompareFlowViewModelTests`
  - search returns matching items for normalized keys
  - empty query returns browse mode
  - suggested cards only appear for items tracked at 2+ stores
  - item detail rows sort by staleness, then price, then recency
  - trend badge returns flat within 2%
  - mixed-unit-family note appears when applicable
  - distance value is absent when no user location exists

## Milestone 4: Compare UI

### Goal

Ship the full Compare experience.

### Files Created

- `Prixio/Compare/SuggestedComparisonCard.swift`
- `Prixio/Compare/StoreRowView.swift`
- `Prixio/Compare/EntryDetailSheet.swift`
- `Prixio/Compare/ItemDetailView.swift`
- `Prixio/Compare/CompareRootView.swift`

### Files Modified

- `Prixio/Core/MainView.swift`

### Implementation Tasks

- Build Compare root screen
- Add `.searchable`
- Add suggested cards section
- Add recent captures section
- Add browse section
- Add empty states
- Build item detail screen with:
  - segmented toggle
  - ranked store rows
  - stale visual system
  - optional distance
  - trend badge
- Add row detail sheet
- Add delete action in row detail sheet

### Milestone Acceptance Criteria

- Compare tab is fully navigable
- Search updates live
- Root screen supports:
  - empty state
  - search results
  - suggestions
  - recent captures
  - browse items
- Item detail supports unit mode switching and immediate re-sort
- Row detail sheet supports delete

### Acceptance Tests

- Build verification
- Manual QA checklist:
  - tapping card navigates to item detail
  - tapping recent capture navigates to item detail
  - tapping browse item navigates to item detail
  - unit toggle reorders rows immediately
  - stale rows show explicit stale language
  - delete removes entry and updates UI state

## Milestone 5: Shopping List Repository And Domain

### Goal

Build the persisted list access layer and row derivation before building full UI.

### Files Created

- `Prixio/Shopping/TripRecommendation.swift`
- `Prixio/Shopping/ShoppingListRowData.swift`
- `Prixio/Shopping/ShoppingListRepository.swift`
- `Prixio/Shopping/ShoppingListViewModel.swift`

### Files Modified

- `Prixio/Core/Derived/PriceInsightEngine.swift`

### Implementation Tasks

- Add repository to fetch-or-create default list
- Add item add / delete / toggle / clear-completed operations
- Add trip recommendation enum
- Add row-data shape for checklist rows
- Build view model recomputation pipeline:
  - active items
  - completed items
  - suggestion lookup
  - trip recommendation
- Ensure rows are built by mapping every item, not by zipping with suggestions
- Add scan-nudge eligibility logic

### Milestone Acceptance Criteria

- Default list is created automatically if none exists
- Items can be added to and removed from the list in the repository layer
- View model derives active rows, completed rows, and trip recommendation
- Missing suggestions do not cause rows to disappear
- Nudge eligibility is true for stale or missing data

### Acceptance Tests

- `TripRecommendationTests`
  - strong winner when top chain wins at least 60%
  - split trip when threshold is not met
  - insufficient data when too few priced suggestions exist
  - stale item count is included correctly
- `ShoppingListViewModelTests`
  - active and completed rows split correctly
  - rows with no suggestions still appear
  - nudge is true when suggestion is missing
  - nudge is true when suggestion is stale
  - nudge is false for fresh suggestions

## Milestone 6: Shopping List UI

### Goal

Ship the working checklist, add flow, completed flow, and trip optimizer card.

### Files Created

- `Prixio/Shopping/TripOptimizerCard.swift`
- `Prixio/Shopping/ShoppingListRowView.swift`
- `Prixio/Shopping/ShoppingListItemDetailSheet.swift`
- `Prixio/Shopping/AddShoppingListItemSheet.swift`
- `Prixio/Shopping/ShoppingListRootView.swift`

### Files Modified

- `Prixio/Core/MainView.swift`

### Implementation Tasks

- Build shopping list root screen
- Add empty states:
  - no items
  - all items completed
- Add trip optimizer card
- Add active checklist section
- Add completed disclosure section
- Add item-detail sheet
- Add add-item sheet with typeahead
- Support known-item and freeform entry
- Support optional quantity note
- Add delete action on rows

### Milestone Acceptance Criteria

- Shopping List tab is usable end to end without scan nudge yet
- Users can add freeform items
- Users can add known tracked items via typeahead
- Active items and completed items render in separate sections
- Trip optimizer card updates when the list changes
- Stale rows show explicit staleness presentation

### Acceptance Tests

- Manual QA checklist:
  - add first item from empty state CTA
  - add known item from typeahead
  - add freeform item
  - completed section collapses and expands
  - trip optimizer changes after adding or deleting items
  - all-complete state appears when every item is checked

## Milestone 7: Scan Nudge And Freshness Loop

### Goal

Close the loop from Shopping List back into Scan.

### Files Created

- `Prixio/Shopping/ScanNudgeSheet.swift`

### Files Modified

- `Prixio/Shopping/ShoppingListRootView.swift`
- `Prixio/Shopping/ShoppingListViewModel.swift`
- `Prixio/Core/Navigation/AppNavigationModel.swift`
- `Prixio/Scanning/ScanRootView.swift`
- `Prixio/Scanning/ScanViewModel.swift`

### Implementation Tasks

- Present scan nudge on stale or missing data when checking off item
- Commit check-off before prompting
- Use row best-store chain as primary prefill
- Use trip winner chain as fallback when row best-store is unavailable
- Route into Scan tab with pending launch request
- Clear request after it is consumed

### Milestone Acceptance Criteria

- Checking off an item with fresh data completes silently
- Checking off an item with stale data presents the nudge
- Checking off an item with no price data also presents the nudge
- `Scan now` routes to Scan
- Scan draft is prefilled with item name
- Preferred chain follows row-best-store-first rule

### Acceptance Tests

- `ShoppingListViewModelTests`
  - fresh item does not request nudge
  - stale item requests nudge
  - missing-suggestion item requests nudge
- Manual QA checklist:
  - tapping `Scan now` switches tabs
  - item name appears prefilled in Scan
  - chain prefill uses row best store when available
  - chain falls back to trip winner otherwise

## Milestone 8: Hardening, Build Validation, And Docs

### Goal

Make the feature safe to merge and leave an accurate project record.

### Files Modified

- `Prixio/AGENTS.md`
- `Prixio/Journal.md`
- `Prixio/OutstandingWork.md` if scope is deferred

### Implementation Tasks

- Run build validation
- Run targeted tests for new domain and view-model coverage
- Fix diagnostics
- Update project memory if architecture or conventions changed
- Update journal with implementation lessons and any gotchas
- Move post-MVP leftovers into `OutstandingWork.md`

### Milestone Acceptance Criteria

- Project builds cleanly
- New tests pass or any harness limitation is documented precisely
- Documentation reflects the new app structure and feature boundaries
- Any deferred work is clearly called out

### Acceptance Tests

- Full project build
- New targeted tests:
  - `ShoppingListDomainTests`
  - `TripRecommendationTests`
  - `CompareFlowViewModelTests`
  - `ShoppingListViewModelTests`

## Build-Ready Execution Checklist

Use this as the working execution list during implementation.

### Milestone 1

- [ ] Create `ShoppingList`
- [ ] Create `ShoppingListItem`
- [ ] Create `StalenessBucket`
- [ ] Create `ItemKeyNormalizer`
- [ ] Create `PriceInsightEngine`
- [ ] Register new models in `PrixioApp`
- [ ] Replace repository-local normalization
- [ ] Add domain tests
- [ ] Build project

### Milestone 2

- [ ] Create `AppNavigationModel`
- [ ] Replace placeholder tab destinations in `MainView`
- [ ] Inject app navigation state from `PrixioApp`
- [ ] Add scan prefill request handling in `ScanViewModel`
- [ ] Consume pending request in `ScanRootView`
- [ ] Build project

### Milestone 3

- [ ] Create `StoreComparisonRow`
- [ ] Create `CompareViewModel`
- [ ] Add compare derivation logic
- [ ] Add compare view-model tests
- [ ] Build project

### Milestone 4

- [ ] Create Compare UI files
- [ ] Build Compare root screen
- [ ] Build item detail screen
- [ ] Add delete-only detail sheet action
- [ ] Manual QA Compare flow
- [ ] Build project

### Milestone 5

- [ ] Create shopping repository and row data types
- [ ] Create trip recommendation type
- [ ] Create shopping list view model
- [ ] Add repository and view-model tests
- [ ] Build project

### Milestone 6

- [ ] Create Shopping List UI files
- [ ] Build add-item flow
- [ ] Build completed section
- [ ] Build trip optimizer card
- [ ] Manual QA Shopping List flow
- [ ] Build project

### Milestone 7

- [ ] Create `ScanNudgeSheet`
- [ ] Add stale/missing-data nudge logic
- [ ] Wire row-best-store-first prefill
- [ ] Route into Scan tab
- [ ] Add targeted tests
- [ ] Manual QA scan loop
- [ ] Build project

### Milestone 8

- [ ] Run full build validation
- [ ] Run targeted tests
- [ ] Update `AGENTS.md`
- [ ] Update `Journal.md`
- [ ] Update `OutstandingWork.md` if needed

## Definition Of Done

The feature set is done when all of the following are true:

- Compare tab is fully usable for browse, search, and item-detail ranking
- Shopping List tab supports add, complete, collapse completed, and trip recommendation
- Staleness is explicit and visually communicated in both flows
- Checking off stale or missing-price items offers a scan nudge
- Scan launches with correct prefill from Shopping List
- The project builds successfully
- New domain and view-model tests are in place
- Project documentation reflects the implemented architecture
