import SwiftUI
import CoreLocation

struct SettingsRootView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    
    var body: some View {
        NavigationView {
            Form {
                NavigationLink("Location & Privacy") {
                    LocationPrivacySettingsView(
                        authorizationStatusText: {
                            guard let svc = appCoordinator.getService(for: .location) as? LocationService else {
                                return "Unknown"
                            }
                            return await withCheckedContinuation { continuation in
                                Task {
                                    let status = await svc.snapshot().authorizationStatus
                                    continuation.resume(returning: mapAuthorizationStatus(status))
                                }
                            }
                        },
                        accuracyStatusText: {
                            guard let svc = appCoordinator.getService(for: .location) as? LocationService else {
                                return "Unknown"
                            }
                            return await withCheckedContinuation { continuation in
                                Task {
                                    let accuracy = await svc.snapshot().accuracyAuthorization
                                    continuation.resume(returning: mapAccuracyAuthorization(accuracy))
                                }
                            }
                        },
                        isTrackingAllowed: {
                            guard let svc = appCoordinator.getService(for: .location) as? LocationService else {
                                return false
                            }
                            return await svc.getAllowLocationTracking()
                        },
                        setTrackingAllowed: { allowed in
                            guard let svc = appCoordinator.getService(for: .location) as? LocationService else {
                                return
                            }
                            await svc.setAllowLocationTracking(allowed)
                        },
                        requestPrecise: {
                            guard let svc = appCoordinator.getService(for: .location) as? LocationService else {
                                return
                            }
                            await svc.requestPreciseLocationIfNeeded()
                        }
                    )
                    .navigationTitle("Location & Privacy")
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private func mapAuthorizationStatus(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        case .authorized: return "Authorized" // Deprecated but still included
        @unknown default: return "Unknown"
        }
    }
    
    private func mapAccuracyAuthorization(_ accuracy: CLAccuracyAuthorization) -> String {
        switch accuracy {
        case .fullAccuracy: return "Precise"
        case .reducedAccuracy: return "Approximate"
        @unknown default: return "Unknown"
        }
    }
}

#Preview {
    SettingsRootView()
        .environmentObject(AppCoordinator())
}
