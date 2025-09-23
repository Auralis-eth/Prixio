import Foundation

/// User preferences
struct UserPreferences: Sendable, Codable {
    var defaultCurrency: String = "USD"
    var defaultUnit: String = "Imperial"
    var allowLocationTracking: Bool = false
    var shareDataAnonymously: Bool = false
    var notificationSettings: NotificationSettings = NotificationSettings()
}
