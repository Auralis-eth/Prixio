import SwiftData
import SwiftUI

@main
struct PrixioApp: App {
    @StateObject private var navigationModel = AppNavigationModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(navigationModel)
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
