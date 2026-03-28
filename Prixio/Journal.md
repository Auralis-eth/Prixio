# Journal

## The Big Picture
Prixio is the app you reach for when a shelf tag, a camera, and a little OCR detective work need to become a clean grocery price record. You point it at a product label, it tries to figure out the item, the price, the unit, and the store, and then it saves something structured enough to compare later instead of leaving you with a blurry photo and false confidence.

## Architecture Deep Dive
Think of the app like a grocery store back room with a very opinionated sorting table.

`PrixioApp` is the building manager. It wires up SwiftData so the rest of the app has somewhere permanent to put things.

The scanning flow is the receiving dock. Camera and OCR bring in messy raw material: half-read words, split prices, duplicate lines, and occasional nonsense that looks like a barcode had a bad day.

`PriceParsingService` is the sorter standing at the table. It filters junk, normalizes what OCR garbled, consolidates repeated observations, extracts likely price candidates, guesses unit and quantity, and only then considers whether Foundation Models should step in as a second opinion instead of running the whole store.

## The Codebase Map
The main app code lives under `Prixio/Prixio`.

`Core/Models` holds the domain types like `PriceEntry`, `StoreChain`, and draft objects used to move data through the app.

`Scanning/Camera`, `Scanning/OCR`, `Scanning/Price`, and `Scanning/Stores` split the scan flow into practical stations: image capture, text extraction, price parsing, and store inference.

`PrixioTests` covers parser and normalization behavior. That is the alarm system for regressions in OCR cleanup and price extraction.

## Tech Stack & Why
SwiftUI drives the UI because the app is naturally state-heavy: camera state, OCR progress, parsed results, confirmation sheets, and persistence all benefit from declarative updates instead of hand-managed view bookkeeping.

SwiftData is the storage layer because the app deals in structured records that want a native Apple persistence story without bolting on a full custom database stack.

Vision-style OCR plus heuristic parsing is the right first pass because grocery tags are repetitive in shape but chaotic in capture quality. Deterministic parsing gives speed and predictable failure modes. Foundation Models are more useful as the careful second reviewer than as the cashier handling every transaction.

## The Journey
### Aha! Moment: TODOs Need Addresses, Not Vibes
Once `PriceParsingService` was split into explicit phases, the old TODOs started reading like someone shouting instructions into a foggy warehouse. They described real work, but not where that work belonged.

The fix was not glamorous, but it matters: rewrite the TODOs so each one points at the phase that owns it. Snapshot preparation TODOs now talk about line grouping, OCR fallback, normalization, candidate scoring, unit detection, item-name extraction, and quantity inference as responsibilities of `buildHeuristicSnapshot`. Result confidence work is called out as `makeOCRResult` assembly work.

That sounds small until you revisit the file a week later. A TODO with a clear owner is a work order. A TODO without one is just guilt with punctuation.

### War Story: Text Order Is Not Shelf Order
The first parser TODO looked harmless: use bounding boxes and reading order when grouping lines. Then the code inspection turned up the real issue. `OCRTextObservation` only carried `string` and `confidence`, which meant the parser literally had no geometry to reason about. Asking the snapshot phase to group nearby shelf-tag lines without bounding boxes was like asking someone to sort groceries while blindfolded and wearing oven mitts.

Step one became a plumbing job before it could become a heuristics job. Vision bounding boxes now need to flow into `OCRTextObservation`, survive sanitization and normalization, and only then can the snapshot phase cluster lines into product-level groups. The useful lesson: if a TODO mentions “spatial” anything, verify the data model actually knows where things are before you start tuning heuristics on top of thin air.

### War Story: The Case of the Vanishing Dollar Sign
A parser regression made the tests look worse than they were. The symptom was ugly: simple cases like `"Fresh Bananas"`, `"$3.99"`, `"$2.99"` ended up with no price candidates at all, assisted merge tests returned `price == nil`, and multi-product ambiguity detection suddenly forgot how to notice two products in one frame.

The culprit was not deep in candidate ranking. It was earlier and dumber: the supported-line regex allowed letters, numbers, punctuation, and spaces, but not currency symbols. In Unicode, `$` lives in the currency-symbol class, not punctuation. So price-only lines were getting kicked out at the front door.

That one filter bug had a domino effect:
- no supported price lines
- no cleaned price lines
- no extracted price candidates
- no competing-price signal
- no multi-product scan signal

The fix was small and surgical: include `\\p{Sc}` in `supportedOCRLinePattern`. One character class change, several test failures gone.

Lesson: when parser behavior suddenly goes strange everywhere, inspect the earliest gate in the pipeline first. A bad filter upstream can make downstream heuristics look guilty when they are just starving.

### War Story: The Shelf Tag Was Real, the Evidence Pipeline Was Too Picky
Step two of the parser checklist turned up a more subtle failure mode. Spatial grouping was doing the right thing by focusing on the strongest product cluster, but `removeObviousNoise` could still get overconfident and toss the only usable price evidence when OCR came back thin. A line like `"399"` is ugly, but on a blurry shelf tag it might be the difference between recovering `$3.99` and shrugging at the user.

The fix was to stop treating snapshot preparation like a trapdoor. `buildHeuristicSnapshot` now walks a fallback ladder:
- cleaned focused observations first
- then broader cleaned observations
- then full supported observations
- and finally a minimally sanitized last resort that preserves evidence instead of over-policing it

The important engineering lesson here is that parser pipelines should degrade like a cautious driver, not fail like a motion sensor. If the clean path loses the plot, widen the search in a deterministic way before you give up. The tests now cover exactly that: sparse tags that still recover implied prices, sparse tags that keep both a description and a price, and healthy spatial groups that do *not* suddenly invite the neighboring Pepsi into the banana conversation.

### War Story: OCR Loves Inventing Prices, Just Not in the Format You Wanted
Step three was all about teaching normalization to stop acting surprised when OCR mangles a perfectly ordinary shelf tag. Grocery pricing lines do not just come back as neat `$1.29 /lb`. They come back as `1,29/lb`, `1 29 /lb`, or the especially rude `S299ea`, which looks like a price token and a unit token got trapped in a dryer together.

The parser already knew how to extract prices and units once the text looked vaguely civilized. The missing piece was a small repair station before extraction: fix merged price/unit lines, convert comma decimals into the dot form the parser expects, and canonicalize obvious standalone price lines into currency text. In other words, stop asking the candidate extractor to decode a ransom note.

The nice part is that this stayed deterministic. No new ranking rules, no unit-parser rewrite, just better prep work. That is a useful lesson in parser design: when downstream logic seems “weak,” first ask whether the upstream text is forcing it to solve a harder problem than necessary.

### War Story: Not Every Dollar Sign Deserves Equal Respect
Step four finally tackled candidate scoring, which is where the parser has to stop acting like every number with two decimals won the same election. Shelf tags routinely contain a real shelf price, a regular fallback price, a member promo, and sometimes a tiny deposit line lurking nearby like a raccoon near a campsite.

The parser already knew how to *find* prices. The problem was choosing between them with enough common sense to avoid escalating perfectly ordinary tags. The fix stayed local to `buildHeuristicSnapshot`: extract candidates as before, then re-rank them with context signals the snapshot already understands.

The useful signals turned out to be refreshingly practical:
- Is this price close to descriptive product text?
- Does the line look promotional?
- Does it carry a unit label like `ea` or `/lb` that makes it smell like the main price?
- Does it say `regular`, `was`, or `deposit`, which usually means “important, but not the price you tap first”?

That changed the parser from “two prices, panic” to “two prices, read the room.” A nearby `"$1.49 ea"` now beats a more distant plain `"$2.49"` when the product text is clearly attached to the first line. A `Sale $3.99 ea` line outranks `Regular $4.99 ea`. And a `"$0.10 deposit"` line gets treated like the side quest it is.

There was one annoying side quest on the tooling side too: validation from the assistant harness ran into a `TestingMacros` plugin path conflict between two local Xcode installs, plus flaky MCP test execution. The good news is that the project build now succeeds again from the harness. The bad news is that targeted parser test runs still refuse to behave like adults: one invocation returned `No result` for every selected test, and the follow-up run timed out. So the scoring work is in, the service file diagnostics are clean, the build is green, and the remaining problem is squarely in harness-level test execution rather than the candidate-ranking code itself.

## Engineer's Wisdom
Good parser work is less about cleverness than about preserving evidence. Every time you add a filter, ask: "What legitimate OCR junk am I about to throw away?" Grocery text is noisy by nature, and prices often appear on lines that look sparse or symbol-heavy. If the pipeline drops those lines too early, later stages cannot recover with confidence because the evidence is gone.

A senior-engineer move here is to fix the narrowest broken assumption instead of layering in compensating logic everywhere else. That keeps the system legible.

## If I Were Starting Over...
I would make the OCR pipeline stages more observable from day one. Snapshot-style tests are already helping, but a tiny debug surface that prints supported, cleaned, normalized, consolidated, and extracted candidates for a fixture would make regressions like this much cheaper to diagnose. The bug was simple. Finding where the evidence disappeared was the real work.
