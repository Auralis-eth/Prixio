# Scanner And Shopping Defect Log

A living log for scanner and shopping-flow defects.

- Add a new defect by copying the **Defect Template** below into **Active Defects**.
- Move a defect into **Closed Defects** once its acceptance criteria are met and verified, recording how it was verified.

The common engineering lesson from the closed defects: **don't let view-local optimistic state pretend to be system state.** Hardware state belongs to the controller that owns the device; one intentional user action belongs to one control.

---

## Defect Template (copy for new defects)

### Defect N: <short title>

**Status:** 🔴 Open · 🟡 In progress / code-complete · ✅ Resolved
**Reported:** YYYY-MM-DD · **Closed:** YYYY-MM-DD

#### Current Behavior
What the user sees and why it is wrong.

#### Relevant Code (verified)
| Element | Location | Current behavior |
|---------|----------|------------------|

#### Root Cause
The confirmed mechanism (note any unconfirmed hypotheses).

#### Proposed Solution
Steps with file/line anchors.

#### Acceptance Criteria
- …

#### Verification
How it was tested (Simulator / device / unit / XCUI) and the result.

---

## Active Defects

_None. All tracked defects are resolved — see Closed Defects below._

---

## Closed Defects

### Defect 1: Scanner Flash Button Does Not Work

**Status:** ✅ Resolved · **Reported:** 2026-06-14 · **Closed:** 2026-06-14

Build passes (`BuildProject`, 0 errors). QA-026 (torch-unavailable-safe) passed automated on the Simulator; QA-025 (illumination) and QA-027 (off on every exit path + glare) passed manually on a physical iPhone (iOS 27.0).

| Item | Status | Notes |
|------|--------|-------|
| Torch ownership (`CameraController` Steps 1–2) | ✅ Implemented | `captureDevice` retained; `isTorchAvailable`/`isTorchEnabled` published; `setTorch(_:)` locks the device on `sessionQueue`. |
| Button wiring (`ScanRootView` Step 3) | ✅ Implemented | Icon binds to `cameraController.isTorchEnabled`; button disabled + dimmed when `!isTorchAvailable`. |
| Torch-off exit paths (Step 4) | ✅ Implemented | `ScanRootView.extinguishTorch()` resets `isFlashEnabled` and calls `setTorch(false)` for capture, gallery, confirmation dismiss, retake, discard, save, and tab/view disappearance. |
| Still-flash decision (Step 5) | ✅ Decided | Still-capture flash kept tied to `isFlashEnabled`; on-device capture showed no blown-out glare, so the decision stands. |
| QA-026 torch-unavailable-safe | ✅ PASS (Simulator) | "Flash toggle" reports `enabled = false`, dimmed (0.4 opacity); tap is a no-op; app responsive. |
| QA-025 / QA-027 physical validation | ✅ PASS (device) | Torch illuminates/extinguishes correctly; off on every exit path; capture not blown out. Recorded in `PhysicalDeviceQATestPlan.md`. |

#### Current Behavior

On the Scanner tab, tapping the flash button changes the icon between `bolt.fill` and `bolt.slash`, but the live camera view does not brighten — the original implementation controlled **still-photo flash** (`AVCapturePhotoSettings.flashMode`), which only fires during the capture event, not the **live torch**.

#### Root Cause (confirmed)

1. **No device reference.** The `AVCaptureDevice` was created inside `configureSession` and discarded — no handle to lock and set `torchMode`.
2. **No capability state exposed to the UI.** `CameraController` published only `authorizationStatus` and `isCaptureReady`, so the button could not reflect real hardware state or disable itself on unsupported devices.

#### Solution (implemented)

Scanner lighting moved into `CameraController`, which owns the physical device; `ScanRootView` drives the torch through the controller while `ScanViewModel.isFlashEnabled` remains only the still-capture preference.

- **Step 1 — Retain device + expose state** (`CameraController.swift:24-39, 156-166`): `isTorchAvailable`/`isTorchEnabled` published; `captureDevice` retained in `configureSession`; availability published from `device.hasTorch && device.isTorchAvailable`.
- **Step 2 — Torch control method** (`CameraController.swift:87-113`): `setTorch(_:)` locks the device on `sessionQueue`, sets `torchMode`, publishes resulting state on the main actor; no-op (stays off) when the device has no usable torch. Uses `.on` rather than `setTorchModeOn(level:)` to avoid glare on close tags.
- **Step 3 — Button drives the torch** (`ScanRootView.swift:243-252, 395-398`): `toggleTorch()` flips the view-model preference and calls `setTorch`; icon binds to `cameraController.isTorchEnabled`; button `.disabled(!isTorchAvailable)` and dimmed to 0.4 opacity.
- **Step 4 — Off on every exit** (`ScanRootView.swift:400-403` plus call sites at `:48, 87, 102, 109, 117, 271, 330, 367`): `extinguishTorch()` covers capture, gallery open/pick, confirmation dismiss, retake, discard, save, and `.onDisappear`.
- **Step 5 — Still-capture flash** kept tied to `isFlashEnabled` (no call-site change); revisit only if device testing shows glare.

#### Acceptance Criteria

- Tapping the flash button visibly toggles the device torch while the live preview is active.
- The button icon binds to `cameraController.isTorchEnabled` (real torch state), not optimistic view-model state.
- On devices without a torch, the button is disabled and visibly dimmed.
- The torch is off after: capturing, retaking, discarding, saving, dismissing the confirmation sheet, and switching away from the Scanner tab.
- The captured still image is acceptable with torch on (no blown-out glare); if glare is observed, revisit the Step 5 decision and record the result.

#### Verification

- ✅ Build links cleanly; per-file diagnostics clean.
- ✅ QA-026 (unavailable-safe) automated on iPhone 17 Pro Max Simulator — PASS.
- ✅ QA-025 (illumination) and QA-027 (off on every exit path + glare) — manual pass on a physical iPhone (iOS 27.0). Torch lights/extinguishes correctly, off on every exit path, and the captured shelf-tag image is not blown out. See the torch results table in `PhysicalDeviceQATestPlan.md`.

---

### Defect 2: Shopping Empty-State Add Item Can Navigate To Scanner

**Status:** ✅ Resolved · **Reported:** 2026-06-14 · **Closed:** 2026-06-14

#### Current Behavior (as reported)

From the Shopping List empty state, the add-item path could unexpectedly switch to the Scanner tab, and returning to Shopping List then showed the add-item sheet still open. The user asked to add an item, the app navigated to Scanner, and Shopping List retained `isShowingAddSheet = true`, so the sheet appeared on the next visit.

#### Root Cause

The empty state rendered two automatic-style `Button`s inside `ContentUnavailableView`'s `actions` builder, itself inside a `List` `Section`. SwiftUI list rows can share a hit target across multiple automatic-style buttons, so a single tap could fire **both** closures: Add set `isShowingAddSheet = true` while Scan switched `selectedTab` to `.scan`. The Shopping List view stays alive under the `TabView`, so its `@State` persisted and presented the sheet on return.

#### Solution (implemented)

Replaced the `ContentUnavailableView` actions with an explicit, isolated empty-state layout and intent-isolated helpers (`ShoppingListRootView.swift:118-152, 202-213`):

- Custom `VStack` empty state with explicit `.buttonStyle(.borderedProminent)` / `.bordered`, giving each button its own hit target.
- `showAddItemSheet()` — sets `selectedTab = .shopping` (defensive no-op) then `isShowingAddSheet = true`.
- `startScanningFromEmptyState()` — clears `isShowingAddSheet = false` **before** navigating to `.scan`, so the add sheet cannot survive into the next visit regardless of how the tap routed.
- Stable identifiers added for future XCUI: `shoppingEmptyAddItemButton`, `shoppingEmptyScanButton`, `addItemSheet`, `scannerPrompt`.

#### Acceptance Criteria

- Tapping "Add your first item" opens the add-item sheet and stays on Shopping List (`selectedTab == .shopping`).
- Tapping "Scan items as you shop" switches to Scanner (`selectedTab == .scan`) without setting `isShowingAddSheet`.
- Returning from Scanner to Shopping List does not present `AddShoppingListItemSheet`.
- Repeated taps and quick tab switches do not leave stale sheet state behind.

#### Verification

Simulator (iPhone 17 Pro Max, iOS 27.0), corresponding to QA-061 / QA-062:

- **QA-061 — Add stays put: PASS.** "Add your first item" presents the Add Item sheet; the Shopping List tab stays selected; Scanner UI does not appear.
- **QA-062 — Scan navigates cleanly: PASS.** "Scan items as you shop" switches to the Scan tab; returning to Shopping List shows the empty state with no Add Item sheet present.

> XCUI coverage can be added when a `PrixioUITests` target exists; the identifiers above are already in place. No automated UI-test target was added in this pass.
