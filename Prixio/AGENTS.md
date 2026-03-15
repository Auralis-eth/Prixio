# Prixio Project Memory

## Project Overview
Prixio is an iOS grocery price capture app. The main flow scans or imports a product photo, runs OCR, infers the item, price, unit, and store, then saves a normalized price record for later comparison.

## Architecture Decisions
- `PrixioApp` owns the SwiftData container for `PriceEntry`, `StoreChain`, and `StoreLocation`.
- `ContentView` is the app shell and the main scanner workflow entry point.
- `ScanDomain.swift` carries the domain logic: OCR parsing, price candidate extraction, unit detection, store inference, and persistence helpers.
- OCR parsing is heuristic-first. Vision provides raw text, then deterministic parsing picks likely prices and units before any future Foundation Models enrichment.

## Important Conventions
- SwiftUI-first structure with state-driven flows.
- Prefer async work over callback-heavy APIs.
- Use `Decimal` for price and quantity math.
- Keep scanner/parser changes tight in scope because `ScanDomain.swift` is already dense.

## Build And Run
- Open the project in Xcode and use the active `Prixio` scheme.
- Build with Xcode or the MCP `BuildProject` tool.
- Unit tests live in `PrixioTests` and use Apple’s `Testing` framework.
- UI smoke tests live in `PrixioUITests`.

## Quirks And Gotchas
- OCR output is noisy, and price fragments can be split across lines.
- Store detection mixes nearby search results with OCR-derived hints, so parser regressions can affect store autofill indirectly.
- `ScanDomain.swift` contains multiple responsibilities; make targeted edits and verify carefully.
