import SwiftUI

struct MainTabView: View {
    var body: some View {
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
        }
    }
}
