import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator

    var body: some View {
        Group {
            switch appCoordinator.appState {
            case .initializing:
                LoadingView()
            case .ready:
                MainTabView()
            case .failed(let error):
                ErrorView(error: error)
            case .terminated:
                Text("App Terminated")
            }
        }
        .animation(.easeInOut, value: appCoordinator.appState)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppCoordinator())
}
