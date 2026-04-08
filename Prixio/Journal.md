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

### War Story: The Shelf Tag Was Split in Two, So the Parser Fell for the Candy Bag
One real scan of a Cadbury shelf tag exposed a geometry bug that text-only fixtures were politely hiding. OCR picked up three different neighborhoods at once:
- product-packaging text on the candy bags
- the shelf-tag description on the left side of the label
- the real shelf price in a separate right-hand price block

The parser’s spatial grouping logic was too column-minded. It happily grouped the bag text together, grouped the shelf-tag description separately, and grouped the price block separately. Then it crowned the “strongest” cluster, which turned out to be the product bag whispering `Cadbury`, `Mini Eggs`, and an unrelated `8.75`-looking fragment. That is how you end up with a result that feels believable enough to be dangerous: partial item name, wrong price, confident posture.

The fix was precise:
- let spatial grouping bridge left-description and right-price blocks when they align like one shelf-tag row
- keep that merged shelf-tag cluster together long enough for scoring to see the actual `17.99` winner
- when assisted extraction has multiple descriptive lines but no canonical name, merge those line fragments instead of grabbing the first digit-free line and pretending the name is complete

The lesson is one worth keeping on a sticky note: geometry bugs often dress up like ranking bugs. If the parser is choosing the wrong evidence neighborhood, no amount of downstream confidence math will rescue it.

### War Story: The OCR Saw `1799`, the Parser Threw It Away, and `875 g` Stole the Job
The next round of debugging finally caught the parser in the act with real console output instead of polite guesses. Vision did not completely miss the shelf price. It saw `1799`. The parser was the one being reckless.

The failure chain was painfully educational:
- the focused shelf-tag group already contained the right product lines
- raw OCR included `1799`
- noise cleanup dropped that numeric-only line before candidate extraction
- implied-price extraction then looked at `875 g` and cheerfully promoted it to `$8.75`
- item-name cleanup kept dragging promo/seasonal crumbs like `THIS WEEK` and `Easter` into the final name

That is the kind of bug that makes every downstream stage look suspicious even though the real crime happened near the front door.

The fix was a bundle of small, specific rules:
- preserve `3` to `4` digit numeric lines like `1799` when they live in a price-dense shelf-tag context
- reject implied-price candidates when the digits are clearly part of package-size text like `875 g`
- keep direct price normalization honest so `$5.00 ea` stays `$5.00 ea` instead of losing its cents
- strip promo and seasonal leftovers from assembled item-name fragments
- penalize price lines sitting next to a standalone `SAVE` marker so a savings amount does not outrank the actual shelf price

The senior-engineering lesson here is simple: real parser bugs are often a relay race. If one stage deletes the real evidence and the next stage promotes a fake one, you do not need one “smart” fix. You need to stop both runners.

### War Story: The Produce Card Was Giving Nutrition Advice, and the Parser Tried to Save It as the Product Name
The next real-image fixture was almost comically clean. `IMG_0473` showed a produce bin with a tidy card for `MINI CUCUMBER` and a clear `$4.00` price. OCR read it perfectly. Then the parser did something only a parser would do: it glued the helpful marketing copy onto the item name and returned something like `MINI CUCUMBER Perfect for snacking High water content helps to keep you hydrated`.

This was not an OCR problem and not a price problem. It was an item-name-boundary problem. The resolver was acting like any nearby non-price text might be a continuation of the title, which is fine for split shelf-tag names and terrible for produce cards that include little lifestyle blurbs underneath the product name.

The fix was to teach the resolver a new kind of suspicion: descriptive card copy is not a title fragment. Sentence-like lines with stopwords and lowercased explanatory phrasing now get filtered out before they can merge into the winning item name. In practical terms, `MINI CUCUMBER` survives, while `Perfect for snacking` and `High water content helps to keep you hydrated` stay where they belong: useful context, not identity.

This was also the moment the image-fixture harness grew up a little. The loader now looks in `PrixioTests/Images`, there is a real Vision-backed fixture test for `IMG_0473`, and the OCR observations are frozen into captured-fixture tests so the next bug can be diagnosed without rerunning Vision every time. That is a good engineering trade: use the real image to prove the pipeline works, then use frozen OCR to make iteration cheap.

### War Story: Keeping `12 PK` Without Marrying `Pepsi`
One regression round managed to break two opposite things at once, which is how parser work likes to keep you humble. The item-name cleanup started stripping trailing size and pack markers too aggressively, so solid names like `Dr Pepper Zero 12 PK`, `Sparkling Water 12 PK`, and `Coca Cola Zero Sugar 2 L` came back on a crash diet. Then the first attempt to fix that swung too far in the other direction and started over-merging nearby text, producing gems like `Coke Zero Pepsi` and `Cadbury Chocolate Mini Eggs Qadouro Mind`.

The real lesson was that “keep size tokens” and “merge nearby fragments” are not the same rule.

The fix ended up being a two-part truce:
- preserve trailing size and pack markers only on the primary winning product line
- only merge a secondary fragment when it earns it by sharing token overlap or carrying an explicit size/pack signal

That restored the useful names without reopening the junk-text floodgates. The side quest was assisted extraction: the Foundation Models merge path was being too deferential to heuristic scoring, so valid model-selected candidates for the correct product cluster could still lose to the old winner. That got corrected by letting target-line alignment beat raw priority when the selected candidate clearly belongs to a different product block.

Meanwhile, one live Vision fixture taught the usual uncomfortable truth: OCR itself is not stable enough to pin exact raw strings forever. The deterministic parser expectations now live in captured OCR tests, while the live-image tests only prove the pipeline still produces a reviewable parse instead of pretending Apple’s OCR engine signed a blood oath.

### War Story: “We Have a Folder Full of Images” Is Not the Same as “We Test the Folder”
At one point the project had eleven numbered fixture images sitting in `PrixioTests/Images` plus the Cadbury screenshot, but only two of them were actually exercised by live Vision-backed tests. That is the testing equivalent of owning a fire extinguisher collection and only checking one of them has pressure.

The fix was not to turn every image into a brittle exact-output contract. That would have been expensive and flaky. Instead, the suite now has two layers:
- strict curated image tests for the high-signal fixtures we already understand well
- full-set sanity coverage that loads, OCRs, and parses every fixture image and requires non-empty OCR plus a structurally reviewable parse

That split is the useful pattern to keep. Exact assertions belong on a few deliberate fixtures. Broad “does the pipeline still work on the whole shelf?” coverage belongs on the whole image set. Together they catch both regression classes: precise parser drift and boring end-to-end breakage.

### War Story: The Camera Was Fine. The State Machine Was Lying.
Device QA found a very product-shaped bug: after a capture, `Retake` could leave the app staring at the old photo instead of returning to the live camera. Repeated captures in one session had the same smell. That kind of issue is easy to misdiagnose as an AVCapture problem, but the actual bug lived higher up the stack.

The scan flow was using “do I still have a `UIImage` around?” as a stand-in for presentation state. That is convenient right up until a sheet dismisses, a reset path misses one image reference, or a reused state object keeps the last capture alive just long enough to look broken. Then the UI feels haunted even though the camera session itself is still healthy.

The fix was to stop letting stale image references drive the whole screen:
- only show the captured/imported image while review is actually active
- treat confirmation-sheet dismissal as a real reset path that clears transient scan state
- force the preview view to refresh after retake/discard/save so repeated capture sessions rebind cleanly
- add direct `ScanViewModel` tests for those reset paths instead of relying only on taps and vibes

That same pass added a practical QA helper: a button in the confirmation sheet can now save the current scan photo to Photos using add-only photo-library access. That gives device QA a cheap way to preserve bad scans for later parser work instead of trying to recreate them from memory.

### War Story: “Reviewable Parse” Was a Comfort Blanket, Not a Contract
The image-fixture suite finally hit the point where its old shape stopped being honest. The tests could prove that every real image still loaded, OCR still returned something, and the parser still emitted a vaguely reviewable result. That sounds useful until you realize it would happily pass while the parser quietly changed `MINI CUCUMBER` into marketing copy soup, promoted a PLU into a banana price, or decided the toothpaste aisle cost `100` per imaginary unit of chaos.

So the fixture strategy got sharper. The live-image suite now behaves like a customs checkpoint instead of a wave-through line:
- every real fixture has a contract case
- every contract asserts the meaningful fields: item, price, unit, quantity, review state, and whether Foundation Models stepped in
- exact OCR lines, candidate lists, and supporting lines only get pinned where they have proved stable enough to deserve it

That last point matters. Vision OCR is not a rock. It is more like a very fast intern who usually does the right thing and occasionally decides `Butterleaf` is `BKUXBUKN`. Freezing every raw line for every image would turn the suite into a weather vane. Freezing the stable, high-signal outputs makes it a guardrail.

The second half of the cleanup was about moving real-image failures into cheaper, more exact parser tests. Instead of making every bug hunt depend on rerunning Vision, the suite now also carries captured-OCR fixtures for the cases that actually teach us something:
- the Cadbury shelf tag where `1799` and `$5.00 ea` fight for attention
- the clean mini cucumber card that proves title-vs-description boundaries
- the banana tag where `PLU 4011` currently wins a price election it should absolutely lose
- the sparse grower label where `19.08` looms in the background but `2.99` still wins

That is the deeper lesson worth keeping: broad image coverage and exact parser contracts are different tools. Live image tests answer “does the full pipeline still behave on real photos?” Captured OCR tests answer “did this specific parser behavior just drift?” When those two layers are separated cleanly, regressions stop hiding inside comforting words like “reviewable.”

### War Story: The Butter Tag Was Right There, but the Parser Picked the Bigger Wrong Neighborhood
One of the new strict image contracts immediately paid rent. The butter shelf photo (`IMG_0483`) contains two plausible tag clusters:
- a larger unsalted cluster with clean descriptive text, `/100G`, promo points, and a mangled price OCR fragment
- a smaller salted cluster with a boring but perfectly recoverable `599` shelf price

Before the fix, the parser behaved like a rookie detective who trusts the biggest witness instead of the witness with the usable evidence. Spatial grouping crowned the unsalted cluster because it had more lines and looked richer in text. Then candidate extraction found no valid shelf price in that winning group, and the parser still stayed loyal to it. Result: `Comp Butter Unsalted`, no price, and a review-required shrug while the real `$5.99` salted tag sat a few inches away waving both arms.

The fix stayed in the focused-group scoring, which is exactly where it belonged. Candidate groups now get rewarded for producing actual recoverable price candidates after cleanup and normalization, and text-heavy groups get penalized when they still cannot surface a usable price. In other words, a shelf-tag group no longer wins just by talking a lot. It has to bring receipts.

That changed the butter fixture the way you would want:
- focused observations collapse to `Comp Butter Salted`, `454 g`, `599`
- the parser returns `$5.99`
- the result stays on the heuristic path with a clean review state instead of escalating out of confusion

This one is worth remembering because it is a classic parser trap. Bigger context is not always better context. If a candidate cluster cannot cash out into a believable price, the parser should stop being impressed by its vocabulary and look for the group that can actually finish the job.

### War Story: When the Model Was Right but the Test Wanted the Exact Breadcrumb Trail
One captured-OCR test for the Stage 4 banana tag started acting like a slot machine. The parse itself was stable enough: same wrong winner, same `40.11`, same `.kg`, same review-required outcome. But the `supportingLines` assertion kept flipping because the live Foundation Models step would sometimes point at one valid subset of the shelf text and sometimes another.

That bug was not in the parser output the product actually cares about. It was in the test pretending the model would always leave the exact same footprints.

So the fix was to tighten the contract around the deterministic parts instead of worshipping a flaky detail:
- the test still pins the final item name, price, unit, quantity, and review state
- it now requires that `supportingLines` includes `Bananas Stage 4 PLU 4011`
- it also requires every returned supporting line to come from the consolidated OCR snapshot

That is the useful lesson: when a test crosses into model-guided behavior, assert the invariant, not the exact breadcrumb arrangement. Otherwise the suite turns into a lie detector for randomness.

### Aha: The Next Parser Leap Is Not "More OCR," It Is Better Traffic Control
After enough fixture work, a pattern finally became impossible to ignore: most of the remaining parser misses do not come from having zero OCR. They come from having OCR that is locally plausible but globally untrustworthy. A compact `299` might be a price. It might also be a fragment. `PLU 4011` might look price-shaped if the parser squints hard enough and makes bad life choices. A promo card can have excellent text recognition and still be the wrong scene for normal shelf-tag logic.

That is what pushed the project toward a new plan captured in `OCRParsingPipelineRefactorPlan.md`. The design direction is heavily informed by what mature OCR systems do well:
- EasyOCR is a good reminder to keep structured detections alive instead of flattening too early
- Tesseract is a good reminder that segmentation assumptions are part of correctness, not preprocessing trivia
- PaddleOCR is a good reminder that detection, orientation, recognition, and downstream understanding should stay modular

The key Prixio-specific takeaway is that the next meaningful upgrade is architectural:
- classify the scene before ranking prices
- promote product/evidence clusters to first-class parser data
- make prices earn ownership inside a product block
- separate OCR confidence from parser confidence
- keep Foundation Models as a scoped tie-breaker instead of a janitor for weak deterministic context

In coffee-shop terms: the current parser is like a smart cashier reading whatever lands nearest the scanner. The next version needs to behave more like a floor manager who first decides which shelf tag we are even talking about, then asks whether the price sticker actually belongs to that tag, and only then writes down the number.

### Aha, Part 2: Better OCR Starts Before OCR
One subtle trap in parser work is blaming every bad result on parsing. Sometimes the parser is guilty. Sometimes it is just being handed a crooked, glare-heavy, low-contrast mess and asked to do algebra with fog.

That is why the OCR refactor plan now starts with image preprocessing instead of parser surgery. The new direction in `OCRParsingPipelineRefactorPlan.md` treats `OCRService.swift` as a real seam, not a thin utility wrapper. The service is now the natural home for experiments like:
- orientation normalization
- perspective rectification for shelf tags
- high-contrast and grayscale OCR variants
- bounded fallback passes when the first Vision result is obviously weak

This is the practical lesson from older OCR stacks that still applies on iOS: the best regex in the world cannot recover text that the recognizer never saw clearly. If the image hits Vision already straightened and easier to read, every downstream parser stage gets to be less desperate and more honest.

### War Story: The First OCR Refactor Needed a Leash
Phase 1 of the OCR plan finally landed, and the main engineering challenge was not "how do we preprocess images?" It was "how do we avoid building a tiny research lab inside `OCRService.swift`?"

The old setup was intentionally simple: `UIImage.extractOCR()` built one Vision request, took the top candidate for each observation, and handed the lines to the parser. That was fine for the first version, but it gave the app no disciplined place to try orientation cleanup, no room for controlled fallback behavior, and no shared seam for fixture tests to exercise the same OCR path as production.

The new shape is more adult without being dramatically more ambitious:
- `UIImage.extractOCR()` still exists, so the rest of the app did not need surgery
- a real `OCRService` now owns preprocessing, Vision execution, and parser hand-off
- the primary OCR pass uses a normalized image
- one fallback pass can try a high-contrast variant when the first pass looks weak
- the pass budget is hard-capped at two total OCR attempts
- debug logging reports which variant won, whether fallback ran, and how many observations came back

That last rule matters more than it sounds. OCR experimentation has a natural tendency to metastasize: "just add grayscale," then "just add another contrast curve," then "maybe one more retry if the tag is yellow." Pretty soon the app is running a small roulette wheel before it even starts parsing. The hard cap keeps Phase 1 honest.

Another good cleanup happened in the tests. The fixture helper no longer carries its own shadow OCR pipeline. It now calls into `OCRService`, which means fixture coverage and production behavior share the same seam. That is the sort of boring alignment work that saves a lot of future confusion.

### War Story: Phase 2 Was Mostly About Telling the Truth
Phase 2 sounded modest on paper: baseline and instrumentation. In reality it was a cleanup pass on the stories the test suite was telling about the system.

The biggest lie was in the live image fixture tests. They were still behaving like a notarized record of Vision OCR output, down to exact line arrays and exact `supportingLines` slices. That worked right up until OCR preprocessing improved, a line got recognized slightly differently, or the model-assisted path chose a different but still valid evidence breadcrumb trail. At that point the tests were no longer protecting correctness. They were protecting yesterday's weather.

So the contract got corrected:
- captured OCR tests still pin exact deterministic parser-stage behavior
- live image tests now assert stable invariants instead of full OCR snapshots
- `supportingLines` is explicitly documented as exact only for deterministic inputs, not as a promise that live OCR or model-assisted paths will always leave the same footprints

The debug story got better too. Parser debug output now reports heuristic confidence and whether the ambiguity layer thinks Foundation Models should even be involved. That sounds small, but it makes a big difference when you are trying to answer the real engineering question: "Did the parser fail because it was weak, because the scene was ambiguous, or because we escalated when we should not have?"

This was one of those phases that feels less glamorous than shipping a new heuristic, but it raises the technical bar. A parser team that cannot distinguish deterministic contracts from live-system invariants eventually starts fighting randomness and calling it quality work.

### War Story: The Parser Finally Learned to Name the Kind of Mess It Was Looking At
Phase 3 added something the pipeline had been faking for a while: scene classification. Before this pass, the parser could act suspicious about a scan, but it could not cleanly say what kind of suspicious scene it thought it was looking at. Everything got funneled through field completeness, competing prices, and a few special-case checks. That works until you realize a promo card, a multi-tag shelf photo, and a receipt-like fragment are all different flavors of trouble.

The new snapshot now carries a `sceneClassification` value:
- `singleTag`
- `multiTag`
- `promoCard`
- `receiptLike`
- `unclear`

The important design choice was restraint. `unclear` is the default unless the evidence really earns something more specific. That keeps the classifier from becoming a tiny overconfident oracle that mislabels noisy scans just because it wants to be helpful.

This also cleaned up the ambiguity path. Instead of always trying to rediscover "is this maybe multi-product?" from scratch, the confidence resolver can now use the scene classification as an explicit signal. That makes the code easier to reason about and gives tests a much sharper contract: not just "did we escalate?" but "what scene did we think this was?"

In restaurant terms, the parser used to say, "something seems wrong with this ticket." Now it can say, "this is not a normal table order, this is a catering sheet," which is a much better starting point for deciding what to do next.

### War Story: Spatial Groups Were Not Enough, We Needed Product Blocks With Paperwork
Phase 4 turned spatial groups into something more accountable. Before this pass, the parser already knew how to group nearby observations, but those groups were still just piles of lines with a score. Useful, but not enough. A pile of lines cannot tell you, "I am probably the primary product tag," or "I am promo noise trying to look important."

So the snapshot now carries first-class `evidenceClusters`. Each cluster has:
- its local observations
- normalized lines
- local price candidates
- local item hint
- local unit and quantity signals
- a role hint
- a cluster score

The role hints are intentionally blunt:
- `primaryProduct`
- `secondaryProduct`
- `promoCopy`
- `noise`

That bluntness is a feature, not a bug. The first version of a clustering layer should behave like a decent warehouse label maker, not like a poet. It needs to separate the useful carton from the cardboard filler before it tries to sound clever.

The other important addition is a `winningClusterIndex`. That gives the parser a concrete answer to a question it had previously been answering indirectly: "Which product block do we think we are actually parsing?" Right now the existing focus and candidate ranking flow still does most of the heavy lifting, which is fine. Phase 4 was about making the data model explicit first, not ripping out working heuristics just to feel architectural.

This is a good example of the right refactor order. First make the concepts real. Then let later phases use those concepts more aggressively. If you reverse that order, you usually end up with a lot of "smart" branching code built on unnamed ideas.

### War Story: The Item Name Finally Stopped Looking Over Its Shoulder
Phase 5 was the moment the final item name got told to stay in its lane.

Before this pass, the parser had evidence clusters, but the snapshot could still compute the final `itemNameHint` from the broader focused observation set. That meant the data model knew which product block had won, but the final name could still be assembled with one eye drifting toward neighboring product text or promo copy. Architecturally, that is the worst kind of half-finished refactor: the right concept exists, but the public result still answers to the old boss.

The fix was simple and appropriately boring:
- if a winning cluster exists and it has a local item name, use that as the final item hint
- only fall back to the broader resolver when the winning cluster cannot produce a name at all

That changes the behavior in the direction you would want:
- neighboring products stop getting a vote on the winner's name
- promo copy can still exist nearby without becoming identity
- the broader merge logic remains available as a safety net instead of the default source of truth

This is one of those changes that feels small in code and large in meaning. Once you introduce first-class product blocks, the final item name should come from the winning block by default. Otherwise the parser is basically announcing, "I know which tag won, but I am still going to ask the aisle for opinions."

### War Story: Confidence Finally Had to Explain Itself
Phase 6 was about a quiet but important lie in the old parser: there was one final confidence number, but it was blending together two very different questions.

1. Did OCR recover decent evidence?
2. Did the parser assemble a believable product-price result from that evidence?

Those are not the same problem. A scan can have pretty healthy OCR and still be structurally ambiguous because two products are fighting in frame. It can also have a simple parse shape with weak OCR evidence that should still make everyone nervous. The old confidence path blurred those into one bucket, which meant `lowConfidence` sometimes described the wrong failure mode.

The new pass splits the logic into:
- OCR evidence confidence
- parse structure confidence
- a weighted combined confidence used for the final score

That does two useful things:
- weak sparse scans can now earn a real `lowConfidence` signal for the right reason
- promo-card or unusual-but-readable scenes do not automatically get treated like OCR disasters just because the layout is a little weird

This is one of those refactors that makes future debugging much saner. When a result looks risky now, the parser is closer to saying whether the problem was "the eyes were blurry" or "the reasoning was shaky." Those are different bugs, and good systems stop pretending they are the same.

### War Story: Foundation Models Stopped Getting Summoned for Work the Heuristic Path Had Already Finished
Phase 7 finally put some manners around the Foundation Models hand-off.

Before this pass, the FM path knew a lot less than it should have, and the deterministic parser sometimes asked for help in situations where it had already done the job. That is a bad deal in both directions:
- the prompt is noisier than it needs to be
- the model gets invited into cases where it adds latency and variability without adding value

The fix had two parts.

First, the prompt got better context:
- scene classification
- evidence clusters
- winning cluster index

That means the model is now looking at something closer to "here are the candidate product blocks and the likely winner" instead of a generic bag of OCR lines plus price candidates. It narrows the search space in a way that is legible to both the code and the tests.

Second, the parser got a proper skip guard. If the heuristic path already has:
- a strong single-tag scene
- a winning primary product cluster
- a complete enough result
- no severe ambiguity
- high heuristic confidence

then the FM path is skipped. That is exactly how this should behave. A model should be a tie-breaker or escalation tool, not a ceremonial consultant who gets called into meetings after the decision is already obvious.

This is another good example of raising the bar by reducing unnecessary cleverness. The best model call is often the one you did not need to make.

### War Story: We Added an OCR Enrichment Seam Without Forcing the Parser to Marry It
Phase 8 was intentionally cautious. The goal was not to suddenly make the parser depend on alternate OCR hypotheses everywhere. That would have been a big behavior change disguised as "just adding more evidence."

Instead, the system got a new seam:
- `OCRTextObservation` can now preserve alternate candidate strings
- `OCRService` captures a bounded second Vision candidate for price-like observations
- the normalization and consolidation path preserves those alternates instead of discarding them immediately

That is exactly the right amount of ambition for this phase. The parser still reasons from the primary recognized string. The new alternate hypotheses are there as structured evidence for future experiments, tests, and debugging, not as a surprise new source of truth.

This is the engineering equivalent of running conduit before you need the wiring. You do the boring structural prep now so that a later experiment does not require opening every wall in the house.

## Engineer's Wisdom
Good parser work is less about cleverness than about preserving evidence. Every time you add a filter, ask: "What legitimate OCR junk am I about to throw away?" Grocery text is noisy by nature, and prices often appear on lines that look sparse or symbol-heavy. If the pipeline drops those lines too early, later stages cannot recover with confidence because the evidence is gone.

A senior-engineer move here is to fix the narrowest broken assumption instead of layering in compensating logic everywhere else. That keeps the system legible.

## If I Were Starting Over...
I would make the OCR pipeline stages more observable from day one. Snapshot-style tests are already helping, but a tiny debug surface that prints supported, cleaned, normalized, consolidated, and extracted candidates for a fixture would make regressions like this much cheaper to diagnose. The bug was simple. Finding where the evidence disappeared was the real work.
