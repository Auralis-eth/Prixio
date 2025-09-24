import SwiftUI
import Foundation
import SwiftData

struct LocationPrivacySettingsView: View {
    // Inputs
    let authorizationStatusText: () async -> String
    let accuracyStatusText: () async -> String
    let isTrackingAllowed: () async -> Bool

    // Actions
    let setTrackingAllowed: (Bool) async -> Void
    let requestPrecise: () async -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]

    @State private var allowTracking: Bool = false
    @State private var authorizationStatus: String = "Loading…"
    @State private var accuracyStatus: String = "Loading…"

    var body: some View {
        Form {
            Toggle("Allow Location Features", isOn: $allowTracking)
                .onChange(of: allowTracking) { newValue in
                    Task {
                        await setTrackingAllowed(newValue)
                    }
                    // Persist to UserPreferences via SwiftData
                    if let user = users.first {
                        var prefs = user.preferences ?? UserPreferences()
                        prefs.allowLocationTracking = newValue
                        user.preferences = prefs
                        try? modelContext.save()
                    }
                }
            
            Section("Current Status") {
                LabeledContent("Authorization") {
                    Text(authorizationStatus)
                }
                LabeledContent("Accuracy") {
                    Text(accuracyStatus)
                }
            }
            
            Section("Precision") {
                Button("Request Precise for Nearby Stores") {
                    Task {
                        await requestPrecise()
                    }
                }
            }
        }
        .navigationTitle("Location & Privacy")
        .task {
            // Seed toggle from stored UserPreferences if available; otherwise fall back to service
            if let prefValue = users.first?.preferences?.allowLocationTracking {
                allowTracking = prefValue
            } else {
                allowTracking = await isTrackingAllowed()
            }
            authorizationStatus = await authorizationStatusText()
            accuracyStatus = await accuracyStatusText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationServiceStateDidChange)) { _ in
            Task {
                // Keep UI aligned with stored preference when present; otherwise reflect service state
                if let prefValue = users.first?.preferences?.allowLocationTracking {
                    allowTracking = prefValue
                } else {
                    allowTracking = await isTrackingAllowed()
                }
                authorizationStatus = await authorizationStatusText()
                accuracyStatus = await accuracyStatusText()
            }
        }
    }
}

#Preview {
    NavigationView {
        LocationPrivacySettingsView(
            authorizationStatusText: { "Authorized Always" },
            accuracyStatusText: { "Full Accuracy" },
            isTrackingAllowed: { true },
            setTrackingAllowed: { allowed in print("Set tracking allowed to \(allowed)") },
            requestPrecise: { print("Requested precise location") }
        )
    }
}
