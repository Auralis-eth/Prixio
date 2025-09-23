import SwiftUI

struct ErrorView: View {
    let error: Error

    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Something went wrong")
                .font(.title)
                .padding()

            Text(error.localizedDescription)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            Button("Retry") {
                // Retry initialization
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
