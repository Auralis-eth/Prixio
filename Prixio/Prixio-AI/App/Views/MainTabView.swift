import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator

    var body: some View {
        ZStack {
            TabView {
                PriceListView()
                    .tabItem {
                        Image(systemName: "list.bullet")
                        Text("Prices")
                    }

                CameraView()
                    .tabItem {
                        Image(systemName: "camera")
                        Text("Scan")
                    }

                StoresView()
                    .tabItem {
                        Image(systemName: "storefront")
                        Text("Stores")
                    }

                SettingsRootView()
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
            }

            VStack {
                HStack {
                    Spacer()
                    LocationUsageIndicator {
                        if let svc = appCoordinator.getService(for: .location) as? LocationService {
                            let snap = await svc.snapshot()
                            return snap.isActivelyUpdating
                        }
                        return false
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

