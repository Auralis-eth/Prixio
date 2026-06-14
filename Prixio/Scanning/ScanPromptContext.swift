//
//  ScanPromptContext.swift
//  Prixio
//

import Foundation

struct ScanPromptContext: Equatable, Sendable {
    var storeName: String?
    var expectedItemName: String?

    static let none = ScanPromptContext()

    var isEmpty: Bool {
        storeName?.isEmpty != false && expectedItemName?.isEmpty != false
    }
}
