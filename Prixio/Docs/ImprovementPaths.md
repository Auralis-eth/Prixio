# Prixio Improvement Paths

## Purpose

This document is the next-step strategy guide for growing Prixio beyond the current MVP.

It focuses on:

1. product expansion outside the narrow “scan one price tag” loop
2. a high-level strategy to improve and expand price capture itself
3. a high-level strategy to research that improvement work properly

This is intentionally not a backlog of tiny UI tweaks. It is a direction-setting document.

## 1. Beyond The Current Price/Product Capture Flow

These are the bigger product directions worth considering after the current Scan + Compare + Shopping List loop.

### A. Pantry And Household Memory

What it is:

- a lightweight home inventory and restock system
- users track what they have, what is low, and what they buy repeatedly

Why it matters:

- it turns Prixio from “price archive” into “grocery operating system”
- Shopping List becomes smarter because it is fed by actual household consumption

Potential features:

- pantry item inventory
- “running low” reminders
- repeat purchase suggestions
- expiration tracking for perishables
- household consumption patterns

### B. Deal Discovery And Promo Intelligence

What it is:

- a flow for spotting and organizing meaningful deals, not just saving isolated prices

Why it matters:

- users often care about “is this actually a good deal?” more than “what did I scan last week?”
- this is where loyalty/member/regular pricing becomes a product feature instead of just parser metadata

Potential features:

- true-deal detection versus normal price noise
- sale watchlist for favorite items
- “new low” alerts
- promo card tracking
- household-specific “worth the trip?” recommendations

### C. Budget And Spend Planning

What it is:

- a budget-facing layer that estimates trip cost before the user shops

Why it matters:

- it moves Prixio closer to decision support
- users can ask not just “where is it cheapest?” but “can I keep this trip under budget?”

Potential features:

- estimated total for shopping list
- budget targets by trip or by month
- substitution prompts when an item spikes in price
- “best affordable trip” versus “absolute cheapest split trip”

### D. Household Collaboration

What it is:

- shared lists, shared scan results, and collaborative shopping plans

Why it matters:

- grocery shopping is often a multi-person workflow
- collaboration increases retention far more than isolated solo logging

Potential features:

- shared shopping lists
- assign items to people
- live checklist sync
- household-level price history

### E. Price History And Market Awareness

What it is:

- trend and price-memory surfaces that help users understand timing, not just current cheapest store

Why it matters:

- once enough entries exist, users will want timing insight:
  - buy now
  - wait for sale
  - switch stores

Potential features:

- per-item price history
- “usual range” versus “outlier” price views
- trend summaries by chain
- seasonal pricing notes

### F. Receipt And Basket Intelligence

What it is:

- use receipt capture as a second major ingestion path

Why it matters:

- shelf tags tell the market story
- receipts tell the real-purchase story
- combining both unlocks verification and spend analytics

Potential features:

- receipt scan import
- purchased price verification against shelf scans
- “you usually buy this for less” prompts
- chain-specific actual-spend reporting

### G. Store Knowledge Layer

What it is:

- a richer internal store graph instead of just chain/location snapshots

Why it matters:

- better store intelligence improves every flow:
  - Compare
  - Shopping List
  - route planning
  - scan prefill

Potential features:

- canonical store entities with stronger identity
- store reliability score
- branch-level versus chain-level behavior
- store-specific sale patterns

### H. Trust And Explainability Layer

What it is:

- product features that explain why the app is making a recommendation

Why it matters:

- trust is the real moat here
- grocery users do not want magic; they want defensible reasoning

Potential features:

- “why this store?” explanation cards
- freshness warnings with concrete age
- confidence explanation on suspicious parses
- recommendation transparency for split-trip suggestions

## 2. High-Level Strategy To Improve And Expand The Price Capture Flow

This is the product-and-engineering strategy for making capture materially better.

### Strategic Goal

Move from “single shelf-tag parser” toward “robust retail evidence pipeline.”

That means the app should eventually handle:

- single shelf tags
- side-by-side shelf tags
- produce cards
- promo boards
- price columns separated from product text
- receipts
- baskets of related evidence

### Phase 1: Harden The Current Single-Tag Experience

Focus:

- reduce false winners
- improve confidence honesty
- improve recovery from noisy but salvageable scans

Work:

- expand real-image fixture coverage
- improve store inference reliability
- tighten stale-data loops
- improve confirmation-sheet ergonomics for low-confidence results

### Phase 2: Add Richer Capture Inputs

Focus:

- the app should understand more than one kind of retail evidence

Work:

- receipt ingestion
- flyer/promo-card handling
- optional barcode-assisted identity support
- multi-image capture for one product

### Phase 3: Turn Capture Into A Structured Evidence System

Focus:

- preserve more context at capture time instead of flattening too early

Work:

- stronger bounding-box ownership
- evidence graphs instead of only line lists
- source-aware confidence:
  - OCR confidence
  - parser confidence
  - store confidence
  - freshness confidence

### Phase 4: Add User-Correctable Learning Loops

Focus:

- use user corrections as a product signal, not just a one-off edit

Work:

- capture what fields users corrected
- log repeated parser misses by scenario
- feed correction patterns into rule refinement and future model prompts

### Phase 5: Expand From Item Capture To Basket Capture

Focus:

- stop assuming one photo always equals one product

Work:

- multi-tag detection
- per-cluster product extraction
- user-assisted selection of the intended tag
- side-by-side product comparison directly from one photo

### Phase 6: Connect Capture To Planning

Focus:

- let capture directly feed Compare, Shopping List, budget, and future pantry systems

Work:

- stronger scan context prefill
- scan-to-list shortcuts
- “scan while shopping” batch mode
- explicit refresh missions for stale items

### Core Principle For Capture Expansion

Do not just add more heuristics forever.

The right direction is:

- richer evidence
- better ownership
- clearer confidence
- narrower use of expensive or unstable model-based assistance

## 3. High-Level Strategy To Research Improving And Expanding The Price Capture Flow

This is the research process, not the implementation backlog.

It should explicitly include:

- reading research papers
- reviewing OCR and document-understanding literature
- studying production systems in adjacent product categories
- building internal evidence corpora and evaluation loops
- validating ideas with narrow experiments instead of shipping speculation

### A. Start With Failure Taxonomy, Not Ideas

Before proposing fixes, classify failures.

Useful buckets:

- OCR saw the wrong text
- OCR saw useful text but parser assigned ownership badly
- parser chose the wrong candidate kind
- item name extraction failed
- store inference failed
- scene type was misclassified
- confirmation UX failed to recover a low-confidence result

Why:

- if you do not name the failure class, you cannot tell whether the next improvement is actually helping

### B. Read The Literature Before Inventing Local Myths

Prixio sits in the overlap of several fields:

- OCR
- document understanding
- scene text recognition
- layout analysis
- multimodal extraction
- human-in-the-loop correction systems

That means research should include deliberate literature review, not just local debugging.

Read across:

- academic papers
- benchmark papers
- survey papers
- engineering blog posts from production OCR/document systems
- Apple platform documentation where relevant to on-device vision and ML

Priority literature areas:

- scene text detection and recognition
- document layout analysis
- key information extraction
- multimodal grounding and region-text association
- confidence calibration
- human correction and active-learning loops
- receipt and invoice parsing systems

What to extract from papers:

- problem framing
- input assumptions
- what evidence is preserved
- what the model or heuristic is actually solving
- benchmark setup and limits
- failure modes
- whether the method is plausible on-device, server-side, or only as inspiration

Why this matters:

- otherwise the team risks rediscovering solved problems slowly and badly
- literature helps distinguish “hard because retail is messy” from “hard because our current architecture throws away useful evidence too early”

### C. Build A Deliberate Evidence Corpus

Research needs a better corpus than ad hoc screenshots.

Maintain separate sets for:

- clean shelf tags
- produce signs
- promo/member price tags
- dense beverage/deposit labels
- multi-tag frames
- bad lighting / glare / skew
- receipt captures
- edge-case OCR traps

For each sample, preserve:

- original image
- OCR output
- expected structured result
- failure notes
- whether the issue is OCR-side or parser-side

### D. Separate OCR Research From Parser Research

Do not conflate “Vision missed the text” with “our parser misread good OCR.”

Run separate tracks:

- OCR track
  - preprocessing
  - orientation
  - contrast variants
  - alternate OCR hypotheses
- parser track
  - ownership
  - candidate selection
  - scene classification
  - quantity/unit/item-name logic

Why:

- otherwise you will solve parser problems with OCR experiments or solve OCR problems with heuristic sprawl

### E. Study Adjacent Real-World Systems, Not Just Papers

Papers are necessary but not sufficient. Prixio also needs product and systems research.

Study adjacent tools like:

- receipt apps
- invoice/document extraction products
- pantry apps
- grocery list apps
- shopping and route optimization tools
- price tracking and deal apps

For each system, ask:

- what is the primary user promise?
- what input format do they optimize for?
- how do they ask for correction?
- how do they communicate uncertainty?
- how much structure do they preserve from the original capture?
- where do they use automation versus user confirmation?

The goal is not to copy UI. The goal is to understand:

- what users actually tolerate
- what workflows scale beyond demos
- where trust is won or lost

### F. Instrument Corrections In Production-Like Usage

Once the app is in real hands, the most valuable research signal is correction behavior.

Track things like:

- item name corrected after scan
- price corrected after scan
- unit changed after scan
- store corrected after scan
- scan discarded after review
- repeated scan-now nudge dismissals

This tells you where real friction lives instead of where the code merely looks interesting.

### G. Turn Reading Into A Structured Research Loop

Reading papers and references is only useful if the output feeds engineering decisions.

Recommended loop:

1. choose one failure class or opportunity area
2. collect internal examples
3. read the most relevant papers and system references for that area
4. summarize what those sources imply for Prixio
5. design one narrow experiment
6. measure against a fixed corpus
7. decide whether the idea should:
   - ship
   - be deferred
   - be discarded

Good outputs from a research read:

- “we should preserve alternate OCR hypotheses for compact numeric lines”
- “layout-aware ownership is more important than another regex tweak”
- “receipt capture should be a separate ingestion pipeline, not bolted into shelf-tag heuristics”

Bad outputs:

- “transformers seem good”
- “we should use AI more”

### H. Run Small, Focused Experiments

Avoid giant “parser rewrite” research efforts.

Good experiments are narrow:

- one preprocessing variant versus baseline
- one ownership heuristic versus baseline
- one prompt refinement on a frozen ambiguity set
- one correction-flow UX change on low-confidence scans

Each experiment should have:

- a clear hypothesis
- a fixed corpus
- a success metric
- a rollback path

### I. Define Success Metrics Up Front

Research should have measurable outputs.

Useful metrics:

- valid price extraction rate
- correct item identity rate
- review-required rate
- false-confidence rate
- user correction rate per field
- scan-to-save completion rate
- time-to-save for low-confidence scans

### J. Treat Foundation Models As A Scoped Research Tool

Do not let the research plan quietly become “use a model for everything.”

Use FM research where it is strongest:

- ambiguity arbitration
- structured repair of low-confidence outputs
- canonical item-name cleanup

Avoid depending on it for:

- the default happy path
- correctness that should come from ownership and evidence
- broad replacement of deterministic parser logic

### K. Feed Research Back Into Product Decisions

Some research outcomes should change the roadmap, not just the parser.

Examples:

- if stale-price nudges are often accepted, invest more in freshness loops
- if store correction is common, store intelligence needs work
- if receipt ingestion proves easier than shelf tags for many users, make it a first-class flow
- if users mostly want budget help, invest earlier in trip-total features

## Recommended Next Strategic Questions

If choosing what to do next, these are the highest-value questions:

1. Which capture failure class is producing the most real user correction work?
2. Is the next major ingestion path receipt capture, flyer/promo capture, or basket/multi-tag capture?
3. What product surface creates the most user trust: better compare detail, better shopping guidance, or better correction transparency?
4. What research corpus is currently missing that makes us overconfident in the parser?

## Starter Reading List

This is a practical on-ramp, not a complete literature review.

The point is to give future work a better starting set of references across:

- classic OCR foundations
- scene-text and layout understanding
- document AI and key information extraction
- multimodal extraction
- practical production engineering

Use it to orient the team before deeper targeted research on a specific failure class.

### 1. Classic OCR And Text Recognition Foundations

These are useful for understanding the historical shape of OCR systems and why preprocessing, segmentation, and recognition assumptions matter so much.

- Tesseract OCR papers and technical writeups
  - useful for segmentation assumptions, OCR pipelines, and practical recognition constraints
- CRNN: Convolutional Recurrent Neural Network for Image-Based Sequence Recognition
  - important for understanding sequence-style text recognition
- CTC-based OCR literature
  - useful for seeing how recognition systems handle alignment without explicit character segmentation

What to extract:

- what preprocessing the recognizer expects
- how much the pipeline depends on segmentation quality
- what failure modes appear before downstream parsing even starts

### 2. Scene Text Detection And Recognition

This category matters because grocery price capture is not a clean scanned document problem. It is a scene-text problem living in messy retail photos.

- EAST: Efficient and Accurate Scene Text Detector
- CRAFT: Character Region Awareness for Text Detection
- DB / Differentiable Binarization papers for text detection
- EasyOCR reference implementations and docs
- PaddleOCR papers and documentation

What to extract:

- how detectors separate adjacent text regions
- how detection quality influences ownership and grouping
- when alternate OCR hypotheses are worth preserving

### 3. Document Layout And Document AI

These papers matter because shelf tags, produce cards, promo boards, and receipts all have layout structure, not just text.

- LayoutLM
- LayoutLMv2
- LayoutLMv3
- Donut: OCR-free Document Understanding Transformer
- DocFormer

What to extract:

- how text and geometry get fused
- how layout context changes extraction quality
- what can be borrowed conceptually even if the exact model is too heavy or server-oriented for Prixio

### 4. Key Information Extraction And Document Parsing

This is the closest academic neighborhood to “turn messy text blocks into structured fields.”

- papers on key information extraction (KIE)
- receipt and invoice understanding benchmarks and competition papers
- form understanding papers

Useful benchmark families to inspect:

- FUNSD
- SROIE
- CORD

What to extract:

- field-extraction framing
- how entity relationships are modeled
- how systems distinguish nearby but semantically different numeric values

### 5. Multimodal And Region-Grounded Extraction

Prixio increasingly lives in the space where text alone is not enough. Region ownership matters.

- multimodal grounding papers
- visually grounded extraction papers
- region-text alignment papers
- papers on table/region linking and spatial relation modeling

What to extract:

- how systems link the right price to the right product block
- how spatial relationships are represented
- what ideas can inform better evidence-cluster ownership in Prixio

### 6. Confidence, Calibration, And Human-In-The-Loop Systems

Prixio is not just an extractor. It is a reviewable extraction system. That makes confidence and correction workflows first-class research topics.

- confidence calibration papers
- selective prediction / abstention literature
- human-in-the-loop document extraction papers
- active-learning and correction-loop papers

What to extract:

- when the system should defer to the user
- how confidence can be communicated honestly
- how user corrections can become training or rule-improvement signals

### 7. Receipt, Invoice, And Retail-Specific Practical References

This is where papers should be combined with production engineering references.

Read:

- receipt-scanning product engineering blog posts
- invoice extraction system writeups
- retail OCR and POS/receipt digitization case studies
- practical OCR benchmarking writeups from engineering teams

What to extract:

- real-world failure classes
- production tradeoffs
- UX patterns for correction
- what successful systems deliberately do not automate

### 8. Apple Platform And On-Device References

Prixio is an iOS app, so platform constraints matter.

Read:

- Apple Vision framework documentation
- Apple image-processing and Core Image references relevant to preprocessing
- Apple on-device ML deployment guidance where applicable
- Foundation Models documentation if and when expansion of the assist path is being considered

What to extract:

- what is realistic on-device
- what image preprocessing is cheap enough to run regularly
- what latency or memory limits should shape architecture decisions

### 9. Practical Engineering References And System Docs

Not all useful reading is academic.

Prioritize:

- PaddleOCR docs and implementation notes
- EasyOCR docs and code references
- Tesseract docs and architecture notes
- OCR benchmark repos with real examples
- engineering blog posts on document AI production systems

Why:

- these sources usually expose the ugly operational details that papers skip
- they are often better for understanding evaluation harnesses, preprocessing knobs, and deployment tradeoffs

### 10. How To Use This Reading List

Do not read it front to back like a course syllabus.

Use it like this:

1. pick one concrete Prixio failure class
2. choose the most relevant category above
3. read 2-4 strong references
4. summarize what those references imply for Prixio
5. design one narrow experiment
6. measure on a fixed corpus

Example mappings:

- price belongs to wrong product block
  - read scene text detection, layout, and multimodal grounding
- OCR misses compact shelf-tag price tokens
  - read classic OCR, scene text recognition, and preprocessing references
- low-confidence scans take too much user cleanup
  - read confidence calibration and human-in-the-loop extraction work
- receipt ingestion is being considered
  - read KIE, receipt benchmarks, and production receipt-system references
