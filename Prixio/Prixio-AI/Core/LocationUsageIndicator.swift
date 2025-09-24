import SwiftUI
import Foundation

struct LocationUsageIndicator: View {
    let isActive: () async -> Bool
    @State private var active: Bool = false

    var body: some View {
        Group {
            if active {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                    Text("Using your location")
                        .font(.footnote)
                        .fontWeight(.semibold)
                }
                .padding(8)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut, value: active)
            }
        }
        .task {
            active = await isActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationServiceStateDidChange)) { _ in
            Task {
                active = await isActive()
            }
        }
    }
}
