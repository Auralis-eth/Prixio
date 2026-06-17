//
//  ScanPromptContext.swift
//  Prixio
//

import Foundation

// A plain Sendable value type carried across the nonisolated extraction boundary, so it must
// not pick up the module's main-actor-default isolation (else `.none` cannot be used as a
// default argument in the nonisolated UIImage.extractPriceInformation entry point).
nonisolated struct ScanPromptContext: Equatable, Sendable {
    var storeName: String?
    var expectedItemName: String?

    static let none = ScanPromptContext()

    var isEmpty: Bool {
        storeName?.isEmpty != false && expectedItemName?.isEmpty != false
    }
}
