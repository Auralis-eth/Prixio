//
//  StoreChain.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation
import SwiftData

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
