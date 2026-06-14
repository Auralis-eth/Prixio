# Camera Performance Implementation Plan

## Source
This plan comes from the WWDC 2026 session "Build a responsive camera app that launches quickly" and the current Prixio camera flow.

Prixio already uses `AVCaptureVideoPreviewLayer` through `CameraPreviewView`, which is the right rendering path for this app. The app does not need per-frame camera buffers today, so the camera performance work should keep the preview layer path and focus on faster time-to-preview, responsive still capture, and sustained behavior under pressure.

## Current Implementation Status
This document has been updated after the uncommitted camera changes currently in the workspace.

Implemented in `Scanning/Camera/CameraController.swift`:
- `isCaptureReady` is now published for diagnostics and future shutter gating.
- `AVCaptureSession.automaticallyRunsDeferredStart` is explicitly enabled during session configuration.
- `AVCapturePhotoOutput.isDeferredStartEnabled` is enabled when supported, after the output is attached to the session.
- `AVCapturePhotoOutput.isResponsiveCaptureEnabled` is enabled when supported.
- `photoOutput.maxPhotoQualityPrioritization` is set to `.quality`.
- Per-capture `AVCapturePhotoSettings.photoQualityPrioritization` is set to `.quality`.
- Duplicate shutter requests are dropped while a capture continuation is already in flight.
- Capture continuations are now resolved on `sessionQueue` so access stays serialized.
- `CameraController` conforms to `AVCaptureSessionDeferredStartDelegate`.
- `sessionDidRunDeferredStart(_:)` sets `isCaptureReady = true` on the main actor.

Implemented in `Scanning/Camera/CameraPreviewView.swift`:
- The preview layer explicitly sets `isDeferredStartEnabled = false`.
- The preview layer remains `resizeAspectFill`.

Not implemented yet:
- Launch and capture signposts.
- Scan startup reordering so store/location work is clearly off the preview critical path.
- `AVCapturePhotoOutputReadinessCoordinator` or richer readiness modeling.
- System pressure observation.
- Real-device timing validation.
- `Journal.md` entry for the camera launch architecture decision.

Related uncommitted work outside this plan:
- `Scanning/OCR/OCRService.swift` currently contains an experimental iOS 27 `FoundationModels` / `PrivateCloudComputeLanguageModel` path. That is not part of this camera performance plan and should be reviewed separately before shipping because it changes OCR behavior, availability, and failure modes.

## Goals
- Make the camera feel ready as soon as the scan screen opens.
- Preserve immediate shutter usefulness after adopting deferred photo-output startup.
- Keep camera setup and `startRunning()` off the main thread.
- Avoid expensive store/location/OCR work on the preview launch critical path.
- Add measurement so improvements are proven instead of guessed.

## Non-Goals
- Do not switch to `AVCaptureVideoDataOutput` unless Prixio later needs per-frame preview processing or custom Metal rendering.
- Do not implement `AVProVideoStorage`; Prixio captures still photos for OCR, not high-data-rate ProRes video.
- Do not refactor OCR, parsing, compare, or shopping flows as part of the camera performance pass.
- Do not gate the shutter purely on `isCaptureReady`; responsive capture is intended to keep early shutter taps useful before deferred start finishes.

## Current Code Touch Points
- `Prixio/Prixio/Scanning/Camera/CameraController.swift`
  - Owns `AVCaptureSession`, `AVCapturePhotoOutput`, deferred start, responsive capture, startup, and photo capture.
- `Prixio/Prixio/Scanning/Camera/CameraPreviewView.swift`
  - Hosts `AVCaptureVideoPreviewLayer` in SwiftUI and explicitly keeps preview non-deferred.
- `Prixio/Prixio/Scanning/ScanRootView.swift`
  - Starts camera preparation and also kicks off location/store work. This is still the main startup sequencing opportunity.
- `Prixio/Prixio/Journal.md`
  - Should get a short entry when this work lands because it is an architectural decision about scan launch sequencing.

## Phase 1: Measure The Existing Launch Path
Status: not implemented.

Add signposts around the scan launch sequence before declaring the performance work complete.

Suggested events:
- Scan screen task started.
- Camera authorization completed.
- Session configuration started.
- Session configuration committed.
- `startRunning()` started.
- `startRunning()` completed.
- Preview view created.
- Photo capture requested.
- First photo delegate callback received.
- Deferred start began.
- Deferred start completed.

Use Instruments after adding signposts:
- App Launch template for cold launch and scan-tab entry.
- Time Profiler for camera/session work.
- Hangs template to verify no main-thread camera blocking.

Primary metric:
- Time from entering the scan flow to visible camera preview.

Secondary metrics:
- Time from shutter tap to first capture callback.
- Time from `startRunning()` completion to deferred start completion.
- Whether nearby store loading overlaps preview startup.
- Whether the main thread blocks during session setup or start.

## Phase 2: Split Critical And Deferred Scan Work
Status: not implemented.

Current scan startup still performs camera preparation, SwiftData seeding, location authorization, and nearby store loading in the same `.task` flow.

Change the startup shape so preview wins:

1. Configure recent items and seed store chains if needed.
2. Start camera preparation as the critical path.
3. Request location authorization after camera preparation has started or completed.
4. Load nearby stores after preview startup is underway.

The store chip can show its existing fallback state while nearby stores load. Store detection is useful, but it is not required for the first preview frame.

Implementation notes:
- Keep UI state changes on the main actor.
- Keep camera session work on `CameraController`'s `sessionQueue`.
- Avoid starting multiple overlapping store loads if location changes while the first load is still in flight.

## Phase 3: Automatic Deferred Start
Status: implemented in the uncommitted camera patch.

Current implementation:
- `CameraController.configureSession()` sets `session.automaticallyRunsDeferredStart = true`.
- `photoOutput.isDeferredStartEnabled = true` is set when `isDeferredStartSupported` is true.
- `CameraPreviewView` explicitly sets `previewLayer.isDeferredStartEnabled = false`.
- `startRunning()` remains on `sessionQueue`.

Why automatic mode:
- Prixio renders preview with `AVCaptureVideoPreviewLayer`.
- With the preview layer as the only non-deferred output, the system can run deferred output initialization shortly after the first preview frame.
- Manual deferred start is only needed if Prixio later moves to custom preview rendering with `AVCaptureVideoDataOutput`.

Compatibility notes:
- The app target currently has `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, so the iOS 26 deferred-start API usage is aligned with the target.
- If the deployment target is lowered later, add availability guards around deferred-start APIs.

## Phase 4: Deferred Start Delegate State
Status: partially implemented in the uncommitted camera patch.

Current implementation:
- `CameraController` conforms to `AVCaptureSessionDeferredStartDelegate`.
- `setDeferredStartDelegate(_:deferredStartDelegateCallbackQueue:)` is called with `sessionQueue`.
- `sessionDidRunDeferredStart(_:)` sets `isCaptureReady = true`.
- `sessionWillRunDeferredStart(_:)` is currently a placeholder.

Remaining work:
- Emit signposts from both delegate callbacks.
- Consider publishing a richer readiness enum only if UI or diagnostics need more than `isCaptureReady`.
- Consider setting `isCaptureReady = false` before reconfiguration or when the session stops, if future flows reconfigure the session.

A richer state could look like this later:

```swift
enum CameraReadiness {
    case idle
    case configuring
    case previewStarting
    case previewRunning
    case photoOutputWarming
    case ready
    case pressureLimited
}
```

Do not add this enum until it has a real consumer. The current boolean is enough for diagnostics and keeps the first patch small.

## Phase 5: Responsive Capture
Status: implemented in the uncommitted camera patch.

Current implementation:
- `photoOutput.isResponsiveCaptureEnabled = photoOutput.isResponsiveCaptureSupported`.
- `photoOutput.maxPhotoQualityPrioritization = .quality`.
- Each capture creates fresh `AVCapturePhotoSettings`.
- Each capture sets `settings.photoQualityPrioritization = .quality`.
- Flash mode is still validated against `supportedFlashModes`.
- Duplicate capture requests are ignored while another capture is in flight.

Why this matters:
- Deferred photo output can make preview appear sooner while photo resources are still warming.
- Responsive capture helps preserve the user's early shutter tap instead of making fast preview come at the cost of missed captures.

Remaining validation:
- Confirm an immediate shutter tap after preview appears still produces an image.
- Measure shutter-to-first-callback before and after deferred start finishes.
- Confirm duplicate-tap behavior is acceptable in the UI.

## Phase 6: Track Capture Readiness
Status: minimally implemented with `isCaptureReady`; richer readiness tracking remains open.

Current implementation:
- `isCaptureReady` flips to true after deferred start completes.
- The shutter remains available before this because responsive capture should buffer early taps.

Remaining options:
- Use `AVCapturePhotoOutputReadinessCoordinator` if UI needs precise readiness transitions.
- Use `photoOutput.captureReadiness` where available if a lightweight state check is enough.
- Surface readiness in a debug diagnostics UI rather than adding user-facing complexity immediately.

Recommended product behavior:
- Show the shutter immediately.
- Allow capture immediately if responsive capture is enabled and the output can accept requests.
- Avoid blocking the whole scan UI while deferred start completes.

## Phase 7: Monitor System Pressure
Status: not implemented.

Store the active video input/device in `CameraController` so the controller can observe system pressure.

After configuration:
- Log `session.hardwareCost` for diagnostics.
- Observe `device.systemPressureState`.
- On `.serious` or worse, reduce nonessential work.

For Prixio, first responses should be conservative:
- Avoid starting extra non-camera work during preview startup.
- Defer OCR until after capture, as it already does.
- Avoid adding live per-frame analysis.
- Consider frame-rate reduction only after profiling shows it helps.

Implementation notes:
- Keep the observer retained by `CameraController`.
- Remove or invalidate observers on deinit if needed.
- Avoid expensive work inside the KVO callback.

## Phase 8: Validate On Real Devices
Status: not completed.

Simulator is not enough for this work.

Manual validation:
- Cold launch to scan screen.
- Warm navigation back to scan screen.
- Immediate shutter tap after preview appears.
- Permission first-run flow.
- Denied camera permission flow.
- Flash on/off capture.
- Duplicate shutter taps.
- Retake after confirmation sheet dismissal.
- Save after confirmation sheet dismissal.
- Background/foreground while scan screen is visible.

Performance validation:
- Compare signpost timings before and after.
- Verify `startRunning()` never runs on the main thread.
- Verify nearby store loading no longer delays first preview after startup reordering lands.
- Verify deferred start callbacks fire on supported OS versions.
- Verify photo capture works before and after deferred start completion.

Thermal validation:
- Run repeated scan/capture cycles on a physical device.
- Watch `systemPressureState` transitions once pressure observation is implemented.
- Confirm pressure handling does not crash or leave the camera stuck.

## Remaining Patch Order
1. Add signposts to `CameraController`, `CameraPreviewView`, and `ScanRootView` where useful.
2. Split scan-screen startup so camera preparation is first-class and nearby store loading is deferred.
3. Decide whether `isCaptureReady` is enough or whether `AVCapturePhotoOutputReadinessCoordinator` is needed.
4. Add system-pressure observation.
5. Build and run physical-device QA.
6. Update `Journal.md` with the camera launch architecture note.
7. Separately review the uncommitted `OCRService` FoundationModels experiment before merging it with camera work.

## Risks And Mitigations
- **Risk: shutter appears ready before photo output can respond.**
  - Responsive capture is enabled; validate immediate shutter taps on device.

- **Risk: duplicate shutter taps confuse continuation ownership.**
  - Current implementation drops duplicate requests while one continuation is in flight. Validate the UX and consider disabling or animating the shutter during capture if needed.

- **Risk: deferred start masks first-capture latency.**
  - Measure shutter-to-callback timing separately from preview launch timing.

- **Risk: store detection feels slower after startup reordering.**
  - Keep the existing fallback store chip copy and update it when candidates arrive.

- **Risk: system-pressure response becomes too aggressive.**
  - Start with logging and conservative work deferral. Lower frame rate only if measured pressure problems remain.

- **Risk: unrelated OCR experiment changes scan outcomes while validating camera work.**
  - Review or isolate the iOS 27 FoundationModels OCR path before using scan result quality as a camera-performance validation signal.

## Later Ideas
- Add a lightweight launch performance test that records scan-screen signpost intervals.
- Track P90 camera-preview startup time across local QA runs.
- Add a debug camera diagnostics panel showing readiness, hardware cost, and pressure state.
- Revisit manual deferred start only if Prixio adopts custom frame rendering.
