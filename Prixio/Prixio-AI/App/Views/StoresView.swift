import SwiftUI

struct StoresView: View {
    var body: some View {
        NavigationView {
            List {
                Section("Detection") {
                    NavigationLink("Detect Nearby Store") {
                        StoreDetectionView()
                    }
                }

                Section("Your Stores") {
                    Text("Stores will appear here")
                }
            }
            .navigationTitle("Nearby Stores")
        }
    }
}
