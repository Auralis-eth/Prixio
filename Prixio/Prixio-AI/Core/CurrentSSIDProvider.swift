import Foundation
#if canImport(NetworkExtension)
import NetworkExtension
#endif
#if canImport(SystemConfiguration)
import SystemConfiguration.CaptiveNetwork
#endif

/// Basic stub that attempts to read the currently connected Wi‑Fi SSID.
/// On iOS, access is restricted and may require special entitlements or conditions.
/// This provider best-effort returns the SSID if available; otherwise returns nil.
final class CurrentSSIDProvider: @unchecked Sendable {
    static let shared = CurrentSSIDProvider()
    private init() {}

    /// Attempts to obtain the current SSID using the best available mechanism.
    /// Returns nil when unavailable or when permissions/entitlements are missing.
    func currentSSID() async -> String? {
        // Prefer NetworkExtension when available (iOS 14+), requires specific entitlements
        #if canImport(NetworkExtension)
        if #available(iOS 14.0, *) {
            if let ssid = await fetchSSIDUsingNetworkExtension() {
                return ssid
            }
        }
        #endif

        // Fallback: CaptiveNetwork (deprecated and often restricted)
        #if canImport(SystemConfiguration)
        if let ssid = fetchSSIDUsingCaptiveNetwork() {
            return ssid
        }
        #endif

        return nil
    }

    // MARK: - Private helpers

    #if canImport(NetworkExtension)
    @available(iOS 14.0, *)
    private func fetchSSIDUsingNetworkExtension() async -> String? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.ssid)
            }
        }
    }
    #endif

    #if canImport(SystemConfiguration)
    // Using deprecated CaptiveNetwork API as a last resort. This may return nil on modern iOS.
    private func fetchSSIDUsingCaptiveNetwork() -> String? {
        guard let interfaces = CNCopySupportedInterfaces() as? [CFString] else { return nil }
        for interface in interfaces {
            if let dict = CNCopyCurrentNetworkInfo(interface) as? [String: AnyObject],
               let ssid = dict[kCNNetworkInfoKeySSID as String] as? String {
                return ssid
            }
        }
        return nil
    }
    #endif
}
