# Camera Performance Implementation Plan (retired)

This planning doc has been folded into the durable project records and is kept only as a redirect.

- **Shipped work** (automatic deferred start, responsive capture, `maxPhotoQualityPrioritization = .quality`,
  duplicate-shutter suppression, `isCaptureReady` after deferred start, non-deferred
  `AVCaptureVideoPreviewLayer`): documented in `LLMAppContext.md` → **Camera Layer**.
- **Remaining work** (launch/capture signposts + Instruments measurement, splitting camera prep from
  store/location loading on the scan-startup critical path, richer readiness modeling, system-pressure
  observation, the `Journal.md` architecture note): tracked in `OutstandingWork.md` → **item 7,
  Camera Launch Performance**, including the locked non-goals.
- **Device/thermal validation**: `PhysicalDeviceQATestPlan.md` → **section 8, Camera Launch
  Performance (device)** (QA-140–QA-144).

Per `OutstandingWork.md`, that file replaces older planning/checklist markdown like this one.
