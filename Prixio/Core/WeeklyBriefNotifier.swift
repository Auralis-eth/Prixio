import Foundation
import UserNotifications

/// Schedules the weekly household brief as a local notification.
///
/// Uses *provisional* authorization: briefs are delivered quietly to Notification
/// Center without ever showing a permission prompt, and the user can upgrade or
/// silence them from the notification itself. Content is composed on-device at
/// schedule time (each app launch), so the delivered brief is "as of the last time
/// the app ran" — refreshing it in the background would need a BGAppRefreshTask
/// capability, deliberately deferred (see Docs/HouseholdAutopilotDesign.md).
struct WeeklyBriefNotifier {
    static let notificationIdentifier = "weekly-household-brief"
    /// Sunday at 5pm local time — before the common start-of-week shop.
    static let deliveryWeekday = 1
    static let deliveryHour = 17
    /// Notification bodies should be glanceable; the card shows the full brief.
    static let maxFactsInBody = 3

    /// Replaces any pending brief with one built from the given facts, aimed at the
    /// next delivery slot. No facts (or no authorization) simply clears the pending
    /// notification — an empty brief is silence, not an empty ping.
    func scheduleNextBrief(facts: [String]) async {
        let center = UNUserNotificationCenter.current()
        let authorized = (try? await center.requestAuthorization(
            options: [.alert, .provisional]
        )) ?? false

        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        guard authorized, !facts.isEmpty else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your household this week"
        content.body = facts.prefix(Self.maxFactsInBody).joined(separator: " ")

        var components = DateComponents()
        components.weekday = Self.deliveryWeekday
        components.hour = Self.deliveryHour
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        try? await center.add(UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        ))
    }
}
