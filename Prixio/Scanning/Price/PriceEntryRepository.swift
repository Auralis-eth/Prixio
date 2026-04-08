//
//  PriceEntryRepository.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import SwiftData
import CoreLocation

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
            itemNameNormalized: ItemKeyNormalizer.normalize(draft.itemName),
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
            confidence: draft.confidence,
            parserReviewStateRaw: draft.review.state.rawValue,
            parserReviewIssuesRaw: draft.review.issues.isEmpty ? nil : draft.review.issues.map(\.rawValue).joined(separator: ","),
            parserUsedFoundationModel: draft.review.usedFoundationModel,
            parserAmbiguityNotesRaw: draft.review.ambiguityNotes.isEmpty ? nil : draft.review.ambiguityNotes.joined(separator: " | ")
        )

        context.insert(entry)
        try context.save()
    }

    func cheapestEntries(for itemName: String, normalizedUnitType: UnitType) throws -> [PriceEntry] {
        let normalizedName = ItemKeyNormalizer.normalize(itemName)
        let descriptor = FetchDescriptor<PriceEntry>(
            predicate: #Predicate<PriceEntry> { entry in
                entry.itemNameNormalized == normalizedName && entry.normalizedUnitType == normalizedUnitType
            },
            sortBy: [SortDescriptor(\.normalizedUnitPriceValue, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func cheapestEntries(for itemName: String, chainId: UUID, normalizedUnitType: UnitType) throws -> [PriceEntry] {
        let normalizedName = ItemKeyNormalizer.normalize(itemName)
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
        let normalizedName = ItemKeyNormalizer.normalize(itemName)
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
}
