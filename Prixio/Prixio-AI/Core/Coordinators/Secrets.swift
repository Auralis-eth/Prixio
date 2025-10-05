import Foundation

/// Centralized secrets holder. Replace with secure injection for production.
public enum Secrets {
    /// Google Places API Key injected via code. Replace at build time or via CI.
    public static let googlePlacesAPIKey: String = "" // TODO: Set via CI or local config
}
