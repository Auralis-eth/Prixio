import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftData
import UIKit
@preconcurrency import Vision

enum UnitType: String, Codable, CaseIterable, Identifiable {
    case each
    case lb
    case kg
    case liter
    case hundredGrams

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .each:
            return "Each"
        case .lb:
            return "lb"
        case .kg:
            return "kg"
        case .liter:
            return "L"
        case .hundredGrams:
            return "100 g"
        }
    }
}

@Model
final class PriceEntry {
    var id: UUID
    var createdAt: Date
    var capturedAt: Date
    var itemNameRaw: String
    var itemNameNormalized: String
    var priceValue: Decimal
    var currencyCode: String
    var unitType: UnitType
    var unitQuantityValue: Decimal?
    var normalizedUnitPriceValue: Decimal?
    var normalizedUnitType: UnitType?
    var storeChainId: UUID?
    var storeLocationId: UUID?
    var storeChainNameSnapshot: String?
    var storeLocationNameSnapshot: String?
    var storeCoordinateLat: Double?
    var storeCoordinateLon: Double?
    var photoAssetId: String
    var ocrText: String?
    var confidence: Float?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        capturedAt: Date,
        itemNameRaw: String,
        itemNameNormalized: String,
        priceValue: Decimal,
        currencyCode: String = "CAD",
        unitType: UnitType,
        unitQuantityValue: Decimal? = nil,
        normalizedUnitPriceValue: Decimal? = nil,
        normalizedUnitType: UnitType? = nil,
        storeChainId: UUID? = nil,
        storeLocationId: UUID? = nil,
        storeChainNameSnapshot: String? = nil,
        storeLocationNameSnapshot: String? = nil,
        storeCoordinateLat: Double? = nil,
        storeCoordinateLon: Double? = nil,
        photoAssetId: String,
        ocrText: String? = nil,
        confidence: Float? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.itemNameRaw = itemNameRaw
        self.itemNameNormalized = itemNameNormalized
        self.priceValue = priceValue
        self.currencyCode = currencyCode
        self.unitType = unitType
        self.unitQuantityValue = unitQuantityValue
        self.normalizedUnitPriceValue = normalizedUnitPriceValue
        self.normalizedUnitType = normalizedUnitType
        self.storeChainId = storeChainId
        self.storeLocationId = storeLocationId
        self.storeChainNameSnapshot = storeChainNameSnapshot
        self.storeLocationNameSnapshot = storeLocationNameSnapshot
        self.storeCoordinateLat = storeCoordinateLat
        self.storeCoordinateLon = storeCoordinateLon
        self.photoAssetId = photoAssetId
        self.ocrText = ocrText
        self.confidence = confidence
    }
}

@Model
final class StoreChain {
    var id: UUID
    var name: String
    var aliases: [String]

    init(id: UUID = UUID(), name: String, aliases: [String]) {
        self.id = id
        self.name = name
        self.aliases = aliases
    }
}

@Model
final class StoreLocation {
    var id: UUID
    var chainId: UUID?
    var displayName: String
    var address: String?
    var city: String?
    var region: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var mapKitPlaceId: String?

    init(
        id: UUID = UUID(),
        chainId: UUID? = nil,
        displayName: String,
        address: String? = nil,
        city: String? = nil,
        region: String? = nil,
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        mapKitPlaceId: String? = nil
    ) {
        self.id = id
        self.chainId = chainId
        self.displayName = displayName
        self.address = address
        self.city = city
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.mapKitPlaceId = mapKitPlaceId
    }
}

struct OCRResult {
    var rawText: String
    var itemNameHint: String?
    var price: Decimal?
    var unit: UnitType?
    var quantity: Decimal?
    var confidence: Float?
    var priceCandidates: [PriceCandidate]
}

struct PriceCandidate: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: Decimal
    let quantity: Decimal?
}

struct StoreCandidate: Identifiable {
    let id: UUID
    let chainName: String?
    let locationName: String
    let address: String?
    let coordinate: CLLocationCoordinate2D?
    let distanceMeters: CLLocationDistance?
    let mapKitPlaceId: String?
}

enum PriceParsingService {
    private static let currencyPattern = #"\$?\s*(\d+[.,]\d{2})"#
    private static let multiBuyPattern = #"(\d+)\s*(?:/|for)\s*\$?\s*(\d+(?:[.,]\d{2})?)"#
    private static let poundsPerKilogram = Decimal(string: "2.2046226218")!
    private static let receiptMarkers = [
        "subtotal",
        "total",
        "tax",
        "hst",
        "gst",
        "change",
        "thank you",
        "receipt",
        "visa",
        "mastercard"
    ]

    static func extract(from text: String) -> OCRResult {
        let normalizedText = text.replacingOccurrences(of: ",", with: ".")
        let priceCandidates = extractPriceCandidates(from: normalizedText)
        let unit = detectUnit(in: normalizedText)
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let itemNameHint = lines.first { line in
            !line.contains("$") && detectUnit(in: line) == nil && !line.contains(where: { $0.isNumber })
        }

        return OCRResult(
            rawText: text,
            itemNameHint: itemNameHint,
            price: priceCandidates.first?.value,
            unit: unit,
            quantity: priceCandidates.first?.quantity,
            confidence: priceCandidates.isEmpty ? 0.1 : 0.72,
            priceCandidates: priceCandidates
        )
    }

    static func normalize(price: Decimal, unit: UnitType, quantity: Decimal?) -> (Decimal, UnitType)? {
        let effectivePrice = unitPrice(price: price, quantity: quantity)

        switch unit {
        case .lb:
            return (effectivePrice * poundsPerKilogram, .kg)
        case .kg:
            return (effectivePrice, .kg)
        case .each:
            return (effectivePrice, .each)
        case .liter:
            return (effectivePrice, .liter)
        case .hundredGrams:
            return (effectivePrice * 10, .kg)
        }
    }

    static func unitPrice(price: Decimal, quantity: Decimal?) -> Decimal {
        guard let quantity, quantity > 0 else {
            return price
        }
        return price / quantity
    }

    static func looksLikeReceipt(text: String) -> Bool {
        let lowered = text.lowercased()
        let markerCount = receiptMarkers.reduce(into: 0) { count, marker in
            if lowered.contains(marker) {
                count += 1
            }
        }
        return markerCount >= 2
    }

    private static func extractPriceCandidates(from text: String) -> [PriceCandidate] {
        var candidates: [PriceCandidate] = []

        if let regex = try? NSRegularExpression(pattern: multiBuyPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard
                    let quantityRange = Range(match.range(at: 1), in: text),
                    let priceRange = Range(match.range(at: 2), in: text),
                    let quantity = Decimal(string: String(text[quantityRange])),
                    let price = Decimal(string: String(text[priceRange]))
                else {
                    continue
                }

                candidates.append(
                    PriceCandidate(
                        label: "\(quantity) for $\(price)",
                        value: price,
                        quantity: quantity
                    )
                )
            }
        }

        if let regex = try? NSRegularExpression(pattern: currencyPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard
                    let range = Range(match.range(at: 1), in: text),
                    let price = Decimal(string: String(text[range]))
                else {
                    continue
                }

                if candidates.contains(where: { $0.value == price && $0.quantity == nil }) {
                    continue
                }

                candidates.append(
                    PriceCandidate(
                        label: "$\(price)",
                        value: price,
                        quantity: nil
                    )
                )
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.quantity != nil, rhs.quantity == nil {
                return true
            }

            return lhs.value > rhs.value
        }
    }

    private static func detectUnit(in text: String) -> UnitType? {
        let lowered = text.lowercased()

        if lowered.contains("100 g") || lowered.contains("100g") {
            return .hundredGrams
        }
        if lowered.contains(" lbs") || lowered.contains("/lb") || lowered.contains(" lb") {
            return .lb
        }
        if lowered.contains("/kg") || lowered.contains(" kg") {
            return .kg
        }
        if lowered.contains(" ea") || lowered.contains(" each") {
            return .each
        }
        if lowered.contains(" l") || lowered.contains("/l") {
            return .liter
        }

        return nil
    }
}

enum StoreCatalog {
    static let commonChains: [(name: String, aliases: [String])] = [
        ("Unknown", []),
        ("Co-op", ["Calgary Co-op", "COOP", "Co-op"]),
        ("Sobeys", ["Sobeys"]),
        ("Safeway", ["Safeway"]),
        ("Real Canadian Superstore", ["Superstore", "Real Canadian Superstore", "RCSS"]),
        ("Walmart", ["Walmart"])
    ]

    static func inferredChain(from text: String) -> String? {
        let lowered = text.lowercased()
        return commonChains.first { chain in
            chain.name != "Unknown" && chain.aliases.contains { lowered.contains($0.lowercased()) }
        }?.name
    }

    static func mapItemIdentifier(name: String, coordinate: CLLocationCoordinate2D?) -> String {
        let lat = coordinate?.latitude ?? 0
        let lon = coordinate?.longitude ?? 0
        return "\(name)-\(lat)-\(lon)"
    }
}

@MainActor
final class ScanSessionStore: ObservableObject {
    @Published private(set) var nearbyCandidates: [StoreCandidate] = []
    @Published private(set) var lastStoreCandidate: StoreCandidate?

    private var cachedAt: Date?

    func updateCandidates(_ candidates: [StoreCandidate]) {
        nearbyCandidates = candidates
        cachedAt = .now
        lastStoreCandidate = candidates.first
    }

    func useLastStore(_ candidate: StoreCandidate?) {
        lastStoreCandidate = candidate
    }

    func cachedCandidatesIfFresh() -> [StoreCandidate]? {
        guard let cachedAt, Date.now.timeIntervalSince(cachedAt) < 300 else {
            return nil
        }
        return nearbyCandidates
    }
}

final class OCRService {
    func analyze(image: UIImage) async -> OCRResult {
        guard let cgImage = image.cgImage else {
            return PriceParsingService.extract(from: "")
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: PriceParsingService.extract(from: text))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try? handler.perform([request])
            }
        }
    }
}

@MainActor
final class StoreDetectionService {
    func fetchNearbyStores(location: CLLocation?) async -> [StoreCandidate] {
        guard let location else {
            return []
        }

        var collected: [StoreCandidate] = []
        let queries = ["grocery", "supermarket"] + StoreCatalog.commonChains.map(\.name).filter { $0 != "Unknown" }

        for query in queries {
            var request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 1_000,
                longitudinalMeters: 1_000
            )

            let response = try? await MKLocalSearch(request: request).start()
            let items = response?.mapItems ?? []
            collected.append(contentsOf: items.map { item in
                let placemarkLocation = item.placemark.location
                return StoreCandidate(
                    id: UUID(),
                    chainName: StoreCatalog.inferredChain(from: item.name ?? ""),
                    locationName: item.name ?? "Unknown Store",
                    address: item.placemark.title,
                    coordinate: placemarkLocation?.coordinate,
                    distanceMeters: placemarkLocation?.distance(from: location),
                    mapKitPlaceId: StoreCatalog.mapItemIdentifier(
                        name: item.name ?? "Unknown Store",
                        coordinate: placemarkLocation?.coordinate
                    )
                )
            })
        }

        let deduplicated = Dictionary(
            collected.map { candidate in
                ("\(candidate.locationName)|\(candidate.address ?? "")", candidate)
            },
            uniquingKeysWith: { current, _ in current }
        )

        return Array(deduplicated.values).sorted { lhs, rhs in
            let lhsRank = lhs.chainName == nil ? 1 : 0
            let rhsRank = rhs.chainName == nil ? 1 : 0

            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            return (lhs.distanceMeters ?? .greatestFiniteMagnitude) < (rhs.distanceMeters ?? .greatestFiniteMagnitude)
        }
    }

    func search(query: String, near location: CLLocation?) async -> [StoreCandidate] {
        guard !query.isEmpty else {
            return []
        }

        var request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5_000,
                longitudinalMeters: 5_000
            )
        }

        let response = try? await MKLocalSearch(request: request).start()
        return (response?.mapItems ?? []).map { item in
            let placemarkLocation = item.placemark.location
            return StoreCandidate(
                id: UUID(),
                chainName: StoreCatalog.inferredChain(from: item.name ?? ""),
                locationName: item.name ?? "Unknown Store",
                address: item.placemark.title,
                coordinate: placemarkLocation?.coordinate,
                distanceMeters: location.flatMap { origin in
                    placemarkLocation?.distance(from: origin)
                },
                mapKitPlaceId: StoreCatalog.mapItemIdentifier(
                    name: item.name ?? "Unknown Store",
                    coordinate: placemarkLocation?.coordinate
                )
            )
        }
    }
}

struct PriceEntryDraft {
    var capturedAt: Date = .now
    var itemName: String = ""
    var priceText: String = ""
    var selectedUnit: UnitType?
    var storeChainName: String?
    var storeChainExplicitlySelected = false
    var storeLocationName: String = ""
    var storeAddress: String = ""
    var storeCoordinate: CLLocationCoordinate2D?
    var storePlaceId: String?
    var imageData: Data?
    var ocrText: String = ""
    var confidence: Float?
    var quantity: Decimal?
    var priceCandidates: [PriceCandidate] = []

    var parsedPrice: Decimal? {
        Decimal(string: priceText.replacingOccurrences(of: ",", with: "."))
    }

    var canSave: Bool {
        guard
            !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let parsedPrice,
            parsedPrice > 0,
            selectedUnit != nil,
            storeChainExplicitlySelected
        else {
            return false
        }

        return true
    }
}

@MainActor
struct PriceEntryRepository {
    let context: ModelContext

    func seedChainsIfNeeded() throws {
        let existing = try context.fetch(FetchDescriptor<StoreChain>())
        guard existing.isEmpty else {
            return
        }

        for chain in StoreCatalog.commonChains where chain.name != "Unknown" {
            context.insert(StoreChain(name: chain.name, aliases: chain.aliases))
        }
        try context.save()
    }

    func saveEntry(from draft: PriceEntryDraft) throws {
        guard
            let unit = draft.selectedUnit,
            let parsedPrice = draft.parsedPrice,
            draft.canSave
        else {
            return
        }

        let chainRecord = try chain(named: draft.storeChainName)
        let locationRecord = try locationRecord(for: draft, chainId: chainRecord?.id)
        let normalized = PriceParsingService.normalize(price: parsedPrice, unit: unit, quantity: draft.quantity)
        let photoPath = try persistPhotoData(draft.imageData, suggestedName: draft.capturedAt)

        let entry = PriceEntry(
            capturedAt: draft.capturedAt,
            itemNameRaw: draft.itemName,
            itemNameNormalized: normalizeItemName(draft.itemName),
            priceValue: parsedPrice,
            unitType: unit,
            unitQuantityValue: draft.quantity,
            normalizedUnitPriceValue: normalized?.0,
            normalizedUnitType: normalized?.1,
            storeChainId: chainRecord?.id,
            storeLocationId: locationRecord?.id,
            storeChainNameSnapshot: draft.storeChainName,
            storeLocationNameSnapshot: draft.storeLocationName.isEmpty ? nil : draft.storeLocationName,
            storeCoordinateLat: draft.storeCoordinate?.latitude,
            storeCoordinateLon: draft.storeCoordinate?.longitude,
            photoAssetId: photoPath,
            ocrText: draft.ocrText.isEmpty ? nil : draft.ocrText,
            confidence: draft.confidence
        )

        context.insert(entry)
        try context.save()
    }

    func cheapestEntries(for itemName: String, normalizedUnitType: UnitType) throws -> [PriceEntry] {
        let normalizedName = normalizeItemName(itemName)
        let descriptor = FetchDescriptor<PriceEntry>(
            predicate: #Predicate<PriceEntry> { entry in
                entry.itemNameNormalized == normalizedName && entry.normalizedUnitType == normalizedUnitType
            },
            sortBy: [SortDescriptor(\.normalizedUnitPriceValue, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func cheapestEntries(for itemName: String, chainId: UUID, normalizedUnitType: UnitType) throws -> [PriceEntry] {
        let normalizedName = normalizeItemName(itemName)
        let descriptor = FetchDescriptor<PriceEntry>(
            predicate: #Predicate<PriceEntry> { entry in
                entry.itemNameNormalized == normalizedName &&
                entry.normalizedUnitType == normalizedUnitType &&
                entry.storeChainId == chainId
            },
            sortBy: [SortDescriptor(\.normalizedUnitPriceValue, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func priceHistory(for locationId: UUID, itemName: String) throws -> [PriceEntry] {
        let normalizedName = normalizeItemName(itemName)
        let descriptor = FetchDescriptor<PriceEntry>(
            predicate: #Predicate<PriceEntry> { entry in
                entry.storeLocationId == locationId && entry.itemNameNormalized == normalizedName
            },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func chain(named name: String?) throws -> StoreChain? {
        guard let name, name != "Unknown" else {
            return nil
        }

        let chainName = name
        let descriptor = FetchDescriptor<StoreChain>(
            predicate: #Predicate { $0.name == chainName }
        )

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let aliases = StoreCatalog.commonChains.first(where: { $0.name == chainName })?.aliases ?? [chainName]
        let chain = StoreChain(name: chainName, aliases: aliases)
        context.insert(chain)
        return chain
    }

    private func locationRecord(for draft: PriceEntryDraft, chainId: UUID?) throws -> StoreLocation? {
        guard !draft.storeLocationName.isEmpty else {
            return nil
        }

        let locationName = draft.storeLocationName
        let descriptor = FetchDescriptor<StoreLocation>(
            predicate: #Predicate { $0.displayName == locationName }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.chainId = chainId
            return existing
        }

        let location = StoreLocation(
            chainId: chainId,
            displayName: locationName,
            address: draft.storeAddress.isEmpty ? nil : draft.storeAddress,
            latitude: draft.storeCoordinate?.latitude,
            longitude: draft.storeCoordinate?.longitude,
            mapKitPlaceId: draft.storePlaceId
        )
        context.insert(location)
        return location
    }

    private func persistPhotoData(_ data: Data?, suggestedName: Date) throws -> String {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = String(Int(suggestedName.timeIntervalSince1970))
        let fileURL = directory.appendingPathComponent("scan-\(timestamp).jpg")

        if let data {
            try data.write(to: fileURL, options: .atomic)
        } else if !FileManager.default.fileExists(atPath: fileURL.path) {
            try Data().write(to: fileURL, options: .atomic)
        }

        return fileURL.path
    }

    private func normalizeItemName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
