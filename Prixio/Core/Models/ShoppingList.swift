import Foundation
import SwiftData

@Model
final class ShoppingList {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    var items: [ShoppingListItem]

    init(
        id: UUID = UUID(),
        name: String = "This trip",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isArchived: Bool = false,
        items: [ShoppingListItem] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.items = items
    }
}
