//
//  PriceEntryDraft.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation
import Foundation

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
    var review: OCRReview = .clean

    var parsedPrice: Decimal? {
        Decimal(string: priceText.replacingOccurrences(of: ",", with: "."))
    }

    var canSave: Bool {
        guard
            !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let parsedPrice,
            parsedPrice > 0,
            selectedUnit != nil,
            storeChainExplicitlySelected,
            !review.issues.contains(.receiptCapture)
        else {
            return false
        }

        return true
    }
}
