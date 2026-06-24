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
- at least 1 month of spending data (use `Settings → Spending Test Data → Add spending test data` in DEBUG builds for expenses, income, and grocery receipts)
- at least 1 receipt in a non-reporting currency (to exercise the currency-mismatch path)
- at least 1 imported PDF receipt

## Test Passes

Run the test plan in this order:

1. First-launch and permissions
2. Scan flow
3. Compare flow
4. Shopping List flow
5. Cross-flow behavior
6. Regression and resilience checks
7. Scanner and shopping defect fixes
8. Camera launch performance
9. Receipt import and review
10. Spending flow
11. Settings
12. Price intelligence (scan-time insights)

## 1. First Launch And Permissions

### QA-001 App launches into main tab shell

Setup:

- fresh install

Steps:

1. Launch the app

Expected:

- app opens successfully
- tab bar shows `Scan`, `Compare`, `Shopping List`, `Spending`, `Settings`
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

### QA-025 Scanner torch toggles the live preview on physical hardware

Setup:

- physical iPhone with a torch
- camera permission granted
- dim shelf-tag or printed-label target

Steps:

1. Open `Scan`
2. Tap the flash button once
3. Tap the flash button again

Expected:

- first tap visibly illuminates the live camera preview
- flash icon changes only when the torch is actually enabled
- second tap turns the torch off and the preview returns to ambient light

### QA-026 Scanner torch is unavailable-safe

Setup:

- Simulator, or hardware/run destination where torch is unavailable

Steps:

1. Open `Scan`
2. Inspect the flash button

Expected:

- flash button is disabled and dimmed
- tapping the button does not claim the torch is on
- app remains responsive

### QA-027 Scanner torch turns off on every preview exit path

Setup:

- physical iPhone with torch
- camera permission granted
- flash button currently on

Steps:

1. Capture a photo and wait for the confirmation sheet
2. Repeat with flash on, then tap `Retake`
3. Repeat with flash on, then tap `Discard`
4. Repeat with flash on, then tap `Save`
5. Repeat with flash on, then dismiss the confirmation sheet
6. Turn flash on, tap the gallery button, and pick a photo
7. Turn flash on, then switch away from the `Scan` tab

Expected:

- torch turns off for every listed path
- returning to `Scan` shows the flash button in the off state
- captured shelf-tag image is not blown out by glare; if glare is unacceptable, revisit still-photo flash behavior

### Torch validation results (2026-06-14)

Build: `BuildProject` succeeds with 0 errors; the target links cleanly. The current build was installed and launched on a physical iPhone ("iPhone (2)", iOS 27.0) and is ready for the manual torch pass.

| Case | Result | Notes |
|------|--------|-------|
| QA-025 (torch illuminates live preview) | ✅ PASS (physical device) | Manual pass on iPhone (iOS 27.0): tapping flash visibly illuminates the live preview; tapping again returns to ambient light. Icon tracks real torch state. |
| QA-026 (torch unavailable-safe) | ✅ PASS (automated, Simulator) | iPhone 17 Pro Max (27.0). "Flash toggle" reports `enabled = false` (Disabled) and is visibly dimmed (0.4 opacity). Tapping it does not flip the icon to `bolt.fill`; app stays responsive, no crash. |
| QA-027 (torch off on every exit path) | ✅ PASS (physical device) | Manual pass on iPhone: torch turns off on capture, retake, discard, save, sheet dismiss, gallery pick, and tab switch; flash button returns to off state each time. Captured shelf-tag image acceptable — no blown-out glare, so the Step 5 still-flash decision (keep flash tied to `isFlashEnabled`) stands. |

All three torch cases pass. QA-025/QA-027 were validated manually on the physical device (the device-interaction harness only drives Simulators, which have no torch).

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
- app stays on `Shopping List`
- scanner UI is not shown

### QA-062 Empty-state scan CTA routes to Scan tab without stale sheet state

Setup:

- no list items

Steps:

1. Tap `Scan items as you shop`
2. Return to `Shopping List`

Expected:

- app switches to `Scan`
- add-item sheet does not open before navigation
- returning to `Shopping List` does not present the add-item sheet

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

## 7. Scanner And Shopping Defect Fixes (2026-06-23)

Manual validation for the defects tracked in `ScannerShoppingDefectPlan.md`. Run after the
flows above. B1/B3/B4/B5/B6/B8 are code-complete and unit-tested; B2 was code-complete before
this pass. These cases confirm the on-device behavior the unit tests can't.

> **Update (2026-06-24):** the store-indicator cache gap behind QA-121 is fixed in code.
> `ScanSessionStore` now records the fetch location and `cachedCandidatesIfFresh(near:)` invalidates
> the cache once the user moves more than 250 m from it (in addition to the 300 s lifetime), so the
> indicator tracks movement between nearby stores. QA-121 should now pass on device; verify it.

### QA-120 Add-item screen auto-focuses the item field (B1)

Setup:

- `Shopping List` tab open

Steps:

1. Open the add-item sheet (`Add your first item`, the `+`, or the empty-state CTA)

Expected:

- the keyboard appears automatically without a tap
- the cursor is in the item name field (first field), ready to type
- the item name field is the first/top control in the form

### QA-121 Scanner store indicator updates as the user moves (B2)

Setup:

- physical iPhone, location permission granted
- start at or near one known store, with a different store reachable

Steps:

1. Open `Scan`
2. Note the store indicator's chain/location
3. Travel toward a different store (or change location) and wait for the indicator to refresh

Expected:

- the indicator reflects the user's actual current location, not a stuck/hardcoded chain
- moving to a new store updates the detected nearby store
- the indicator is not limited to a single hardcoded chain

> Note (2026-06-24): nearby candidates are cached, but the cache is invalidated once the user moves
> more than 250 m from where it was taken (not just on the 300 s timer), so the indicator should
> refresh after a move of roughly a block or more. A small move within 250 m may still show the prior
> nearest store — that is expected.

### QA-122 Review screen "change store" button opens the store picker (B2)

Setup:

- confirmation/review sheet open after a capture or import

Steps:

1. Tap the Store Location button on the review sheet
2. Pick a different nearby/searched store

Expected:

- the store selection sheet opens
- choosing a store updates the draft's location (and chain when the candidate carries one)
- the store selection sheet dismisses and the review sheet shows the new store

### QA-123 Custom chain can be entered in the store selection sheet (B3)

Setup:

- store selection sheet open (from the review sheet's Store Location button)

Steps:

1. Scroll to the `Custom Chain` section
2. Type a chain name that is not in the built-in list (e.g. "Save-On-Foods")
3. Tap `Use`

Expected:

- the typed chain becomes the draft's selected chain
- a checkmark indicates the custom chain is selected
- the chain no longer falls through to "Unknown"

### QA-124 Custom chain can be entered from the review chain menu (B3)

Setup:

- confirmation/review sheet open

Steps:

1. Open the Store Chain menu
2. Tap `Custom…`
3. Enter a non-listed chain name in the alert and tap `Set`
4. Save the entry, then reopen it (Compare → item → entry)

Expected:

- the menu label updates to the custom chain and the store is treated as explicitly selected
- after save, the entry's store shows the custom chain (not "Unknown")

### QA-125 Brand is captured, shown, and persisted on a scanned price (B6)

Setup:

- confirmation/review sheet open after capturing a branded shelf tag

Steps:

1. Confirm or type a value in the new `Brand` field
2. Complete the required fields and tap `Save`
3. Open the entry from Compare → item detail → store row

Expected:

- the `Brand` field is present and editable on the review sheet
- the saved entry detail shows a `Brand` row with the entered value
- leaving Brand blank saves with no brand and shows no brand row

### QA-126 Brand can be added to a shopping-list item (B6)

Setup:

- add-item sheet open

Steps:

1. Enter an item name and a value in the `Brand` field
2. Tap `Add`

Expected:

- the item is added with the brand shown under the item name in the checklist row
- adding an item with a blank brand shows no brand line

### QA-127 Saved Compare entry can be edited (B8)

Setup:

- Compare → item detail → tap a store row to open the entry detail sheet

Steps:

1. Tap `Edit`
2. Change item name, brand, price, unit, store chain (try `Custom…`), and store location
3. Tap `Save`

Expected:

- the sheet switches to an editable form, then back to the detail view on Save
- the detail view reflects every changed value
- `Cancel` discards in-progress edits without changing the entry

### QA-128 Edits recompute derived data across Compare/Shopping (B8)

Setup:

- an item tracked at multiple stores; edit one entry's price/unit/chain (QA-127)

Steps:

1. Save the edit
2. Re-open the same item detail and review the store rows
3. Open `Shopping List` if the item is listed

Expected:

- comparison rows re-sort and re-price to match the edited values
- changing the chain regroups the row under the new store
- Shopping List best-price/best-store data reflects the edit
- no crash; renaming one entry's store location does not rewrite other entries at the same place

### QA-129 Generic shopping item rolls up specific scanned products (B4)

Setup:

- save at least one specific branded price entry (e.g. "Daisy Sour Cream", or "Almond Milk")
- add a generic item to the Shopping List whose words are a subset of that product
  (e.g. "sour cream", or "milk")

Steps:

1. Open `Shopping List` and find the generic row
2. Open the row detail / best-store data
3. Optionally open `Compare`, search the generic name, and open item detail

Expected:

- the generic row surfaces best store/price drawn from the specific scanned product
- Compare item detail for the generic name includes the specific product's captures
- a more-specific query does NOT match a broader entry (e.g. "Daisy Sour Cream" does not pull in a
  plain "sour cream" entry), and the generic word as a mere modifier does not match
  (e.g. "milk" does not roll up "milk chocolate")

### QA-130 Quick capture mode queues shots without inline review (B5)

Setup:

- camera permission granted
- scanner mode picker set to `Quick`

Steps:

1. Open `Scan`, select `Quick`
2. Capture several shelf tags in quick succession without waiting between shots

Expected:

- the camera stays live after each shot; no confirmation sheet opens inline
- a "N captures to review" queue chip appears and increments as you shoot
- the chip shows a spinner while captures are still extracting, then a chevron when done
- switching scan modes and back does not lose the queued captures

### QA-131 Batch review confirms and discards queued captures (B5)

Setup:

- one or more pending captures in the Quick-mode queue (QA-130)

Steps:

1. Tap the queue chip to open the batch review list
2. Tap a capture to open its confirmation editor; complete fields and `Save`
3. Return to the list, swipe another capture to discard
4. Open a capture and use the store picker (including a `Custom…` chain)

Expected:

- each row shows a thumbnail, parsed item/price/store, and a ready / needs-details / processing status
- tapping a row opens the standard confirmation sheet bound to that queued draft
- `Save` persists the price and removes it from the queue; swipe-discard drops it
- the store picker (custom chain included) works the same as the inline flow
- emptying the queue shows the "All Caught Up" state

### Defect-fix validation results (2026-06-23)

Build: `BuildProject` succeeds with 0 errors. Unit coverage passing: `ItemKeyNormalizerTests`
(B4 matching + B7 stemming), `ItemPriceHistoryTests` (B4 generic rollup),
`PriceEntryRepositoryTests` (brand persistence + entry update). The cases below need a manual
device/Simulator pass.

| Case | Defect | Result | Notes |
|------|--------|--------|-------|
| QA-120 | B1 | ⬜ Pending | Auto-focus the add-item field. |
| QA-121 | B2 | ⬜ Pending | Store indicator tracks movement. Cache now invalidates on a >250 m move (fixed 2026-06-24); confirm on device. |
| QA-122 | B2 | ⬜ Pending | Review change-store button opens the picker and applies the choice. |
| QA-123 | B3 | ⬜ Pending | Custom chain via store selection sheet. |
| QA-124 | B3 | ⬜ Pending | Custom chain via review menu; persists (not "Unknown"). |
| QA-125 | B6 | ⬜ Pending | Brand captured on scan, shown in entry detail, persists. |
| QA-126 | B6 | ⬜ Pending | Brand on shopping-list item shows in the row. |
| QA-127 | B8 | ⬜ Pending | Edit saved entry; fields persist; Cancel discards. |
| QA-128 | B8 | ⬜ Pending | Edits recompute comparison/shopping derived data. |
| QA-129 | B4 | ⬜ Pending | Generic shopping item rolls up specific scanned products; head-noun/modifier guards hold. |
| QA-130 | B5 | ⬜ Pending | Quick mode queues shots without inline review; queue survives mode switches. |
| QA-131 | B5 | ⬜ Pending | Batch review confirms/discards queued captures; custom chain works. |

## 8. Camera Launch Performance (device)

Migrated from the removed `CameraPerformanceImplementationPlan.md` planning doc. These validate the shipped
deferred-start / responsive-capture path and the launch behavior it targets. The signpost-based
timing comparisons depend on the not-yet-added instrumentation tracked in `OutstandingWork.md`
item 7 — run those once signposts land.

### QA-140 Cold launch reaches a visible preview quickly

Setup:

- physical iPhone, camera permission granted
- app fully quit (cold launch)

Steps:

1. Launch the app and open `Scan`

Expected:

- the live preview appears promptly with no long black/blank frame
- the scanner overlay and shutter are visible
- the store chip may show its fallback state briefly while nearby stores load

### QA-141 Immediate shutter tap after preview still captures

Setup:

- camera permission granted

Steps:

1. Open `Scan`
2. Tap the shutter as soon as the preview appears, before waiting

Expected:

- the early tap still produces a captured image (responsive capture preserves it)
- the confirmation sheet opens with the captured image
- no missed/dropped capture

### QA-142 Nearby-store loading does not delay first preview

Setup:

- location permission granted, several stores nearby

Steps:

1. Cold launch into `Scan`

Expected:

- preview appears without waiting on store detection
- the store chip populates shortly after, independent of preview readiness

> Depends on the Phase 2 startup reordering (OutstandingWork.md item 7); until that lands, note any
> observed preview delay attributable to store/location work rather than filing a new defect.

### QA-143 Repeated scan/capture cycles stay stable under thermal load

Setup:

- physical iPhone

Steps:

1. Run many capture → confirm → retake/save cycles in a row
2. Optionally with the torch on to add thermal load

Expected:

- no crash, no stuck/frozen preview, no camera that fails to restart
- the app stays responsive as the device warms

### QA-144 Background/foreground while scan is visible recovers

Setup:

- `Scan` tab visible

Steps:

1. Background the app, then foreground it
2. Repeat a few times

Expected:

- the preview resumes
- capture still works after returning
- no stuck loading or black preview

## 9. Receipt Import And Review

The third scan mode (`Receipt`) captures a basket-level receipt instead of a single shelf tag, and routes
to the dedicated `ReceiptReviewView` rather than the single-tag confirmation sheet. Reviewed receipts feed
the Spending tab; promoted line items feed price history. Run after the Scan and Spending passes.

### QA-150 Receipt mode is selectable and prompts for a receipt

Setup:

- camera permission granted

Steps:

1. Open `Scan`
2. Select `Receipt` in the capture-mode picker

Expected:

- the capture prompt updates to receipt-oriented guidance
- an `Import PDF from Files` button appears below the prompt
- the live preview and shutter remain available

### QA-151 Long-press shutter shortcut switches to Receipt mode

Setup:

- `Scan` open in a non-receipt mode

Steps:

1. Long-press the shutter button (~0.5s) without a normal tap

Expected:

- the mode switches to `Receipt`
- no capture is taken from the long press itself
- a normal tap afterward captures a receipt

### QA-152 Capturing a receipt opens the receipt review surface

Setup:

- `Receipt` mode, camera permission granted

Steps:

1. Aim at a printed receipt
2. Tap the shutter

Expected:

- the `Review Receipt` screen opens (not the single-tag confirmation sheet)
- the captured image appears at the top
- an extraction/processing indicator runs while parsing

### QA-153 Importing a receipt photo opens review

Setup:

- photo library contains a receipt image

Steps:

1. In `Receipt` mode, tap the gallery/last-photo button
2. Choose the receipt image

Expected:

- the `Review Receipt` screen opens with the chosen image
- extracted header/line data populates when parsing completes

### QA-154 Importing a PDF receipt opens review

Setup:

- a PDF receipt is available in Files

Steps:

1. In `Receipt` mode, tap `Import PDF from Files`
2. Choose a PDF

Expected:

- the PDF renders into a reviewable receipt
- review opens with extracted data
- an unreadable/cancelled file surfaces a failure message rather than crashing

### QA-155 Receipt header fields are editable

Setup:

- receipt review open

Steps:

1. Edit store, category, currency, and date
2. Edit `Total`, `Subtotal`, `Tax`, `Discount`, and `Deposit`

Expected:

- every header field accepts edits
- amounts ≥ 1000 round-trip without being wiped
- negative amounts are rejected/normalized
- editing amounts re-runs the totals reconciliation live

### QA-156 Currency mismatch warning appears and blocks spending inclusion

Setup:

- a receipt whose currency is not the reporting currency

Steps:

1. Open review
2. Inspect the `Currency` row and helper text

Expected:

- a note warns the receipt won't be added to spending totals while its currency differs
- changing the currency to the reporting currency clears the warning

### QA-157 Review issues surface extraction problems

Setup:

- a receipt that triggers issues (e.g. totals don't reconcile, missing total, blur, handwriting, or a non-receipt image)

Steps:

1. Open review

Expected:

- a `Needs a look` section lists the relevant issues in plain language
- fixing the underlying values (e.g. correcting line/total amounts) clears the totals issue

### QA-158 Line item edits and promotion work

Setup:

- a receipt with several extracted line items

Steps:

1. Correct a line's item name and price
2. Tap `Promote` on a trustworthy line
3. Attempt to promote a line with a blank name or zero price

Expected:

- the `Promote` button is disabled until the line has a name and price > 0
- a promoted line shows a `Saved` checkmark
- the promotable count in the section header decrements as lines are promoted
- promoted lines later appear in Compare price history

### QA-159 Save Draft keeps the receipt unreviewed

Setup:

- receipt review open with edits

Steps:

1. Tap `Save Draft`

Expected:

- edits persist
- the receipt remains in `Needs review` state in the Spending tab
- the receipt does not yet count toward spending

### QA-160 Done marks the receipt reviewed only when the total is valid

Setup:

- receipt review open

Steps:

1. Clear the `Total` (or leave totals unreconciled) and tap `Done`
2. Enter a valid total / reconcile and tap `Done`

Expected:

- the first attempt is blocked with a `Check the Total` prompt
- the second attempt closes review and marks the receipt `Reviewed`
- the receipt now counts toward spending

### QA-161 Discard deletes the receipt and its line items

Setup:

- receipt review open

Steps:

1. Tap `Discard Receipt`

Expected:

- the receipt and its line items are deleted
- review dismisses
- nothing is added to spending

### QA-162 Swipe-dismiss preserves in-flight edits as a draft

Setup:

- receipt review open with unsaved edits

Steps:

1. Swipe the sheet down to dismiss without tapping Save Draft / Done / Discard

Expected:

- the edits are auto-saved as a draft
- a persistence failure surfaces a `Couldn't Save` alert directing the user back to the Spending tab
- using Save Draft / Done / Discard does not double-save on dismiss

## 10. Spending Flow

The `Spending` tab summarizes the current month from manual expenses, income, and reviewed receipts, and
surfaces recurring-pattern suggestions and anomalies. Seed data via `Settings → Spending Test Data` in
DEBUG builds.

### QA-170 Spending tab opens with a monthly summary

Setup:

- some spending data exists (seeded or manual)

Steps:

1. Open `Spending`

Expected:

- the summary section is titled with the current month
- rows show Income, Groceries, Bills, Subscriptions, and a Net total
- Net is red when negative

### QA-171 Empty state appears with no expenses

Setup:

- no expenses, income, or receipts for the month

Steps:

1. Open `Spending`

Expected:

- a `No expenses yet` empty state appears with guidance to add an expense or income
- the app does not crash with an empty dataset

### QA-172 Budget pressure indicator reflects income ratio

Setup:

- income and expenses producing a known ratio

Steps:

1. Open `Spending`

Expected:

- the pressure row shows Comfortable / Tight / Over (or a no-income-data state) with the correct tint
- the `% of income` value matches the data

### QA-173 Add expense

Setup:

- `Spending` open

Steps:

1. Tap the `+` toolbar menu and choose `Add Expense`
2. Enter an amount, pick a category, optionally a merchant/note/date
3. Tap `Save`

Expected:

- `Save` is disabled until amount > 0
- the expense appears in the `Expenses` list and the summary recomputes
- a persistence failure surfaces a `Couldn't Save` alert

### QA-174 Add income

Setup:

- `Spending` open

Steps:

1. Tap the `+` toolbar menu and choose `Add Income`
2. Enter an amount and optional label/date
3. Tap `Save`

Expected:

- `Save` is disabled until amount > 0
- the entry appears in the `Income` section and the summary recomputes

### QA-175 Delete expense, income, and receipt via swipe

Setup:

- at least one expense, income entry, and receipt for the month

Steps:

1. Swipe each row and tap `Delete`

Expected:

- each row is removed and the summary recomputes
- a delete failure rolls back (the row does not vanish while still persisted) and surfaces an alert

### QA-176 Spend-over-time chart appears when data exists

Setup:

- spending and/or income across multiple months

Steps:

1. Open `Spending`

Expected:

- a `Spend over time` chart renders with monthly bars
- the chart is hidden when there is no spend/income history

### QA-177 Anomalies section flags unusual categories

Setup:

- a category whose current month is well above its baseline

Steps:

1. Open `Spending`

Expected:

- an `Unusual this month` section lists the spiking category with a `+N% vs usual` delta

### QA-178 Store-share breakdown appears

Setup:

- reviewed receipts/expenses across multiple stores

Steps:

1. Open `Spending`

Expected:

- a `Where spending goes` section shows each store's total, percentage, and a proportional bar

### QA-179 Recurring suggestion can be confirmed or dismissed

Setup:

- repeated similar expenses that trigger a recurring suggestion (seeded data includes these)

Steps:

1. Open `Spending` and find the `Recurring patterns` section
2. Confirm one suggestion and dismiss another

Expected:

- a confirmed suggestion moves to a `Confirmed recurring` section showing cadence and expected amount
- a dismissed suggestion is removed and does not reappear
- a failure surfaces a `Couldn't Save` alert

### QA-180 Confirmed recurring rule can be removed

Setup:

- at least one confirmed recurring rule

Steps:

1. Swipe the rule and tap `Remove`

Expected:

- the rule is removed from `Confirmed recurring`
- matching expenses are no longer tagged to it

### QA-181 Tapping a receipt row opens review

Setup:

- the month has at least one receipt

Steps:

1. Tap a row in the `Receipts` section

Expected:

- the `Review Receipt` surface opens for that receipt
- the row shows store, category, date, total, and a `Reviewed` / `Needs review` badge
- closing review recomputes the summary

### QA-182 Month rolls over on foreground

Setup:

- app left running/backgrounded across a month boundary (or device clock advanced)

Steps:

1. Foreground the app on the `Spending` tab

Expected:

- the summary retitles to the new month and filters to its data
- the previous month no longer headlines

## 11. Settings

### QA-190 Settings shows on-device intelligence status

Setup:

- iOS 27+ device

Steps:

1. Open `Settings`

Expected:

- the `On-Device Intelligence` section shows a quota status (Within / Nearing / Usage limit exceeded)
- a `Resets` relative time appears when the provider reports one
- on pre-iOS 27 a "requires iOS 27 or later" note is shown instead

### QA-191 Limit-increase options can be shown when offered

Setup:

- a device state where a limit-increase suggestion is available

Steps:

1. Open `Settings`
2. Tap `Show options`

Expected:

- the system limit-increase flow is presented
- the app remains responsive

### QA-192 Debug test-data seeders work and stay isolated (DEBUG only)

Setup:

- a DEBUG build

Steps:

1. Use `Add 100 test records` / `Reset to 100 test records`, then `Delete test records`
2. Use `Add spending test data`, then `Delete spending test data`

Expected:

- seeded counts update correctly and the delete buttons disable at zero
- delete removes only tool-created records, leaving real data intact
- a failure surfaces a `Test data update failed` alert
- (sanity) these sections are absent from release builds

## 12. Price Intelligence (Scan-Time Insights)

`PriceInsightEngine` surfaces a "usual price" read and a store-relative read inside the scan confirmation
sheet as the draft is edited. Run with several saved entries for the same item.

### QA-200 Usual-price memory appears in the confirmation sheet

Setup:

- multiple saved entries for an item across time

Steps:

1. Scan/import that item and let OCR populate the draft
2. Adjust price/unit if needed

Expected:

- a price-memory read appears once item name, a price > 0, and a unit are present
- it stays silent while OCR is still processing or required fields are incomplete
- the read updates as the draft's price/unit/name change

### QA-201 Store-relative memory appears when a store is chosen

Setup:

- the same item saved at multiple stores

Steps:

1. In the confirmation sheet, ensure item, unit, and a store chain are set

Expected:

- a store-memory read indicates whether the chosen store is usually cheaper, average, or pricier
- it stays silent until item, unit, and a store chain are all present

## Exit Criteria

The physical-device pass is successful when:

- all critical flow tests pass:
  - Scan capture/import/save
  - Compare browse/search/detail/delete
  - Shopping add/complete/detail/nudge
  - Receipt capture/import/review/promote and reviewed-receipt → spending inclusion
  - Spending add/delete/recurring/summary
  - Settings intelligence status
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
