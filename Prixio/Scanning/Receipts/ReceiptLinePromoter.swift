//
//  ReceiptLinePromoter.swift
//  Prixio
//
//  Promotes a reviewed, trustworthy receipt line into a durable PriceEntry. This is the
//  ONLY path from receipt data into price history — keeping promotion explicit and
//  per-line ensures receipts never silently pollute price comparison.
//

import Foundation
import SwiftData

@MainActor
struct ReceiptLinePromoter {
    let context: ModelContext

    /// Persistence hook, overridable in tests to exercise the save-failure rollback path. Defaults to
    /// the real `ModelContext.save()`.
    var persist: (ModelContext) throws -> Void = { try $0.save() }

    /// Creates a `PriceEntry` from a receipt line, stamps the line with the new entry's id, and
    /// saves. Returns `nil` (no write) when the line lacks a usable name or price.
    @discardableResult
    func promote(_ line: ReceiptLineItem, from receipt: ReceiptCapture) throws -> PriceEntry? {
        guard
            let price = line.priceValue,
            price > 0,
            let name = line.itemNameRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else {
            return nil
        }

        // Receipt lines rarely carry a per-weight unit; default to each when the model left it nil.
        let unit = line.unitType ?? .each

        let entry = PriceEntry(
            capturedAt: receipt.purchaseDate ?? receipt.capturedAt,
            itemNameRaw: name,
            itemNameNormalized: ItemKeyNormalizer.normalize(name),
            priceValue: price,
            currencyCode: receipt.currencyCode,
            unitType: unit,
            unitQuantityValue: line.quantityValue,
            storeChainId: receipt.storeChainId,
            storeLocationId: receipt.storeLocationId,
            storeChainNameSnapshot: receipt.storeChainNameSnapshot,
            storeLocationNameSnapshot: receipt.storeLocationNameSnapshot,
            photoAssetId: "",
            parserUsedFoundationModel: true
        )

        context.insert(entry)
        line.promotedPriceEntryId = entry.id
        do {
            try persist(context)
        } catch {
            // Roll back so a failed save leaves no orphan PriceEntry and no false promotion link
            // on the line — the caller can surface the error and the user can retry.
            context.delete(entry)
            line.promotedPriceEntryId = nil
            throw error
        }
        return entry
    }
}
