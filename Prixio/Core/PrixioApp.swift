import SwiftData
import SwiftUI

@main
struct PrixioApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(
            for: [
                PriceEntry.self,
                StoreChain.self,
                StoreLocation.self,
                ShoppingList.self,
                ShoppingListItem.self
            ]
        )
    }
}
