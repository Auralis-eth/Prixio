//
//  ScanMode.swift
//  Prixio
//

import Foundation

/// The capture mode for the scanner screen.
///
/// `priceTag` is the default flow for shelf tags, product signs, and single-product prices.
/// `receipt` captures basket-level images (camera, photo library, or imported PDF) into a
/// `ReceiptCapture` for later review instead of running single-tag price extraction.
enum ScanMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case priceTag
    case receipt

    var id: String { rawValue }

    /// Short label shown in the scanner mode picker.
    var title: String {
        switch self {
        case .priceTag:
            return "Price Tag"
        case .receipt:
            return "Receipt"
        }
    }

    /// Guidance shown under the store chip while the user is aiming the camera.
    var capturePrompt: String {
        switch self {
        case .priceTag:
            return "Point at the price tag."
        case .receipt:
            return "Point at the receipt."
        }
    }
}
