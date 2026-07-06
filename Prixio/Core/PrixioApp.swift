import SwiftData
import SwiftUI

@main
struct PrixioApp: App {
    @StateObject private var navigationModel = AppNavigationModel()

    /// True when the host app is launched in-process by a unit-test bundle. UI tests launch the app
    /// out-of-process, so this stays false for them.
    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            if isRunningUnitTests {
                // Skip the full UI during unit tests so AVFoundation/camera startup (and other
                // launch-time work) does not destabilize @MainActor SwiftData tests on the simulator.
                Color.clear
            } else {
                MainView()
                    .environmentObject(navigationModel)
            }
        }
        .modelContainer(
            for: [
                PriceEntry.self,
                StoreChain.self,
                StoreLocation.self,
                ShoppingList.self,
                ShoppingListItem.self,
                ReceiptCapture.self,
                ReceiptLineItem.self,
                ExpenseEntry.self,
                IncomeEntry.self,
                RecurringExpenseRule.self,
                RestockRule.self,
                FlyerPriceRecord.self
            ]
        )
    }
}
