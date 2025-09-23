import SwiftUI

struct StoresView: View {
    var body: some View {
        NavigationView {
            List {
                Text("Stores will appear here")
            }
            .navigationTitle("Nearby Stores")
        }
    }
}
