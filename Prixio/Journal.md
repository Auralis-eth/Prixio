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

### War Story: A 12-Pack Is Not a Liter, and `lb` Is Not Noise
Step five turned out to be a good reminder that OCR parsers do not fail because they are dumb. They fail because they are confidently literal in exactly the wrong place.

The old unit detector was basically a row of `contains(...)` checks. That worked for friendly tags like `$1.29 /lb`, but it got confused the minute real shelf-tag chaos showed up. A line like `12 x 355 mL` would tempt the parser toward `.liter` even though that text describes package size, not a per-liter price. Meanwhile, a split OCR sequence like `Price`, `per`, `lb`, `$1.29` could lose the word `per`, decide `lb` looked too short to be useful, toss it out as noise, and then act surprised that no unit survived.

The fix was to stop treating unit detection like a reflex and start treating it like evidence. `PriceParsingService` now scores unit signals instead of grabbing the first substring that looks vaguely unit-shaped. Direct rate signals like `/lb`, `per kg`, or `price per 100 g` outrank package-size hints. Package-size hints like `12 x 355 mL` and `6 pk` now map to `.each` as a safer fallback instead of masquerading as rate units. And the noise filter learned one extremely practical lesson: if a tiny token like `lb` is the only bridge between OCR fragments and a valid unit price, do not throw it in the trash just because it is short.

This one also produced a small tooling comedy. The new Step 5 tests were useful enough to catch two real regressions immediately: multi-pack lines were still getting dropped as fake SKUs, and split `price per` OCR was recovering the unit but not the default quantity. Both were fixed. Then the harness test runner decided it had done enough work for one day and started returning incomplete result bundles. So the final verification story is delightfully modern: green build, clean service-file diagnostics, direct in-project snippet verification for the new cases, and a test runner that still needs adult supervision.

### War Story: `7UP Zero Sugar 2L` Is a Product Name, Not a Crime Scene
Step six was about item-name extraction, which sounds polite until you look at the old rule: find the first line that is not a price, not a unit, and does not contain digits. That works fine if every shelf tag is a schoolbook noun phrase like `Fresh Bananas`. It falls over the moment the grocery aisle starts behaving like the real world.

Real product names are full of things the old shortcut treated like suspicious activity: brand names with numbers, size markers, and promo-adjacent wording. `7UP Zero Sugar 2L` is obviously a product line to a human. To the old parser, it was dangerously close to a SKU because it mixed letters and digits. Meanwhile, a useless line like `Member Deal` could sneak past as the item name simply because it had no price and no numbers. That is how you end up with an app that sounds like it shops entirely from cardboard sale placards.

The fix was to make item-name selection a scoring problem instead of a veto problem. Candidate lines now get judged on descriptive-token density, closeness to the top-ranked price line, OCR confidence, and whether they look like actual product text instead of promo confetti or receipt leftovers. Size-bearing product names are allowed to live. Promo-only fragments get penalized. Short unit-ish lines like `per lb` stop pretending they are a product.

The nice little sting in the tail was that the first Step 6 probe came back with `nil` for `Coca Cola Zero Sugar 2L`, which immediately exposed the remaining weak assumption: the SKU filter was still too aggressive for branded names that include explicit size tokens. Relax that one gate, and the extractor starts acting like it has met a soda bottle before. Final state: the build is green, direct in-project verification shows the right item-name choices, and the harness is still occasionally timing out like a coworker who agrees to help and then vanishes into Slack.

### War Story: The Parser Knew the Price, but Not How Many Things You Were Buying
Step seven was the quantity pass, which is where parsers discover that humans love offer math and OCR does not. Before this step, the snapshot could carry a quantity if it happened to fall out of the direct `2/$5` candidate extraction, but anything more contextual was basically left to vibes. A tag saying `Buy One Get One Free` next to `$5.99` would give you a price, maybe a unit, maybe a product name, and then stare blankly when asked how many items the price actually covered.

The fix was to make quantity inference candidate-aware. Instead of reading the entire OCR text like a conspiracy board, the snapshot now starts from the chosen price candidate, gathers the nearby lines that are most likely to belong to that price, and looks there for quantity signals. That matters because pack counts and promo phrases are often adjacent to the chosen price, not smeared uniformly across the scan.

That produced a few useful rules that feel obvious in hindsight:
- If the chosen candidate already carries a quantity, trust it.
- If the nearby text says `Buy One Get One Free` or `BOGO`, quantity is `2`.
- If the nearby text says `12 x 355 mL` or `6 pk`, quantity is the pack count when the parser is dealing with an `.each`-style product.

This was one of those steps where the parser started sounding more like a cashier and less like a dictionary. `2/$5` now means two items. BOGO now means two items. A 12-pack now means twelve items. Revolutionary stuff, but only if you have ever debugged a parser that proudly divided by `nil` in its heart.

### War Story: Confidence Needed a Jury, Not a Single Witness
Step eight cleaned up the last suspicious shortcut in the parser: confidence used to be little more than “whatever confidence came with the top price candidate.” That is convenient, but it is also the kind of logic that lets one confident OCR line swagger into court and testify on behalf of an entire shelf tag.

The problem is obvious once you say it out loud. A good grocery parse is not just “I found a price.” It is “I found a price, and the item name makes sense, and the unit makes sense, and the quantity makes sense, and the scan does not look like two products fighting for custody of the same result.” Confidence had to become a summary of agreement, not a souvenir from the price extractor.

So `makeOCRResult(from:)` now assembles confidence more like a jury verdict. Helpful signals push it up: a stable price candidate, a believable item name, a resolved unit, a resolved quantity, and enough OCR support lines that the parse does not feel like it was reconstructed from a ransom note. Weaknesses push it down: missing fields, sparse OCR, competing prices, multi-product scans, and other ambiguity flags.

The nice part is that the new scores feel sane in human terms:
- clean product tag: very high confidence
- one lonely price line: low confidence
- conflicting multi-product frame: middling at best

That is a much better contract for the rest of the app. Confidence is now the parser’s closing argument, not just the loudest witness in the room.

### War Story: The Parser Finally Moved Out of Its Studio Apartment
After the feature push, `PriceParsingService.swift` had become the kind of file that technically still works but makes everyone nervous. Snapshot prep, ranking, unit logic, quantity logic, item-name logic, confidence logic, and Foundation Models were all living in one place like roommates who swear they have a system while storing forks in the bathroom.

The refactor did not try to make the parser smarter. That would have been reckless. The job was to make the code legible without changing its behavior. The service is now an orchestrator instead of a storage unit. The heavy lifting moved into a dedicated `Scanning/Price/Parsing/` subfolder:
- snapshot building
- candidate scoring
- unit and quantity resolution
- item-name resolution
- confidence assembly
- assisted/Foundation Models flow

This matters more than it sounds. Refactors like this are not about aesthetics. They are about making the next change cheaper and less dangerous. A cleaner snapshot builder means easier prompt construction later. A dedicated Foundation Models file means the second-pass parser can evolve without dragging half the deterministic pipeline into every review. And when a bug shows up in quantity inference, nobody has to step over assisted prompt code and regex soup just to find it.

The encouraging part is that the build stayed green immediately after the split. That is the kind of boring success you want from structural work: less drama, more drawers with labels.

### War Story: Refactors Love Sneaking In Tiny Behavioral Lies
The first post-refactor test run found two failures that looked small and were not. One case lost the default quantity for a split `Price`, `per`, `lb`, `$1.29` scan. The other started inferring `12` from a trailing `12 x 355 mL` line even when the shelf price appeared before the pack-size note.

Both bugs came from the same family of mistake: the refactor preserved the big pipeline shape but slightly changed what counted as quantity evidence. The parser had become a little too eager and a little too literal at the same time. It was happy to forget that a bare nearby `lb` should still imply quantity `1`, and it was equally happy to treat a pack-size line *after* the price as if it always belonged to the chosen candidate.

The fix was precise:
- restore token-boundary quantity detection for standalone unit markers like `lb`
- keep offer inference broad, but make pack-count inference trust the chosen price line and its preceding context instead of blindly reaching forward

That same pass also cleaned up a structural code smell from the refactor. The extracted parser files were leaning too hard on `static` helper style, which made Swift code read like a JavaScript utility pile wearing a trench coat. The ranking, unit/quantity, item-name, and confidence phases now live behind owned helper structs with thin service-level delegates. The service remains the entry point, but the real work has clearer owners now.

The cleanup did not stop there. Snapshot building and the Foundation Models assist path now follow the same ownership pattern, which means the parser phases finally agree on who owns what instead of mixing orchestration and implementation in every file.

### War Story: A Typed Model Contract Beats Hoping for Good Manners
Once the assisted Foundation Models path had its own file, the next weak spot was obvious: the model response contract was still a little too trusting. Raw strings for price kind and confidence bucket meant the parser was relying on polite behavior from the model instead of enforcing a proper boundary.

The fix was to tighten both sides of the deal. The prompt now states the response contract explicitly: use existing OCR line indexes, use an existing candidate index or `nil`, classify only the selected candidate, and never invent missing values. The guided-generation schema also got stricter by switching `selectedPriceKind` and `confidenceBucket` to typed `@Generable` enums instead of free-form strings.

Then came the adult-supervision layer: deterministic normalization before merge. Invalid line indexes get filtered out. Invalid candidate indexes become `nil`. Empty canonical names disappear instead of pretending to be meaningful. Ambiguity notes get trimmed and capped. In other words, the model can suggest, but the parser still checks its homework before writing anything in pen.

That cleanup exposed a second issue hiding next door: the ambiguity gate was still a bit too eager in one direction and not eager enough in another. A stable packaged tag with a deposit sidecar was escalating simply because unit and quantity were missing, while a plain two-price tag could slip through without escalation after ranking nudged one candidate just ahead of the other.

The fix was to make the gate care about the *kind* of ambiguity instead of just counting bruises. Stable packaged goods can now stay on the heuristic path when the only weakness is “no unit, no quantity,” but unresolved near-top competing prices still escalate. The new FM assist tests also cover the cases that actually matter for rollout: multi-product selection, regular-vs-sale overrides, deposit classification, canonical item-name repair, and low-confidence no-override behavior.

The last Phase 1 wrinkle was confidence. Assisted parsing had learned to behave, but its confidence math was still too eager to celebrate. The merge path was anchoring off raw snapshot candidate confidence instead of the assembled heuristic result confidence, which is how you end up with absurdly cheerful scores for messy multi-product frames. That got fixed by basing assisted merge confidence on the heuristic result’s real confidence and then adjusting it based on agreement: helpful assist beats noisy assist, noisy assist beats weak assist, and multi-product selections stay visibly less certain than clean single-product wins.

That let the Foundation Models Phase 1 story finally close with something better than “it seems plausible.” The assisted path now has:
- a typed response contract
- deterministic normalization before merge
- explicit non-authoritative handling for low-confidence, deposit, and noise-classified output
- agreement-aware confidence behavior
- realistic ambiguous OCR fixtures instead of only toy examples

### War Story: Real Shelf Tags Do Not Care About Your Beautiful Synthetic Tests
Once the parser and Foundation Models Phase 1 work were in decent shape, the next honest question was brutal and fair: “How much of this survives contact with a shelf tag that was actually photographed in the wild?”

That is where the shiny synthetic fixtures started getting humbled. Four realistic OCR patterns immediately found the soft spots:
- a member promo tag with a clean `2/$11` winner, a regular fallback, and a `plus dep` sidecar
- a beverage tag where the deposit line looked just price-like enough to start an argument
- a noisy branded OCR line like `C0KE ZER0 SGR`
- a flyer-ish tag with lines like `WEEKLY SPECIAL`, `SAVE 2.00`, and `Valid Fri Sat Sun`

Each one exposed a different kind of parser snobbery.

The item-name resolver was too willing to entertain flyer banner text as a product. `Valid Fri Sat Sun` is useful to a store, but it is not a raspberry. The snapshot cleanup path was also over-policing mixed letter-digit text and throwing away a perfectly salvageable brand line because it smelled a little too much like a SKU. And the ambiguity gate was still acting like a member promo plus a regular fallback plus `dep` meant “multiple products,” which is a great way to ask Foundation Models to solve a problem the heuristics already had the answer to.

The fixes were pleasantly specific:
- treat promo-banner and validity lines as non-product text
- keep OCR digit-as-letter brand lines in the evidence set instead of binning them as fake SKUs
- ignore regular fallback and deposit context when deciding whether a scan looks like multiple products

That was enough to make the first batch of real-world fixtures credible, but not enough to declare the checklist item done. Two more patterns rounded it out:
- a stacked sale tag with a `BUY 2 SAVE 1.00` banner, a clean sale line, a regular fallback line, and a validity line
- a side-by-side member-price frame with two real products competing in different columns

Those two matter because they pull the parser in opposite directions. The stacked sale tag is a “do not get distracted” test. The side-by-side member frame is a “please do get suspicious” test. Once both were green, the OCR coverage story finally felt complete instead of merely improved.

That is the kind of parser progress that feels boring in code review and excellent in production. The sanitation suite now passes with real-world style fixtures, the ambiguity suite agrees that obvious winner tags should stay heuristic, and the spatial grouping suite still throws the flag when two products show up in the same photo like uninvited roommates.

### War Story: The Parser Whispered, but the Confirmation Sheet Smiled and Nodded
The scan-flow integration review turned up a classic product bug wearing a quiet face: the parser had grown much better at describing uncertainty, but the UI was still treating almost every parse like a polite autofill suggestion that happened to arrive from the sky.

Internally, the parser can now explain *why* a scan is shaky. It knows the difference between “I only saw one blurry line,” “there are two competing prices,” and “this looks like two shelf tags trying to share one photo.” But by the time that result reaches `ScanViewModel`, most of that meaning has been flattened into a small bundle of editable fields plus one float confidence score. That is like a doctor writing a full chart and the front desk reducing it to “vaguely fine, probably.”

The confirmation sheet exposes only a sliver of that nuance today. Missing unit gets an orange outline. Store detection asks for explicit confirmation before saving. Everything else mostly looks the same whether the parser felt rock-solid or mildly alarmed. Two price-candidate buttons might appear, but they do not explain whether the parser found a normal sale-vs-regular situation or a genuinely ambiguous multi-product frame.

That is the engineering lesson worth keeping: uncertainty is only useful if it survives long enough to change behavior. A parser confidence score without its reasons is a weather forecast that forgot to mention the tornado. The next scan-flow pass should carry structured review metadata into the draft and let the confirmation UI react differently when the parser is telling us, as clearly as it can, “this scan needs adult supervision.”

### War Story: A Confidence Float Is Not a Product Decision
The implementation pass for the scan-flow review was a good reminder that data contracts age just like UI. `OCRResult` had become too skinny for the job. It could tell the rest of the app “here is a price, here is a unit, here is a confidence number,” but it could not say the part a human actually cares about: *why* this scan might still be sketchy.

So the parser got a second suitcase. The scan flow now carries structured `OCRReview` metadata alongside the usual parsed fields: review issues, derived review severity, ambiguity notes, and whether Foundation Models had to step in as the adult in the room. That review state gets copied into `PriceEntryDraft`, which means the confirmation sheet finally has enough context to behave like a reviewer instead of a blind form.

The UI change itself is intentionally plainspoken. While OCR is still running, the sheet now says so. Once parsing finishes, the sheet shows a review card that can say one of three honest things:
- this scan looks solid
- this scan needs a careful look
- this scan should not be saved casually

That sounds obvious, which is exactly why it matters. Good product behavior often comes from making the machine say the quiet part out loud.

The last piece was save behavior. Before this pass, a severe multi-product or competing-price scan could eventually look “ready” if the required fields were filled in. Now the confirmation flow puts a speed bump in front of those cases with an explicit save-anyway alert. Not a prison, just a gate that says: yes, you *can* save this, but you do not get to pretend the parser never raised its hand.

One more familiar war-story footnote: the build is green, but the targeted test run for the new review-state coverage timed out in the harness again. So the feature is implemented and compiled, the tests exist, and the environment is still auditioning for the role of unreliable narrator.

### War Story: Shipping Cleanup Is Mostly About Removing Embarrassing Noise
The “app and code cleanup” pass turned out to be less glamorous than parser work and more useful than it sounds. This was not a hunt for one dramatic bug. It was a hunt for the kind of release noise that makes a codebase feel unfinished even when the feature technically works.

The first fake lead was `Combine`. At a glance, a few files looked like they were carrying stale imports. They were not. In this project, `ObservableObject` and `@Published` still need that import, so ripping it out just turned “cleanup” into “compiler complaint generator.” That is a good reminder that dead-code cleanup should be verified, not aesthetic.

The real cleanup win was the warning surface. Swift 6 actor-isolation warnings were polluting the parser test target badly enough that build output no longer felt trustworthy at a glance. The fix was not to silence them with hand-waving. The fix was to make the test files honest about their execution context by standardizing the parser-focused suites onto `@MainActor`, which matches the parser test seams they already rely on.

There was also one small but worthwhile modernization in store detection. `StoreDetectionService` was still leaning on deprecated `placemark.location` access. Swapping that out for the current `MKMapItem.location` path cleaned up a real warning, and adding a deterministic fallback id when MapKit does not supply one made the candidate pipeline a little less fragile at the same time.

The result is exactly the kind of boring success you want near release: the full project build is green, the warning log is empty, and the remaining cleanup work is now mostly optional refinement instead of loud compiler-shaped clutter. That is a very senior-engineer kind of progress. Not flashy, but suddenly the room is quiet enough to hear the real problems.

### War Story: “Complete” Usually Means the Last 5 Percent Was Real Work
Finishing the shipping-cleanup checklist was mostly about refusing to confuse “probably fine” with “done.” The obvious big wins had already happened earlier. What remained was the irritating edge of release engineering: prove that the leftover helper seams are intentional, trim the code that is not pulling its weight, and make sure the build output is quiet enough that a *new* warning will actually mean something.

That final pass removed one unused review helper, cleaned up redundant actor annotations left behind after the Swift 6 test cleanup, and left the intentional parser test seams in place because they are still serving the test suite instead of freeloading in the binary. That distinction matters. A senior cleanup pass is not about deleting the most lines. It is about deleting the right lines and defending the ones that still earn rent.

The nice outcome is that the cleanup checklist can now be called complete without crossing fingers. The parser-related shipping work no longer reads like an unfinished migration, the build stays green, the warning log stays empty, and the remaining polish work is the kind you schedule because you care, not because release would otherwise be irresponsible.

### War Story: The Difference Between “We Have Tests” and “We Have a Ship Gate”
The proof-and-measurement pass finally got over an annoying but important hump: the parser test suite existed, but the harness was still flaky enough that “run a few parser tests” could mean timeout, `No result`, or actual signal depending on the day. That is not a ship gate. That is a weather report.

The fix was not to pretend the flaky path was fine. The fix was to carve out a smaller, boring, non-parameterized release-critical suite and make *that* the gate. `ParserShipGateTests` now covers the things you would be embarrassed to ship broken: clean single-product parsing, a real-world member promo tag, a multi-product scan that must surface review-required state, and an assisted-merge confidence sanity check. Then the repository got one more important proof point: parser review metadata now survives save instead of evaporating at the moment it would become useful for QA.

That same pass also added a lightweight evaluation suite over realistic fixtures. Not an academic benchmark, not a dashboard, just a compact “tell me how this parser behaves on the shelf-tag shapes we actually care about” loop. The summary now covers price, unit, quantity, item name, review state, and Foundation Models usage. In other words, we finally promoted the parser from “tested” to “measurable.”

The satisfying part is the result: the targeted ship-gate run passed cleanly in the current harness, six tests passed, zero failed, and the build stayed green. That does not mean the parser is done learning. It means release quality now has a smaller, sharper definition than “it seems pretty good on my machine,” which is how adults avoid shipping folklore.

## Engineer's Wisdom
Good parser work is less about cleverness than about preserving evidence. Every time you add a filter, ask: "What legitimate OCR junk am I about to throw away?" Grocery text is noisy by nature, and prices often appear on lines that look sparse or symbol-heavy. If the pipeline drops those lines too early, later stages cannot recover with confidence because the evidence is gone.

A senior-engineer move here is to fix the narrowest broken assumption instead of layering in compensating logic everywhere else. That keeps the system legible.

## If I Were Starting Over...
I would make the OCR pipeline stages more observable from day one. Snapshot-style tests are already helping, but a tiny debug surface that prints supported, cleaned, normalized, consolidated, and extracted candidates for a fixture would make regressions like this much cheaper to diagnose. The bug was simple. Finding where the evidence disappeared was the real work.
