import SwiftData
import SwiftUI

@main
struct PrixioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [PriceEntry.self, StoreChain.self, StoreLocation.self])
    }
}
