# Physical Device QA Test Plan

## Purpose

This document is the manual QA checklist for testing Prixio on a real iPhone.

It is written for a human QA pass, not an automated suite. Every test case includes:

- setup
- steps
- expected result

## Test Environment

Run this on a physical iPhone, not just Simulator.

Recommended setup:

- latest debug build installed from Xcode
- at least one clean app install pass
- at least one upgrade-over-existing-build pass
- device with camera
- device with location services enabled
- device with photo library access available

Recommended device states to cover:

- camera permission not determined
- camera permission denied
- location permission not determined
- location permission granted
- location permission denied
- photo library permission not determined
- photo library add-only granted
- photo library denied

Recommended test data:

- at least 5 saved `PriceEntry` records across 2+ stores
- at least 1 item tracked at multiple stores
- at least 1 item with fresh data
- at least 1 item with stale data
- at least 1 item with no data in Shopping List

## Test Passes

Run the test plan in this order:

1. First-launch and permissions
2. Scan flow
3. Compare flow
4. Shopping List flow
5. Cross-flow behavior
6. Regression and resilience checks

## 1. First Launch And Permissions

### QA-001 App launches into main tab shell

Setup:

- fresh install

Steps:

1. Launch the app

Expected:

- app opens successfully
- tab bar shows `Scan`, `Compare`, `Shopping List`, `Settings`
- no blank screen
- no crash on launch

### QA-002 Camera permission prompt on first scan use

Setup:

- fresh install
- camera permission not determined

Steps:

1. Launch app
2. Stay on `Scan`

Expected:

- system camera permission prompt appears when scan camera is needed
- app remains responsive

### QA-003 Camera denied state shows fallback UI

Setup:

- deny camera permission in system prompt or Settings

Steps:

1. Open app
2. Go to `Scan`

Expected:

- camera unavailable UI appears
- import-photo fallback is visible
- app does not crash or loop on permission prompt

### QA-004 Location permission request does not block app usage

Setup:

- location permission not determined

Steps:

1. Launch app
2. Visit `Scan`
3. Visit `Compare`

Expected:

- location permission may be requested
- app remains usable if user declines
- Compare and Shopping List still render without distance values

### QA-005 Photo library add-only denial does not break review flow

Setup:

- deny photo-library add access

Steps:

1. Capture or import an image
2. Open confirmation sheet
3. Tap `Save Photo`

Expected:

- user receives failure/denied message
- confirmation sheet stays usable
- save flow still works

## 2. Scan Flow

### QA-010 Live camera preview loads on authorized device

Setup:

- camera permission granted

Steps:

1. Open `Scan`

Expected:

- live camera preview is visible
- scanner overlay is visible
- shutter button is enabled

### QA-011 Capture photo opens confirmation sheet

Setup:

- camera permission granted

Steps:

1. Aim at any shelf tag
2. Tap shutter

Expected:

- review image is shown
- confirmation sheet appears
- OCR processing indicator appears while parsing

### QA-012 Import from photo library opens confirmation sheet

Setup:

- photo library contains a grocery shelf-tag image

Steps:

1. Open `Scan`
2. Tap gallery/import button
3. Choose image

Expected:

- selected image is shown
- confirmation sheet appears
- OCR result populates draft fields when parsing completes

### QA-013 OCR populates editable draft fields

Setup:

- use a clear shelf-tag image

Steps:

1. Capture or import image
2. Wait for OCR

Expected:

- item name is populated when detectable
- price is populated when detectable
- unit is selected when detectable
- store fields may be inferred
- all populated values remain editable

### QA-014 Recent item suggestions are tappable

Setup:

- at least 2 previously saved entries

Steps:

1. Capture/import a new image
2. Open confirmation sheet
3. Tap a recent item suggestion

Expected:

- tapped suggestion replaces item name field

### QA-015 Price candidate chips apply chosen candidate

Setup:

- use an image that produces multiple candidate prices

Steps:

1. Capture/import image
2. Tap a displayed price candidate chip

Expected:

- price field updates to selected candidate
- quantity updates if candidate carries quantity

### QA-016 Store chain must be explicitly confirmed before save

Setup:

- confirmation sheet open

Steps:

1. Leave detected chain unconfirmed if possible
2. Try to save

Expected:

- save remains disabled until store chain is explicitly selected

### QA-017 Manual store chain selection works

Setup:

- confirmation sheet open

Steps:

1. Open store chain menu
2. Choose a chain

Expected:

- selected chain appears in draft
- save eligibility updates if other required fields are valid

### QA-018 Store location sheet can assign a nearby or searched store

Setup:

- confirmation sheet open

Steps:

1. Open store selection
2. Choose nearby store or search result

Expected:

- location name updates
- address updates if available
- store selection sheet dismisses

### QA-019 Retake clears transient scan state

Setup:

- confirmation sheet open after capture

Steps:

1. Tap `Retake`

Expected:

- confirmation sheet dismisses
- captured image clears
- preview returns to live camera
- prior draft values do not linger

### QA-020 Discard clears transient scan state

Setup:

- confirmation sheet open

Steps:

1. Tap `Discard`

Expected:

- review state clears
- no entry is saved
- scanner returns to ready state

### QA-021 Save creates a price entry and shows success toast

Setup:

- confirmation sheet with valid fields

Steps:

1. Tap `Save`

Expected:

- entry is persisted
- success toast appears
- confirmation sheet dismisses
- scanner resets cleanly

### QA-022 Last save banner updates after save

Setup:

- save any valid entry

Steps:

1. Return to `Scan` main surface after save

Expected:

- last-save banner reflects newest saved entry

### QA-023 Scan prefill from app navigation does not auto-open review UI

Setup:

- trigger scan launch from Shopping List flow

Steps:

1. Use `Scan now` from Shopping List

Expected:

- app switches to `Scan`
- item name is prefilled
- preferred chain is prefilled when available
- confirmation sheet is not shown automatically
- capture/import still requires user action

### QA-024 Save photo reference works when permission is granted

Setup:

- photo-library add access granted
- confirmation sheet open

Steps:

1. Tap `Save Photo`

Expected:

- app reports success
- image appears in Photos

## 3. Compare Flow

### QA-030 Compare empty state appears when no entries exist

Setup:

- clean install with no saved entries

Steps:

1. Open `Compare`

Expected:

- empty state appears
- CTA to scan is visible

### QA-031 Compare empty-state CTA routes to Scan tab

Setup:

- no entries exist

Steps:

1. Open `Compare`
2. Tap `Scan a price tag`

Expected:

- app switches to `Scan`

### QA-032 Compare root shows suggested cards when item is tracked at multiple stores

Setup:

- at least one item saved at 2+ stores

Steps:

1. Open `Compare`

Expected:

- `Suggested Comparisons` section appears
- matching item card is visible

### QA-033 Tapping suggested comparison card opens item detail

Setup:

- suggested cards visible

Steps:

1. Tap a suggested comparison card

Expected:

- item detail screen opens
- title matches item

### QA-034 Recent captures section shows latest entries

Setup:

- multiple saved entries

Steps:

1. Open `Compare`

Expected:

- `Recent Captures` section is visible
- rows show item, store, relative time, and price

### QA-035 Tapping recent capture opens item detail

Setup:

- recent captures visible

Steps:

1. Tap a recent capture row

Expected:

- item detail opens for that item

### QA-036 Browse section shows tracked items

Setup:

- multiple saved items

Steps:

1. Open `Compare`

Expected:

- `Browse` section is visible
- each row shows item name
- each row shows store count
- best known price appears when available

### QA-037 Search filters items live

Setup:

- multiple saved items

Steps:

1. Open `Compare`
2. Enter part of an item name in search

Expected:

- results update while typing
- only matching items appear

### QA-038 Search no-results state appears

Setup:

- saved items exist

Steps:

1. Search for nonexistent item

Expected:

- no-results state appears
- app remains responsive

### QA-039 Item detail defaults to useful display mode

Setup:

- choose an item with normalized unit pricing

Steps:

1. Open item detail

Expected:

- `Per unit` mode is shown when comparable rows exist
- rows appear without extra user action

### QA-040 Item detail falls back to per-package when per-unit has no comparable rows

Setup:

- choose item with package-only pricing

Steps:

1. Open item detail

Expected:

- item detail still shows rows
- user is not left on an empty per-unit screen

### QA-041 Unit toggle re-sorts rows immediately

Setup:

- item with both normalized and package display possibilities

Steps:

1. Open item detail
2. Toggle between `Per unit` and `Per package`

Expected:

- row list updates immediately
- price labels update immediately

### QA-042 Stale rows are visibly stale

Setup:

- item with entries older than 30 days

Steps:

1. Open item detail

Expected:

- stale rows are faded
- stale rows display explicit stale language

### QA-043 Very stale rows look more degraded than fresh rows

Setup:

- item with both fresh and very stale entries

Steps:

1. Open item detail

Expected:

- visual hierarchy clearly favors fresh rows
- very stale row uses "Old price" style

### QA-044 Distance appears only when location is available and coordinates exist

Setup:

- location permission granted
- item has entries with store coordinates

Steps:

1. Open item detail

Expected:

- distance appears on rows with coordinates
- rows without coordinates do not show fake placeholders

### QA-045 Trend badge appears when two comparable entries exist for a store

Setup:

- same item captured multiple times at same store

Steps:

1. Open item detail

Expected:

- trend badge shows up/down/flat when enough data exists

### QA-046 Mixed unit-family note appears when item has conflicting unit families

Setup:

- same item saved with mixed normalized families

Steps:

1. Open item detail

Expected:

- note appears explaining dominant family behavior

### QA-047 Entry detail sheet opens from store row tap

Setup:

- item detail open

Steps:

1. Tap a store row

Expected:

- entry detail sheet appears
- image preview appears when file exists
- timestamp is shown
- normalization breakdown appears when available

### QA-048 Delete entry from entry detail removes data

Setup:

- entry detail sheet open

Steps:

1. Tap `Delete`
2. Confirm delete

Expected:

- entry is removed
- item detail updates accordingly
- compare root updates accordingly
- app does not crash

## 4. Shopping List Flow

### QA-060 Shopping List empty state appears when list has no items

Setup:

- no shopping list items

Steps:

1. Open `Shopping List`

Expected:

- empty state appears
- `Add your first item` button visible
- `Scan items as you shop` button visible

### QA-061 Empty-state add CTA opens add-item sheet

Setup:

- no list items

Steps:

1. Tap `Add your first item`

Expected:

- add-item sheet opens

### QA-062 Empty-state scan CTA routes to Scan tab

Setup:

- no list items

Steps:

1. Tap `Scan items as you shop`

Expected:

- app switches to `Scan`

### QA-063 Add known tracked item through typeahead

Setup:

- saved entries exist for known items

Steps:

1. Open add-item sheet
2. Type partial item name
3. Tap suggested known item
4. Tap `Add`

Expected:

- item is added to checklist
- display name is correct

### QA-064 Add freeform item with no existing price data

Setup:

- open add-item sheet

Steps:

1. Type brand-new item name
2. Optionally enter quantity note
3. Tap `Add`

Expected:

- item appears in checklist
- no crash even with no matching `PriceEntry`

### QA-065 Trip optimizer card appears when items exist

Setup:

- at least one shopping-list item

Steps:

1. Open `Shopping List`

Expected:

- trip card appears at top of active checklist state

### QA-066 Trip optimizer shows insufficient-data state when data is sparse

Setup:

- list has items but fewer than 2 priced suggestions

Steps:

1. Open `Shopping List`

Expected:

- card says there is not enough data yet

### QA-067 Trip optimizer shows strong winner when one chain wins at least 60%

Setup:

- active items and saved entries produce strong winner

Steps:

1. Open `Shopping List`

Expected:

- strong winner message appears
- winner chain and count are correct

### QA-068 Trip optimizer shows split-trip state when threshold is not met

Setup:

- active items produce no single chain at 60%+

Steps:

1. Open `Shopping List`

Expected:

- split-trip language appears
- top two chain counts are shown

### QA-069 Checklist row shows best store and best price when known

Setup:

- shopping-list item has price data

Steps:

1. Open `Shopping List`

Expected:

- row shows best store name
- row shows best price

### QA-070 Checklist row shows fallback copy when no price exists

Setup:

- shopping-list item has no price data

Steps:

1. Open `Shopping List`

Expected:

- row shows "No known price yet" or equivalent fallback

### QA-071 Checklist row shows quantity note when set

Setup:

- item has quantity note

Steps:

1. Open `Shopping List`

Expected:

- quantity note is visible below item name

### QA-072 Checklist row staleness badge reflects fresh data

Setup:

- item suggestion is fresh

Steps:

1. Open `Shopping List`

Expected:

- short age badge appears
- row does not look stale

### QA-073 Checklist row visibly degrades for stale data

Setup:

- item suggestion is stale

Steps:

1. Open `Shopping List`

Expected:

- row appears faded relative to fresh rows
- staleness badge is warning-colored

### QA-074 Checklist row can be opened for detail

Setup:

- item exists in active list

Steps:

1. Tap row body, not checkbox

Expected:

- item detail sheet opens
- top store rows are shown when available

### QA-075 Item detail sheet supports delete

Setup:

- row detail sheet open

Steps:

1. Tap `Delete`

Expected:

- item is removed from list
- sheet dismisses

### QA-076 Item detail sheet supports direct scan loop-back

Setup:

- row detail sheet open

Steps:

1. Tap `Scan price now`

Expected:

- sheet dismisses
- app routes to `Scan`
- item name is prefilled

### QA-077 Checking an item moves it into completed section

Setup:

- active checklist has items

Steps:

1. Tap item checkbox

Expected:

- item disappears from active section
- item appears in completed section

### QA-078 Completed section is collapsed by default

Setup:

- at least one completed item

Steps:

1. Open `Shopping List`

Expected:

- completed group is collapsed initially

### QA-079 Completed section can expand and collapse

Setup:

- completed items exist

Steps:

1. Tap completed disclosure
2. Tap again

Expected:

- list expands and collapses correctly

### QA-080 Unchecking a completed item moves it back to active section

Setup:

- completed item visible

Steps:

1. Expand completed section
2. Tap checkbox

Expected:

- item returns to active checklist

### QA-081 Deleting an active row from swipe action removes it

Setup:

- active row visible

Steps:

1. Swipe row
2. Tap `Delete`

Expected:

- row is removed
- trip card recomputes

### QA-082 All-complete state appears when every item is done

Setup:

- mark all items complete

Steps:

1. Open `Shopping List`

Expected:

- celebratory all-done state appears

## 5. Freshness Loop And Cross-Flow Behavior

### QA-090 Fresh item checks off without scan nudge

Setup:

- shopping-list row with fresh suggestion

Steps:

1. Tap checkbox

Expected:

- row completes
- no scan nudge sheet appears

### QA-091 Stale item checkoff shows scan nudge

Setup:

- row with stale suggestion

Steps:

1. Tap checkbox

Expected:

- row is marked completed
- scan nudge sheet appears

### QA-092 Missing-price item checkoff shows scan nudge

Setup:

- row with no suggestion

Steps:

1. Tap checkbox

Expected:

- row is marked completed
- scan nudge sheet appears

### QA-093 Nudge dismiss leaves item completed

Setup:

- scan nudge visible

Steps:

1. Tap `Not now`

Expected:

- nudge dismisses
- item stays completed

### QA-094 Nudge scan-now routes to Scan with item prefilled

Setup:

- scan nudge visible

Steps:

1. Tap `Scan now`

Expected:

- app switches to `Scan`
- draft item name is prefilled

### QA-095 Row best-store prefill is used before trip winner fallback

Setup:

- row has best-store suggestion
- trip winner may differ

Steps:

1. Trigger `Scan now` for that row

Expected:

- scan draft uses row best-store chain first

### QA-096 Trip winner fallback used when row best-store is unavailable

Setup:

- row has no specific best-store name
- trip recommendation exists

Steps:

1. Trigger `Scan now`

Expected:

- scan draft uses trip winner chain

### QA-097 Compare reflects new scan after saving refreshed price

Setup:

- launch scan from Shopping List or save from normal Scan

Steps:

1. Save a new price for an item already used in Compare
2. Open `Compare`

Expected:

- recent captures update
- item detail reflects newest data

### QA-098 Shopping List recomputes after refreshed scan is saved

Setup:

- item exists in Shopping List

Steps:

1. Save new scan for that item
2. Return to `Shopping List`

Expected:

- row best-price data updates
- trip card recomputes if relevant

## 6. Regression And Resilience Checks

### QA-110 App survives repeated tab switching

Setup:

- normal dataset loaded

Steps:

1. Switch repeatedly across all tabs
2. Open and dismiss multiple sheets

Expected:

- no crash
- no obviously stale screen state

### QA-111 App survives repeated compare-detail navigation

Setup:

- several compare items available

Steps:

1. Open item detail
2. Go back
3. Open another detail
4. Repeat

Expected:

- navigation remains stable
- no duplicate toolbar or blank screens

### QA-112 App survives repeated shopping-detail and nudge presentation

Setup:

- shopping items present

Steps:

1. Open row detail
2. Dismiss
3. Check item to trigger nudge
4. Dismiss or route to Scan
5. Repeat

Expected:

- sheets do not get stuck
- no overlapping presentation bugs

### QA-113 Search cancellation in Compare restores default sections

Setup:

- compare data exists

Steps:

1. Search for an item
2. Clear search text or cancel search

Expected:

- root screen returns to suggestions + recent + browse sections

### QA-114 App survives deleting the last entry for an item

Setup:

- item with single remaining entry

Steps:

1. Open Compare item detail
2. Delete only row

Expected:

- app handles empty result gracefully
- compare root updates without crash

### QA-115 App survives deleting the last shopping-list item

Setup:

- only one list item exists

Steps:

1. Delete item

Expected:

- Shopping List returns to empty state
- no stale row remains on screen

### QA-116 App survives denied permissions after prior grant

Setup:

- first grant, then revoke camera or location in Settings

Steps:

1. Relaunch app
2. Use affected flow

Expected:

- app falls back gracefully
- no stuck loading state

## Exit Criteria

The physical-device pass is successful when:

- all critical flow tests pass:
  - Scan capture/import/save
  - Compare browse/search/detail/delete
  - Shopping add/complete/detail/nudge
  - cross-tab scan routing
- no crashes occur during normal use
- no data-corruption issue is observed
- no sheet/navigation deadlock is observed
- stale-state communication is clear in Compare and Shopping List

## Notes For QA

When filing a bug, include:

- device model
- iOS version
- build/config used
- exact test case ID from this plan
- whether permissions were granted or denied
- whether issue happened after capture, import, compare navigation, or shopping-list routing
- screenshot or screen recording if possible
