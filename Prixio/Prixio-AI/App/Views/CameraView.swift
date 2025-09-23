import SwiftUI

struct CameraView: View {
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "camera.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.gray)

                Text("Camera functionality")
                Text("Tap to scan receipts")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Scan Receipt")
        }
    }
}
