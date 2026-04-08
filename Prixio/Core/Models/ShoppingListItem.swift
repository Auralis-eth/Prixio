import Foundation
import SwiftData

@Model
final class ShoppingListItem {
    var id: UUID
    var itemKey: String
    var displayName: String
    var quantityNote: String?
    var isDone: Bool
    var doneAt: Date?
    var createdAt: Date

    var list: ShoppingList?

    init(
        id: UUID = UUID(),
        itemKey: String,
        displayName: String,
        quantityNote: String? = nil,
        isDone: Bool = false,
        doneAt: Date? = nil,
        createdAt: Date = .now,
        list: ShoppingList? = nil
    ) {
        self.id = id
        self.itemKey = itemKey
        self.displayName = displayName
        self.quantityNote = quantityNote
        self.isDone = isDone
        self.doneAt = doneAt
        self.createdAt = createdAt
        self.list = list
    }
}
