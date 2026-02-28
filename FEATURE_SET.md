# Prixio Feature Set and Rebuild Specification

## Purpose

This document describes the current project in implementation terms, not aspirational terms. It is intended to let someone rebuild the app from scratch by reproducing:

- the app structure
- the navigation model
- the data model
- the service architecture
- the implemented feature behavior
- the placeholder and incomplete areas
- the deprecated or duplicate code paths that still exist in the repository

Where behavior is not fully implemented, that is called out explicitly.

## Product Summary

Prixio is a SwiftUI + SwiftData iOS app for recording grocery or retail prices, detecting nearby stores, and preparing for future AI-assisted receipt/product scanning and sync features.

Current implemented product areas:

- app startup lifecycle with service registration and health checks
- tab-based app shell
- recent prices screen scaffold
- receipt scan screen scaffold
- store list screen scaffold
- nearby store detection flow
- location privacy/settings flow
- model layer for prices, products, stores, users, and images
- OCR/barcode analysis service
- Google Places autocomplete/details/nearby search service
- local logging and error types

Current non-final or partial areas:

- price CRUD UI is mostly not built
- camera capture flow is placeholder-only
- CloudKit sync manager is deprecated and mostly no-op
- DatabaseManager is deprecated and no-op
- tests are template-level only
- Google Places secret injection is not configured

## Tech Stack

- Language: Swift
- UI: SwiftUI
- Persistence: SwiftData
- Concurrency: async/await and actors are both used, despite `ARCHITECTURE.md` saying actors should be avoided
- Apple frameworks: CoreLocation, MapKit, UserNotifications, Vision, VisionKit, OSLog, CloudKit
- Third-party SDK: GooglePlaces

## Source of Truth

Primary architectural files:

- `Prixio/Prixio/PrixioApp.swift`
- `Prixio/Prixio/ARCHITECTURE.md`
- `Prixio/Prixio/Prixio-AI/Core/Coordinators/AppCoordinator.swift`
- `Prixio/Prixio/Prixio-AI/Core/Services/ServiceRegistry.swift`

## App Entry and Lifecycle

### App Bootstrap

`PrixioApp` is the app entry point.

On launch it:

- creates a single `@StateObject` `AppCoordinator`
- injects `AppCoordinator` into the environment
- creates a SwiftData model container for:
  - `PriceEntry`
  - `Product`
  - `Store`
- runs `appCoordinator.initializeApp()` in a `.task`

### Scene Phase Handling

The app listens for scene phase changes:

- `.background` -> `appDidEnterBackground()`
- `.active` -> `appWillEnterForeground()`
- `.inactive` -> no-op

### App State Machine

`ContentView` renders according to `AppCoordinator.appState`:

- `initializing` -> `LoadingView`
- `ready` -> `MainTabView`
- `failed(Error)` -> `ErrorView`
- `terminated` -> plain text `"App Terminated"`

The root view animates state transitions with `.easeInOut`.

## Navigation Structure

### Root Tabs

`MainTabView` contains a `TabView` with four tabs:

1. `PriceListView`
2. `CameraView`
3. `StoresView`
4. `SettingsRootView`

### Global Overlay

`MainTabView` overlays `LocationUsageIndicator` in the top-right corner.

It becomes visible when the `LocationService` snapshot reports `isActivelyUpdating == true`.

## Screen-by-Screen Feature Inventory

### Loading Screen

`LoadingView` contains:

- `ProgressView`
- static text `"Loading Prixio..."`

### Error Screen

`ErrorView` contains:

- warning triangle icon
- title `"Something went wrong"`
- `error.localizedDescription`
- `Retry` button

Current limitation:

- `Retry` button has no implementation

### Price List Screen

`PriceListView` currently provides:

- navigation title `"Recent Prices"`
- a placeholder row: `"Price entries will appear here"`
- a `Settings` navigation link into `SettingsRootView`

Current limitation:

- no actual `@Query` or fetched price list is implemented
- no create/edit/delete flow exists

### Camera Screen

`CameraView` currently provides:

- large camera icon
- static text `"Camera functionality"`
- static text `"Tap to scan receipts"`
- navigation title `"Scan Receipt"`

Current limitation:

- no camera integration
- no Vision document capture flow
- no OCR screen or confirmation UI

### Stores Screen

`StoresView` currently provides:

- navigation title `"Nearby Stores"`
- section `"Detection"` with navigation to `StoreDetectionView`
- section `"Your Stores"` with placeholder text `"Stores will appear here"`

Current limitation:

- no persisted store list query
- no manual store creation/editing UI

### Store Detection Screen

`StoreDetectionView` is one of the main implemented flows.

It provides:

- automatic detection on appearance
- pull-to-refresh to force another detection pass
- `"Best Match"` section if a best candidate exists
- `"All Candidates"` section listing scored candidates
- loading overlay with `"Detecting nearby store…"`
- alert for detection error text

Display behavior:

- best candidate row has accessibility ID `bestCandidateRow`
- each candidate row shows:
  - store name
  - source label (`Gps`, `Wifi`, or `Places`)
  - score as a percentage

Detection dependencies:

- requires `LocationService`
- requires a current location
- uses SwiftData `modelContext`

Current limitation:

- the `force` parameter in `runDetection(force:)` is accepted but not passed into lower-level cache bypass logic
- detection errors are only surfaced for missing location service, not empty location results

### Settings Screen

`SettingsRootView` currently provides:

- a single navigation path to `"Location & Privacy"`

It adapts `LocationService` state into user-facing strings:

- authorization:
  - Not Determined
  - Restricted
  - Denied
  - Always
  - When In Use
  - Authorized
  - Unknown
- accuracy:
  - Precise
  - Approximate
  - Unknown

### Location and Privacy Screen

`LocationPrivacySettingsView` is a fully wired settings form.

Features:

- toggle for `"Allow Location Features"`
- current authorization status display
- current accuracy display
- button `"Request Precise for Nearby Stores"`

Persistence behavior:

- reads stored `User.preferences.allowLocationTracking` if a `User` exists
- otherwise reads current service preference
- writes toggle changes back to:
  - `LocationService`
  - SwiftData `User.preferences`

Refresh behavior:

- updates on first appearance via `.task`
- updates when `LocationService.stateDidChange` notification is posted

Current limitation:

- assumes `users.first` is the active user
- there is no dedicated user onboarding or profile selection flow

### Location Usage Indicator

`LocationUsageIndicator` is a passive transparency UI.

When active it shows:

- location icon
- text `"Using your location"`

It updates:

- on first appearance
- when `LocationService.stateDidChange` fires

## Service Architecture

### AppCoordinator

`AppCoordinator` is the root orchestrator.

Responsibilities:

- own `appState`
- create and register services
- initialize all services
- run health checks
- expose services by `ServiceKey`
- forward background/foreground lifecycle events
- respond to memory warnings by calling `freeMemoryResources()` on `MemoryManaged` services

Registered services:

- `CloudKitSyncManager`
- `AppleIntelligenceService`
- `ErrorHandlingService`
- `LocationService`
- `GooglePlacesService`

Health-check behavior:

- if every registered service returns healthy, app moves to `ready`
- otherwise app moves to `failed`

Important implementation detail:

- `LocationService.healthCheck()` returns `state.isReady && isAuthorizedForUse`
- this means the app can fail initialization if location permission is not granted, even though location is not strictly required for the whole app

### ServiceRegistry

`ServiceRegistry` supports:

- register service by `ServiceKey`
- resolve optional service
- require service or throw dependency error
- initialize all services in dependency order
- shutdown all services in reverse order
- health-check all services
- expose service state map

Dependency handling:

- uses DFS topological ordering
- logs missing dependencies as warnings
- detects circular dependencies and logs them

### BaseService

`BaseService` provides default lifecycle behavior:

- `initialize()`
- `shutdown()`
- `healthCheck()`

It tracks:

- `identifier`
- `state`

Subclass override points:

- `performInitialization()`
- `performShutdown()`
- `performHealthCheck()`

### Service Protocols

Available protocols:

- `AppService`
- `MemoryManaged`
- `NetworkDependent`
- `SyncableService`

## Core Services

### LocationService

`LocationService` is implemented as an actor and also conforms directly to `AppService`.

#### Responsibilities

- own and configure `CLLocationManager`
- request when-in-use authorization
- store user preference for allowing location tracking
- start and stop live location updates
- expose a snapshot of current location state
- request temporary precise accuracy when needed
- run nearby store detection using `StoreDetectionService`
- notify UI that location state changed
- send a one-time local notification explaining location usage

#### Persisted Keys

`UserDefaults` keys:

- `LocationService.hasShownUsageNotification`
- `UserPreferences.allowLocationTracking`

#### Runtime State

Tracked state includes:

- `currentLocation`
- `authorizationStatus`
- `accuracyAuthorization`
- `isAuthorizedForUse`
- `hasPreciseAccuracy`
- `isActivelyUpdating`
- `allowLocationTracking`

#### Initialization Flow

On `initialize()`:

- sets delegate bridge callbacks
- assigns `CLLocationManager.delegate`
- sets `desiredAccuracy = kCLLocationAccuracyBest`
- requests when-in-use authorization if status is `.notDetermined`
- refreshes authorization-derived flags
- loads saved `allowLocationTracking` from `UserDefaults`
- starts updates only if:
  - location is authorized, and
  - user has opted in

#### Public API

Methods:

- `setAllowLocationTracking(_:)`
- `getAllowLocationTracking()`
- `requestPreciseLocationIfNeeded()`
- `requestTemporaryFullAccuracyIfNeeded(purposeKey:)`
- `startUpdatingLocationIfAuthorized()`
- `stopUpdatingLocation()`
- `snapshot()`
- `detectNearbyStore(using:)`
- `detectNearbyStore(using:ssidMapping:)`

#### UI Notification Behavior

Posts `LocationService.stateDidChange` through `NotificationCenter`.

#### One-Time Transparency Notification

When live location starts for the first time, the service best-effort:

- requests notification permission if needed
- schedules a local notification:
  - title: `"Location in Use"`
  - body: `"We use your location to show nearby results. You can change this anytime in Settings."`

#### Current Limitations

- location errors are silently ignored in `handleLocationError(_:)`
- health check requires authorization, which may cause app startup failure
- no region monitoring or background location support
- nearby store detection requires an already-populated `currentLocation`

### StoreDetectionService

`StoreDetectionService` orchestrates nearby store matching.

#### Inputs

- current `CLLocation`
- optional `ModelContext`
- optional Wi-Fi SSID provider
- optional SSID-to-store-name mapping
- internal `DetectionCache`

#### Output

`Result` contains:

- `best: DetectedCandidate?`
- `candidates: [DetectedCandidate]`

#### Detection Order

1. GPS-based matching against known SwiftData stores
2. Wi-Fi SSID hint matching against known SwiftData stores
3. MapKit local search for `"grocery store"`

#### Early Exit Rule

If the current best candidate reaches `score >= 0.6` after GPS or Wi-Fi stages, later stages are skipped.

#### GPS Detection

Requires `modelContext`.

Behavior:

- fetches all `Store` models
- calculates distance from current location to each store
- scores by distance plus GPS bonus
- returns top 10 sorted descending by score

#### Wi-Fi Detection

Requires:

- `modelContext`
- SSID string from `ssidProvider`
- matching SSID in provided dictionary

Behavior:

- fetches all stores
- filters by case-insensitive name contains match on mapped store name
- scores by distance plus strong Wi-Fi bonus

#### Places Detection

Behavior:

- runs `MKLocalSearch` with natural language query `"grocery store"`
- searches within 1500 meters
- maps results into transient `DetectedCandidate`s
- scores by distance plus places bonus
- returns top 10

#### Score Formula

Distance score:

- 1.0 at 0 meters
- tapers linearly to 0.0 at 200 meters

Source bonus:

- GPS: `+0.05`
- Wi-Fi: `+0.5`
- Places: `+0.25`

Final score is clamped to `<= 1.0`.

#### Cache Behavior

`DetectionCache`:

- actor-backed in-memory cache
- key based on location rounded to ~0.001 degrees
- default TTL is 180 seconds

### CurrentSSIDProvider

Best-effort current Wi-Fi SSID reader.

Lookup order:

1. `NEHotspotNetwork.fetchCurrent` on iOS 14+
2. deprecated CaptiveNetwork fallback

Expected behavior:

- returns SSID if available
- returns `nil` if restricted, unsupported, or missing entitlement/permissions

### GooglePlacesService

`GooglePlacesService` is the most detailed external integration in the project.

#### Responsibilities

- configure Google Places SDK
- provide autocomplete sessions
- fetch place details
- persist place details cache
- run nearby grocery store search via Google Places Web API
- apply request budgets and cooldowns
- fall back to cache when possible
- monitor network reachability

#### Initialization

On service initialization:

- reads `Secrets.googlePlacesAPIKey`
- fails initialization if the key is empty
- calls `GMSPlacesClient.provideAPIKey`
- starts `NWPathMonitor`
- asynchronously loads cached place snapshot from disk using `PlacesCacheStore`

Important consequence:

- because `Secrets.googlePlacesAPIKey` is currently `""`, service initialization will fail unless a key is supplied
- since this service is registered during app startup, the app may enter failed state immediately

#### Public Data Types

Defined types:

- `PlacesError`
- `PlaceSuggestion`
- `GooglePlaceDetails`
- `SessionToken`
- `StorePlaceType`

#### PlacesError Cases

- `invalidAPIKey`
- `quotaExceeded`
- `rateLimited`
- `networkUnavailable`
- `offlineDataExpired`
- `serviceUnavailable`
- `unknown(String)`

#### Session Management

Autocomplete supports:

- `beginAutocompleteSession()`
- `cancelAutocompleteSession()`
- `didSelectPlace(with:)`

It creates:

- internal custom `SessionToken`
- Google `GMSAutocompleteSessionToken`

#### Autocomplete

`autocomplete(query:)` behavior:

- requires configured API key
- auto-starts a session if needed
- enforces cooldown window
- if network unavailable, returns cached suggestions matching query
- consumes autocomplete rate budget
- throttles requests by minimum interval
- adds a small sleep-based debounce
- calls `GMSPlacesClient.findAutocompletePredictions`
- maps predictions into lightweight `PlaceSuggestion`
- on failure:
  - maps the error
  - may start cooldown for rate/quota issues
  - falls back to cache results

#### Fetch Place Details

`fetchPlaceDetails(placeID:)` behavior:

- returns cache hit immediately if available
- requires API key
- enforces cooldown
- fails if network unavailable
- consumes details budget
- requests fields:
  - name
  - formatted address
  - coordinate
  - phone number
  - placeID
  - address components
  - website
- extracts:
  - city
  - state
  - zip
  - country
- caches successful details in memory
- best-effort persists cache snapshot to disk

#### Nearby Store Search

`searchNearbyStores(center:radiusMeters:types:limit:)` behavior:

- requires API key and network
- enforces cooldown
- consumes nearby search budget
- uses a rounded-coordinate cache key
- returns cached nearby results when available
- otherwise calls Google Places Nearby Search Web API
- supports either:
  - explicit Google place types, or
  - fallback keyword `"grocery store"` if type list is empty
- deduplicates by `placeID`
- fetches full details for each nearby result
- ranks by distance ascending
- maps details into transient `Store` models
- returns at most `limit`

#### Nearby Search Mapping Rules

`GooglePlaceDetails` is converted into a `Store` only if all of the following exist:

- coordinate
- address
- city
- state
- zipCode
- country

Fields mapped:

- `name`
- `chain` inferred from name/website
- `address`
- `city`
- `state`
- `zipCode`
- `country`
- `phoneNumber`
- `website`
- `latitude`
- `longitude`
- `locationAccuracy = nil`

#### Chain Inference

Known chain heuristics include:

- Walmart
- Target
- Costco
- Safeway
- Kroger
- Whole Foods
- Trader Joe's
- ALDI
- Lidl
- Sam's Club
- Albertsons
- Publix
- H-E-B
- Meijer
- Fred Meyer

Inference sources:

- `details.name`
- website host substring

#### Request Protection

Budgets:

- autocomplete: 30 requests / 60 seconds
- details: 60 requests / 60 seconds
- nearby: 30 requests / 60 seconds

Cooldown behavior:

- rate-limited -> 30 seconds
- quota exceeded -> 300 seconds

#### Cache Layers

In-memory details cache:

- actor `PlacesCache`
- detail TTL defaults to 30 days
- durable set of selected place IDs

Nearby search cache:

- actor `NearbySearchCache`
- TTL defaults to 600 seconds

Disk persistence:

- `PlacesCacheStore.shared`
- file name `places_cache.json`
- stored under Application Support / `PlacesCache`

#### Reachability

Uses `NWPathMonitor` and stores a Boolean `isNetworkReachable`.

#### Error Mapping

Maps from:

- `PrixioError`
- `PlacesError`
- `GMSPlacesErrorCode`
- `NSURLErrorDomain`

Network-related mapping includes:

- no connection
- timeout
- cannot find/connect host

#### Current Limitations

- service hard-fails startup when API key is missing
- debouncer actor exists but is not actually used in request dispatch
- there are two cache store source files in the repo, but only `PlacesCacheStore` is referenced
- nearby search relies on full detail fetches per place, which is potentially expensive

### AppleIntelligenceService

`AppleIntelligenceService` is implemented and usable independently, but not connected to UI flow.

#### Responsibilities

- OCR text recognition
- barcode detection
- basic price extraction from text
- currency symbol detection
- basic memory accounting

#### OCR Pipeline

Input:

- raw image `Data`

Processing:

- decode to `UIImage` / `CGImage`
- run `VNRecognizeTextRequest`
- run `VNDetectBarcodesRequest`

Output:

- `detectedPrices: [Decimal]`
- `currencyCode: String?`
- `detectedBarcodes: [String]`
- `fullText: String`
- `confidence: Double`

#### Price Extraction Rule

Regex matches values like:

- optional `$`, `€`, or `£`
- integer or comma-grouped number
- optional decimal cents

Currency symbol mapping:

- `$` -> `USD`
- `€` -> `EUR`
- `£` -> `GBP`

#### Memory Management

- increments `processedImages`
- reports `memoryUsage = processedImages * 1024`
- `freeMemoryResources()` resets image count

#### Current Limitations

- no UI integration
- no receipt-line parsing
- no product matching
- no persistence of OCR results

### ErrorHandlingService

Responsibilities:

- collect handled errors into `errorHistory`
- log handled errors

Stored record fields:

- error
- context
- timestamp

### CloudKitSyncManager

Status:

- explicitly deprecated

Current behavior:

- still registered as a service
- initializes and health-checks
- tracks `lastSyncTime` and `isSyncing`
- exposes `syncIfNeeded()`, `forceSync()`, and `handleNetworkChange(_:)`
- minimal `savePriceEntry(_:)` and `fetchPriceEntryRecord(id:)` methods are present but intentionally no-op

Important note:

- app comments indicate SwiftData CloudKit-backed `ModelContainer` should replace this manager

### DatabaseManager

Status:

- explicitly deprecated
- not registered
- no-op lifecycle only

## Data Model Specification

## Enumerations

### CaptureMethod

Supported values:

- `manual`
- `camera`
- `ai_enhanced`
- `barcode`
- `import`
- `estimated`

### ImageType

Supported values:

- `product`
- `receipt`
- `price_tag`
- `storefront`
- `interior`
- `shelf`

### ProductCategory

Supported values:

- `produce`
- `meat`
- `dairy`
- `bakery`
- `pantry`
- `beverages`
- `frozen`
- `personal_care`
- `household`
- `health`
- `baby`
- `pet`
- `other`

### SyncStatus

Supported values:

- `pending`
- `syncing`
- `synced`
- `failed`
- `conflict`

### ValidationStatus

Supported values:

- `pending`
- `valid`
- `invalid`
- `suspicious`
- `user_verified`

## Models

### PriceEntry

SwiftData model with:

- `id: UUID` unique
- `price: Decimal` transformable via `DecimalTransformer`
- `captureDate: Date`
- `captureMethod: CaptureMethod`
- `notes: String?`
- `validationStatus: ValidationStatus`
- `confidenceScore: Double`
- `store: Store?`
- `product: Product?`
- `capturedBy: User?`
- `sourceImage: ProductImage?`
- `createdAt: Date`
- `updatedAt: Date`
- `isDeleted: Bool`

Relationships:

- `store` inverse `Store.priceEntries`
- `product` inverse `Product.priceEntries`
- `capturedBy` nullified on delete

Soft delete:

- uses `isDeleted`

Helper:

- `touch()` updates `updatedAt`

Validation rules:

- price must be `> 0`
- price must be finite
- `captureDate` must be within 5 years past and 5 years future of now
- at least one association must exist:
  - `store`, or
  - `product`
- `confidenceScore` must be between `0.0` and `1.0`

Important mismatch:

- `ARCHITECTURE.md` says capture date should not be in the future
- actual code allows up to 5 years in the future

### Product

SwiftData model with:

- `id: UUID` unique
- `name: String`
- `productDescription: String?`
- `brand: String?`
- `category: ProductCategory`
- `barcode: String?` unique and cloud-encrypted
- `sizeInformation: String?`
- `unit: String?`
- `priceEntries: [PriceEntry]`
- `images: [ProductImage]`
- `createdAt: Date`
- `updatedAt: Date`
- `isDeleted: Bool`

Image relationship:

- cascades delete to `ProductImage`

Helper:

- `touch()`

Validation rules:

- trimmed `name` must not be empty
- `category` exists by type system only
- `barcode`, if present:
  - must be digits only
  - length must be one of `8`, `12`, `13`, `14`

### ProductImage

SwiftData model with:

- `id: UUID` unique
- `imageData: Data?` cloud-encrypted
- `cloudKitAssetURL: String?` ephemeral
- `imageType: ImageType`
- `caption: String?`
- `sortOrder: Int`
- `product: Product?`
- `priceEntries: [PriceEntry]`
- `createdAt: Date`
- `updatedAt: Date`
- `isDeleted: Bool`

Purpose:

- stores product, receipt, price-tag, or related images
- can link OCR-derived `PriceEntry` records via `sourceImage`

### Store

SwiftData model with:

- `id: UUID` unique
- `name: String`
- `chain: String?`
- `address: String`
- `city: String`
- `state: String`
- `zipCode: String`
- `country: String`
- `phoneNumber: String?`
- `website: String?`
- `latitude: Double`
- `longitude: Double`
- `locationAccuracy: Double?`
- `priceEntries: [PriceEntry]`
- `images: [StoreImage]`
- `createdAt: Date`
- `updatedAt: Date`
- `isDeleted: Bool`

Image relationship:

- cascades delete to `StoreImage`

Helper:

- `touch()`

Validation rules:

- trimmed name must not be empty
- address, city, state, zip, and country must all be non-empty after trimming
- latitude must be within `-90...90`
- longitude must be within `-180...180`

### StoreImage

SwiftData model with:

- `id: UUID` unique
- `imageData: Data?` cloud-encrypted
- `cloudKitAssetURL: String?` ephemeral
- `imageType: ImageType`
- `caption: String?`
- `sortOrder: Int`
- `store: Store?`
- `createdAt: Date`
- `updatedAt: Date`
- `isDeleted: Bool`

### User

SwiftData model with:

- `id: UUID` unique
- `displayName: String`
- `email: String?` unique and cloud-encrypted
- `preferences: UserPreferences?` transformable
- `cloudKitRecordID: String?` ephemeral
- `syncStatus: SyncStatus` ephemeral
- `lastSyncAttempt: Date?` ephemeral
- `syncError: String?` ephemeral
- `createdAt: Date`
- `updatedAt: Date`
- `isDeleted: Bool`

Current usage:

- mainly used to persist `UserPreferences`
- location settings screen assumes first user is active

## Settings Data

### NotificationSettings

Fields:

- `priceAlerts: Bool = true`
- `dealNotifications: Bool = true`
- `syncNotifications: Bool = true`
- `enablePushNotifications: Bool = true`
- `enableEmailNotifications: Bool = false`

### UserPreferences

Fields:

- `defaultCurrency: String = "USD"`
- `defaultUnit: String = "Imperial"`
- `allowLocationTracking: Bool = false`
- `shareDataAnonymously: Bool = false`
- `notificationSettings: NotificationSettings`

## Transformers

### DecimalTransformer

Transforms:

- `Decimal` <-> archived `NSDecimalNumber` `Data`

### UserPreferencesTransformer

Transforms:

- `UserPreferences` <-> JSON `Data`

## Validation Error Model

`ValidationError` cases:

- `emptyName`
- `invalidPrice`
- `invalidDateRange`
- `missingCategory`
- `invalidBarcode`
- `invalidCoordinates`
- `missingAssociation(String)`
- `custom(String)`

## Logging and Error Model

### Logging

`Logging.shared` wraps `OSLog.Logger`.

Supported levels:

- `info`
- `debug`
- `warning`
- `error`

Categories:

- `general`
- `network`
- `database`
- `sync`
- `ml`
- `lifecycle`
- `ui`
- `performance`

Metadata:

- formatted as `key=value` pairs appended to log message

### PrixioError

Structured error families:

- service initialization
- dependency resolution
- database
- network
- sync
- permissions
- data processing
- memory/resource availability

Permission types:

- camera
- location
- notifications
- cloudkit

This error type also defines:

- `errorDescription`
- `failureReason`
- `recoverySuggestion`

## Caching and Persistence Details

### SwiftData Container

The app container currently includes only:

- `PriceEntry`
- `Product`
- `Store`

Important limitation:

- `User`, `ProductImage`, and `StoreImage` exist as models but are not listed in the `modelContainer(for:)` call
- if those entities are expected to persist through SwiftData, the container definition is incomplete

### Places Cache Persistence

Primary store:

- `PlacesCacheStore`

Behavior:

- loads JSON from Application Support
- saves JSON snapshots atomically
- stores:
  - place details
  - durable place IDs

Repository anomaly:

- `PlacesCacheStore 2.swift` also exists and defines `PlacesCacheStoreV2`
- appears to be alternate or newer persistence work
- current `GooglePlacesService` does not use it

### Price Query Helpers

`PriceEntryQueries.swift` exists only as commented example code for:

- latest price by product
- latest price by store

It shows intended query style:

- filter out `isDeleted == true`
- sort by `captureDate` descending
- fetch first result

## Permissions, Entitlements, and Config

### Info.plist

Current plist only contains:

- `UIBackgroundModes = ["remote-notification"]`

Missing from source as checked:

- location usage description strings
- camera usage description strings
- notification usage description strings

These may be required elsewhere in project settings, but they are not present in this file.

### Entitlements

`Prixio.entitlements` is currently empty.

Impact:

- no NetworkExtension entitlements for SSID lookup
- no obvious iCloud entitlements declared here

### Secrets

`Secrets.googlePlacesAPIKey` is blank and marked TODO.

Rebuild requirement:

- this must be replaced with build-time or runtime secret injection for Google Places features to initialize successfully

## Deprecated, Duplicate, or Transitional Code

### Documented Architectural Drift

`ARCHITECTURE.md` says:

- avoid actor-based services
- use simple SwiftUI-friendly flows

Actual implementation uses actors for:

- `LocationService`
- `DetectionCache`
- `PlacesCache`
- `NearbySearchCache`
- `Debouncer`

### Deprecated Components

- `CloudKitSyncManager`
- `DatabaseManager`

### Duplicate / Transitional Files

- `PlacesCacheStore.swift`
- `PlacesCacheStore 2.swift`

This suggests an unfinished migration in the Places caching layer.

## Test Coverage

### Unit Tests

`PrixioTests.swift` contains only template placeholder test code.

### UI Tests

`PrixioUITests.swift` contains:

- basic launch test
- launch performance measurement

`PrixioUITestsLaunchTests.swift` contains:

- launch screenshot test

Current gap:

- no tests for models
- no validation tests
- no location permission tests
- no store detection tests
- no Google Places tests
- no snapshot or navigation tests

## Rebuild Blueprint

To rebuild the current app faithfully, implement the following layers in this order.

### 1. App Shell

- SwiftUI app entry
- single `AppCoordinator`
- root content state machine
- four-tab navigation
- overlay location usage badge

### 2. Core Service Framework

- `AppService` protocol
- `BaseService`
- `ServiceRegistry`
- `ServiceState`
- `ServiceKey`
- structured logging
- structured app errors

### 3. Data Layer

- SwiftData models:
  - `PriceEntry`
  - `Product`
  - `Store`
  - `ProductImage`
  - `StoreImage`
  - `User`
- transformable types:
  - `DecimalTransformer`
  - `UserPreferencesTransformer`
- enums:
  - capture methods
  - image types
  - categories
  - sync status
  - validation status

### 4. Validation Layer

- per-model `validate()` methods
- shared `ValidationError`
- `touch()` timestamp helpers

### 5. Location Stack

- actor-based location service
- CLLocationManager delegate bridge
- user defaults preference gating
- notification center updates
- settings UI bound to service snapshot
- one-time local notification for transparency

### 6. Store Detection Stack

- `DetectedCandidate`
- in-memory detection cache
- GPS scoring against persisted stores
- optional Wi-Fi SSID matching
- MapKit local search fallback
- best-candidate and candidate-list UI

### 7. Google Places Stack

- Google Places SDK initialization
- autocomplete session management
- rate limiting and cooldowns
- place detail fetching and address component parsing
- JSON-backed cache persistence
- nearby grocery store search via Google Nearby Search API
- chain inference heuristics

### 8. AI/OCR Stack

- Vision text recognition
- barcode detection
- regex-based price extraction
- OCR result model

### 9. Current UI Scaffolds

Replicate current non-final screens as placeholders:

- recent prices placeholder
- camera placeholder
- your stores placeholder
- retry button with no action

## Known Gaps That Matter for a Full Product Rebuild

These are not just missing polish. They are missing product functionality.

- no workflow to create a `User`
- no workflow to add/edit/delete `Product`
- no workflow to add/edit/delete `Store`
- no workflow to create `PriceEntry`
- no UI that uses `AppleIntelligenceService`
- no UI that uses `GooglePlacesService` directly
- no receipt capture pipeline
- no product search or barcode search flow
- no sync conflict handling UI
- no background sync implementation
- no real retry behavior on app failure screen

## Immediate Requirements to Make This Repo Rebuildable as Working Software

If the target is a functioning rebuild rather than a static clone, these issues must be addressed first:

- provide a Google Places API key
- decide whether Google Places service failure should block app startup
- add missing usage description plist keys for location, camera, and notifications
- decide whether `User`, `ProductImage`, and `StoreImage` belong in the SwiftData container
- remove or reconcile duplicate `PlacesCacheStore` implementations
- define whether `captureDate` may be future-dated
- replace placeholder UI for prices, stores, camera, and retry

## File Role Index

### App and Views

- `Prixio/Prixio/PrixioApp.swift`: app entry and model container
- `Prixio/Prixio/Prixio-AI/App/Views/ContentView.swift`: root state switch
- `Prixio/Prixio/Prixio-AI/App/Views/LoadingView.swift`: loading screen
- `Prixio/Prixio/Prixio-AI/App/Views/ErrorView.swift`: error screen
- `Prixio/Prixio/Prixio-AI/App/Views/MainTabView.swift`: tab shell and location badge
- `Prixio/Prixio/Prixio-AI/App/Views/PriceListView.swift`: prices placeholder
- `Prixio/Prixio/Prixio-AI/App/Views/CameraView.swift`: camera placeholder
- `Prixio/Prixio/Prixio-AI/App/Views/StoresView.swift`: stores placeholder and detection entry
- `Prixio/Prixio/Prixio-AI/Core/SettingsRootView.swift`: settings navigation
- `Prixio/Prixio/Prixio-AI/Core/LocationPrivacySettingsView.swift`: location/privacy feature UI
- `Prixio/Prixio/Prixio-AI/Core/LocationUsageIndicator.swift`: active location badge
- `Prixio/Prixio/Prixio-AI/Core/StoreDetectionView.swift`: detection results UI

### Coordination and Services

- `Prixio/Prixio/Prixio-AI/Core/Coordinators/AppCoordinator.swift`: app orchestration
- `Prixio/Prixio/Prixio-AI/Core/Coordinators/GooglePlacesService.swift`: Google Places integration
- `Prixio/Prixio/Prixio-AI/Core/Coordinators/PlacesCacheStore.swift`: persisted places cache
- `Prixio/Prixio/Prixio-AI/Core/Coordinators/PlacesCacheStore 2.swift`: alternate cache store
- `Prixio/Prixio/Prixio-AI/Core/Coordinators/Secrets.swift`: secret placeholder
- `Prixio/Prixio/Prixio-AI/Core/Services/AppleIntelligenceService.swift`: OCR/barcode analysis
- `Prixio/Prixio/Prixio-AI/Core/Services/CloudKitSyncManager.swift`: deprecated sync manager
- `Prixio/Prixio/Prixio-AI/Core/Services/DatabaseManager.swift`: deprecated database service
- `Prixio/Prixio/Prixio-AI/Core/Services/ErrorHandlingService.swift`: error history service
- `Prixio/Prixio/Prixio-AI/Core/Services/ServiceRegistry.swift`: service container
- `Prixio/Prixio/Prixio-AI/Core/LocationService.swift`: permission and live location manager
- `Prixio/Prixio/Prixio-AI/Core/StoreDetectionService.swift`: multi-source store detection
- `Prixio/Prixio/Prixio-AI/Core/CurrentSSIDProvider.swift`: SSID lookup helper

### Models and Foundations

- `Prixio/Prixio/Prixio-AI/Core/Models/Models/*.swift`: persisted entities
- `Prixio/Prixio/Prixio-AI/Core/Models/enums/*.swift`: enum definitions
- `Prixio/Prixio/Prixio-AI/Core/Models/Settings/*.swift`: preference structs
- `Prixio/Prixio/Prixio-AI/Core/Models/Transformers/*.swift`: transformable storage helpers
- `Prixio/Prixio/Prixio-AI/Core/Foundation/LoggingActor.swift`: logging helper
- `Prixio/Prixio/Prixio-AI/Core/Foundation/PrixioError.swift`: structured errors

### Project Metadata and Tests

- `Prixio/Prixio/ARCHITECTURE.md`: architectural intent
- `Prixio/Prixio/Info.plist`: app plist
- `Prixio/Prixio/Prixio.entitlements`: entitlements file
- `Prixio/PrixioTests/PrixioTests.swift`: placeholder unit test
- `Prixio/PrixioUITests/PrixioUITests.swift`: basic UI launch tests
- `Prixio/PrixioUITests/PrixioUITestsLaunchTests.swift`: launch screenshot test

## Bottom Line

The codebase is best described as a structured MVP skeleton with one materially implemented vertical slice: privacy-aware location-driven store detection, backed by a serious but not fully integrated Google Places and OCR foundation.

It is not yet a fully functioning price-tracking product, but it contains enough concrete architecture and model detail to rebuild the current project accurately.
