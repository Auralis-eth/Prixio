import SwiftUI

struct PriceListView: View {
    var body: some View {
        NavigationView {
            List {
                Text("Price entries will appear here")

                Section {
                    NavigationLink("Settings") {
                        SettingsRootView()
                    }
                }
            }
            .navigationTitle("Recent Prices")
        }
    }
}
