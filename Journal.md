# Journal

## The Big Picture
Prixio is the app you use after that tiny produce sign or blurry shelf tag wins the first round. You snap a photo, the app tries to read the chaos, and it turns that mess into something you can actually compare later: what item, what store, what price, and in what unit.

## Architecture Deep Dive
Think of the app like a grocery store back room with three workers:

- SwiftUI is the cashier up front. It handles the interaction, shows suggestions, and lets you correct anything the app guessed wrong.
- Vision is the hurried stock clerk reading labels from a shaky photo. It gets a lot right, but sometimes it mumbles.
- `ScanDomain.swift` is the department manager. It takes the clerk’s half-legible notes, decides what looks like a real price, normalizes units, and packages the result for storage.

SwiftData is the pantry. Once a price is trustworthy enough, it gets shelved there for later comparisons.

## The Codebase Map
- `Prixio/PrixioApp.swift`: app entry and model container wiring.
- `Prixio/needs code sanitation/ContentView.swift`: scanner flow, confirmation UI, and applying OCR suggestions into the draft.
- `Prixio/needs code sanitation/ScanDomain.swift`: the parsing brain. OCR services, price extraction, unit logic, store inference, and repository helpers live here.
- `PrixioTests/PrixioTests.swift`: unit tests for parser behavior and draft rules.
- `PrixioUITests/*`: smoke-test territory.

## Tech Stack & Why
- SwiftUI, because the app is state-heavy and the scan-confirm-save loop maps naturally onto declarative UI.
- Vision, because OCR is the first unavoidable step and Apple already ships the machinery.
- SwiftData, because the app wants structured local persistence without building a storage framework from scratch.
- Apple’s `Testing` framework, because parser regressions are exactly the kind of thing that quietly hurt users unless you pin behavior down with tests.

## The Journey
- We finally muzzled a noisy OCR gremlin in `PriceParsingService`: English-only shelf photos were still producing Cyrillic-looking tokens like `Сабвич`, which then flowed downstream as if they were real product text. The fix was a line-level sanitizer that keeps Latin-script text (including French-friendly accents), numbers, punctuation, and spaces, and drops unsupported-script lines before price extraction and summarization. Practical result: fewer hallucinated item hints, cleaner prompt input, and confidence now reflects surviving text instead of junk lines.
- We put a seatbelt on nearby store lookup. `StoreDetectionService` was firing a burst of `MKLocalSearch` queries one after another, which is basically yelling every grocery-related keyword at MapKit in rapid succession and hoping it stays polite. Now queries are deduplicated, capped, and paced with a small delay between calls, plus throttled requests get one delayed retry instead of being dropped immediately.
- We fixed a meaningful OCR blind spot: the app used to keep only the recognized text string and discard Vision’s confidence score. That meant two prices with the same regex priority were effectively decided by value, which is a terrible tie-breaker if one number came from a shaky read.
- The parser now carries both the OCR `string` and its `confidence` together, and every extracted `PriceCandidate` keeps that provenance. Translation: we stopped treating all OCR lines like equally trustworthy eyewitnesses.
- Split prices are still a little dramatic. Shelf tags love to put dollars on one line and cents on another, so the parser explicitly checks adjacent OCR lines as a pair. That bug class is the software equivalent of someone saying “seventeen” in one room and “ninety-nine” from the hallway.
- We also started evicting persistent models from `ScanDomain.swift`. Moving `PriceEntry` into `Core/Models` is the codebase equivalent of finally taking the plates out of the toolbox: the parser still uses them, but it should not have to store them in the same drawer.
- The photo import flow graduated from a UIKit chaperone to SwiftUI’s native `PhotosPicker`. That let us delete the `UIImagePickerController` wrapper entirely while keeping the live camera path on `AVCaptureSession`, which is the right split: use the built-in front desk for library browsing, keep the custom machinery for actual capture.
- We squashed a sneaky race in `ScanViewModel`: scan A could still be doing OCR while the user had already retaken the photo and started scan B. Without a notion of “which async job currently owns the draft,” the older result could wander back late and repaint the form with stale text. The fix was intentionally boring and that is a compliment: each scan now gets an ID, and any late-arriving work that no longer owns the draft is ignored on sight.

## Engineer's Wisdom
- Preserve signal as long as possible. Throwing away confidence early is like deleting the “how sure are we?” column before making a decision.
- Rank candidates using the information source, not just the extracted value. A parser that only sorts by number size will confidently choose the wrong thing the moment OCR gets noisy.
- Tight tests around parsing logic pay for themselves quickly. OCR bugs do not announce themselves with polite compiler errors.

## If I Were Starting Over...
- I’d split `ScanDomain.swift` sooner. Right now it works, but it feels like one overstuffed kitchen drawer where the scissors, batteries, and soy sauce packets somehow all live together.
- I’d also introduce a dedicated parser model for OCR observations earlier, because confidence, source line, and normalized text all want to travel together. Reconstructing that later is more annoying than just modeling it honestly from the start.
