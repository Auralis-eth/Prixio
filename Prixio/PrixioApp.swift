import SwiftUI
import SwiftData

@main
struct PrixioApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appCoordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appCoordinator)
                .modelContainer(for: [PriceEntry.self, Product.self, Store.self])
                .task {
                    appCoordinator.initializeApp()
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .background:
                        appCoordinator.appDidEnterBackground()
                    case .active:
                        appCoordinator.appWillEnterForeground()
                    case .inactive:
                        // You could flush pending saves or prepare for background here if needed
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
