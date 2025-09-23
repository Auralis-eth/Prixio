// Architecture Overview

/*
This document summarizes the project’s architectural approach, validation rules, and data model at a high level. It is intended to guide contributors and to inform automated assistants during future conversations.

Tech Stack and Approach

- UI: SwiftUI
- Persistence: SwiftData
- Concurrency: No actors. Prefer straightforward Swift Concurrency (async/await, Tasks) only where useful, but avoid actor-based isolation and actor-managed services.
- Dependency flow: Keep things simple and SwiftUI-friendly (Environment, Observable models, ViewModels as needed). Avoid complex service layers unless required.
- Deletions: Use soft-delete flags (e.g., `isDeleted`) and filter them out in queries.

Why no Actors?
- The app favors a pragmatic SwiftUI + SwiftData approach that remains simple and easy to reason about.
- Actor-based isolation can introduce unnecessary complexity and friction for UI code paths.
- Build settings should not enforce strict concurrency rules as errors (see Won’t Do).

Validation Rules (Guidelines)
Validation is enforced in view models, form logic, and/or lightweight helpers. The following rules reflect current intent and should be applied consistently:

- PriceEntry
  - Monetary amount must be greater than 0.
  - `captureDate` should not be in the future.
  - Respect soft deletion (entries with `isDeleted == true` are not considered in active logic).
  - Associations to the referenced entities (e.g., product, store) must be present when creating a new entry.
- Product
  - Name/title must be non-empty and trimmed.
- Store
  - Name must be non-empty and trimmed.

Notes:
- Prefer user-friendly validation with inline error messages in SwiftUI forms.
- Keep validation logic close to the UI and/or simple helpers; avoid central actor-based validators.

Data Model (High-Level)

The project uses SwiftData models. At a minimum, a `PriceEntry` model participates in queries. Typical fields include:

- `id: UUID`
- `captureDate: Date`
- `isDeleted: Bool` (soft-delete flag)
- Relationships: `product` and `store`
- A monetary amount field (Decimal) for the recorded price

Other related entities (e.g., `Product`, `Store`) are standard SwiftData models with basic identifying properties like name/title and relationships to `PriceEntry`.

Query Example

Queries should consistently exclude soft-deleted records and prefer clear sort orders. For example, fetching the latest price by product or store while ignoring soft-deleted entries:

```swift
let descriptor = FetchDescriptor<PriceEntry>(
    predicate: #Predicate { entry in
        entry.product?.id == someProductID && entry.isDeleted == false
    },
    sortBy: [SortDescriptor(\.captureDate, order: .reverse)],
    fetchLimit: 1
)
let latest = try context.fetch(descriptor).first
