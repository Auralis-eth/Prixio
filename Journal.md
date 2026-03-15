# Prixio Journal

## The Big Picture
Prixio is the app you reach for when a grocery shelf is making promises your memory will not keep. Snap a shelf tag or product display, let OCR do the messy reading, and save a clean price record you can compare later without playing "was that chips deal actually good?" in aisle seven.

## Architecture Deep Dive
Think of the app like a small kitchen with a very opinionated expeditor.

- SwiftUI is the dining room. It presents the flow, reacts to state, and keeps the experience moving.
- The scanning stack is the line cook. Camera input, OCR, and location gathering prep raw ingredients.
- `PriceParsingService` is the expeditor with a red pen. It takes noisy OCR fragments, throws out junk, groups related lines into product families, and decides which price signal deserves to be trusted.
- SwiftData is the pantry. Once a price record is clean enough, it gets stored in a shape the app can query later.

The important architectural choice here is that OCR interpretation is heuristic-first. That keeps the core extraction path deterministic, debuggable, and fast enough to reason about without handing every problem to a model.

## The Codebase Map
- `Prixio/Prixio/Core`: app shell, shared formatters, shared UI, and model types.
- `Prixio/Prixio/Scanning/Camera`: camera session and preview plumbing.
- `Prixio/Prixio/Scanning/OCR`: OCR result types and extraction services.
- `Prixio/Prixio/Scanning/Price`: the high-noise zone. Normalization, price extraction, and product-family clustering all live here.
- `Prixio/Prixio/Scanning/Stores`: store detection, selection, and session state.
- `Prixio/PrixioTests`: unit coverage, with several parser and OCR sanitation tests already aimed at regression-prone cases.

If you are hunting parsing bugs, start in `PriceParsingService.swift`. That file is doing the work of a whole committee.

## Tech Stack & Why
- SwiftUI, because the app is state-driven and the scanner flow benefits from declarative UI updates.
- Swift Concurrency, because async camera/OCR/location work is cleaner and safer than callback ladders.
- SwiftData, because persisted price entries and store metadata fit the native Apple stack well and keep the project lightweight.
- Vision/OCR-style parsing plus deterministic heuristics, because grocery shelf text is chaotic and the team needs results that can be explained line by line.
- Swift Testing over XCTest, because the lighter syntax fits this codebase better and keeps parser regressions easier to express and maintain.
- Parameterized tests over one-off test methods, because parsing logic usually fails as a family of related inputs rather than as isolated snowflakes.

## The Journey
### March 13, 2026
War story: the product-family clustering logic had a bad habit of acting like flavor text was the whole identity of a product. That meant lines such as `Old Dutch Mesquite BBQ` and `Lays Mesquite BBQ` could end up in the same family because `Mesquite` and `BBQ` were shouting loudly in the keyword overlap score.

The fix was a brand anchor guard in the descriptive-only clustering path:
- Take the first significant token from the incoming line.
- Compare it with the first significant token from the cluster's anchor line.
- If they differ and the incoming token has never appeared in that cluster's keyword map, refuse the merge.

This is the OCR equivalent of checking the jersey name before seating someone on the team bus.

Gotcha: generic descriptor lines like `Selected Varieties` are a different problem entirely. They are low-signal copy, not brand anchors, and should not be treated like one.

### August 16, 2025
Architecture turn: `PriceParsingService` now has the beginnings of a two-stage brain.

Stage one is still the practical, deterministic parser: filter junk, normalize OCR, consolidate lines, and extract price/unit/item hints the old-fashioned way. Stage two is a guarded "ask the model only when the heuristics look shaky" path. That matters because grocery OCR is messy enough to need help sometimes, but not so messy that we should hand the steering wheel to a model on every scan.

The useful lesson here is that Foundation Models are better treated like a specialist consultant than a replacement parser. Let the code do candidate generation and basic sanity checks first. Then, only when the result smells ambiguous, ask the model to break a tie: which lines belong to the product, which existing price candidate is the real one, and what should the product be called in human language.

Gotcha: the `@Generable` response path was less forgiving than expected. Enums looked clean in app code, but the generated schema wanted simpler raw-string fields. The fix was to keep the app-facing result strongly typed while using a raw-string bridge for the generated response. Classic boundary design problem: keep the outside world loose, keep your own house typed.

## Engineer's Wisdom
- Heuristic systems fail at the edges where two different items share the same descriptive vocabulary. Always ask what the true anchor is.
- Cheap scores are useful until they become overconfident. Add guardrails where false merges are more damaging than false splits.
- In parser code, regression tests are not optional. Every weird shelf sign you fix today is tomorrow's boomerang.
- Prefer Swift Testing with parameterized coverage when possible. Parser behavior is easier to trust when one test shape can prove the same rule across many OCR fixtures.

## If I Were Starting Over...
I would split `PriceParsingService.swift` earlier into smaller specialists: noise filtering, normalization, family clustering, and price ranking. Right now it still works, but it has the energy of a drawer full of useful cables that only one person knows how to untangle.
