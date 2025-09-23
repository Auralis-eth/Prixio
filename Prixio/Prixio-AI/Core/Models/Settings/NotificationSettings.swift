import Foundation

struct NotificationSettings: Sendable, Codable {
    var priceAlerts: Bool = true
    var dealNotifications: Bool = true
    var syncNotifications: Bool = true
    var enablePushNotifications: Bool = true
    var enableEmailNotifications: Bool = false
}
