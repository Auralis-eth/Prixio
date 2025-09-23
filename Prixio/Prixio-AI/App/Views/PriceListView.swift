import SwiftUI

struct PriceListView: View {
    var body: some View {
        NavigationView {
            List {
                Text("Price entries will appear here")
            }
            .navigationTitle("Recent Prices")
        }
    }
}
