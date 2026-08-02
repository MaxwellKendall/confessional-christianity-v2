// Daily local-notification reminder to continue today's catechism — one of
// the native-only additions the implementation plan calls out to defend
// against App Store 4.2 (Minimum Functionality) risk: a habit-forming tool,
// not just a content viewer. No push infrastructure needed — entirely local.
import Foundation
import UserNotifications

enum PracticeReminderScheduler {
    static let requestIdentifier = "daily-practice-reminder"

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Schedules (or replaces) a repeating daily reminder at the given time.
    static func scheduleDaily(hour: Int, minute: Int, programTitle: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Time to catechize"
        content.body = "Continue today's session in \(programTitle)."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }
}
