import DomainKit
import Foundation
import SwiftData
import UserNotifications

struct ReminderRoute: Equatable, Sendable {
    let id = UUID()
    let kind: PlannedReminder.Kind
    let sermonID: UUID?
    let page: Int?

    init?(_ payload: [AnyHashable: Any]) {
        guard let value = payload["reminderKind"] as? String, let kind = PlannedReminder.Kind(rawValue: value) else {
            return nil
        }
        self.kind = kind
        sermonID = (payload["sermonID"] as? String).flatMap(UUID.init(uuidString:))
        page = payload["page"] as? Int
    }
}

@MainActor @Observable
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    private static let prefix = "local-reminder."
    private static let legacyID = "daily-practice-reminder"
    private static let settingsKey = "ReminderSettings"
    private static let offeredKey = "SermonReminderPermissionOffered"
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var context: ModelContext?
    private var needsPlan = false
    private var planning = false
    private var needsPermissionOffer = false
    private(set) var isReady = false
    private(set) var settings = ReminderSettings()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    var route: ReminderRoute?

    func install() { center.delegate = self }

    func update(_ settings: ReminderSettings) {
        self.settings = settings
        saveSettings()
        refresh()
    }

    func refresh(in context: ModelContext? = nil, keptSermon: Bool = false) {
        if let context { self.context = context }
        needsPlan = true
        needsPermissionOffer = needsPermissionOffer || keptSermon
        guard !planning else { return }
        planning = true
        Task {
            while needsPlan {
                needsPlan = false
                await replan()
            }
            planning = false
        }
    }

    private func replan() async {
        let pending = await center.pendingNotificationRequests()
        if let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(ReminderSettings.self, from: data) {
            settings = saved
        } else {
            let legacy = pending.first { $0.identifier == Self.legacyID }?.trigger as? UNCalendarNotificationTrigger
            if let hour = legacy?.dateComponents.hour {
                settings.catechism = ReminderTime(hour: hour, minute: legacy?.dateComponents.minute ?? 0)
            }
            saveSettings()
        }

        authorization = await center.notificationSettings().authorizationStatus
        isReady = true
        if needsPermissionOffer {
            needsPermissionOffer = false
            if !defaults.bool(forKey: Self.offeredKey), !defaults.bool(forKey: "SkipNotificationOffer") {
                defaults.set(true, forKey: Self.offeredKey)
                if authorization == .notDetermined {
                    _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                    authorization = await center.notificationSettings().authorizationStatus
                }
            }
        }

        let allowed = authorization == .authorized || authorization == .provisional || authorization == .ephemeral
        let calendar = Calendar.current
        var entries: [JournalEntry] = []
        var preserveSermonRequests = false
        if allowed, settings.weekday != nil || settings.saturday != nil {
            if let context, let journal = try? LordsDayJournal(store: LordsDayStore(context: context), calendar: calendar) {
                entries = journal.entries
            } else {
                // A failed read should leave enabled sermon reminders intact.
                preserveSermonRequests = true
            }
        }
        let plan = allowed ? ReminderPlanner.plan(settings: settings, now: Date(), calendar: calendar, entries: entries) : []
        let requests = plan.map { Self.request(for: $0, calendar: calendar) }
        let plannedIDs = Set(requests.map(\.identifier))
        let obsolete = pending.map(\.identifier).filter { id in
            if preserveSermonRequests {
                if settings.weekday != nil, id.hasPrefix(Self.prefix + "weekday.") { return false }
                if settings.saturday != nil, id.hasPrefix(Self.prefix + "saturday.") { return false }
            }
            return id == Self.legacyID || (id.hasPrefix(Self.prefix) && !plannedIDs.contains(id))
        }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                NSLog("Could not schedule reminder: %@", error.localizedDescription)
            }
        }
    }

    private func saveSettings() {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
    }

    private static func request(for reminder: PlannedReminder, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        switch reminder.kind {
        case .weekday: content.title = "This week's sermon"
        case .saturday: content.title = "Prepare for the Lord's Day"
        case .resurfaced: content.title = "From an earlier Sunday"
        case .catechism: content.title = "Time to catechize"
        }
        content.body = reminder.body
        content.subtitle = reminder.attribution ?? ""
        content.sound = .default
        var payload: [String: Any] = ["reminderKind": reminder.kind.rawValue]
        payload["sermonID"] = reminder.sermonID?.uuidString
        payload["page"] = reminder.page
        content.userInfo = payload
        // Pin the resolved instant, including which occurrence of an hour was
        // selected on a fall-back day. Foreground and time changes re-plan it.
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = utc.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: reminder.date)
        components.calendar = utc
        components.timeZone = utc.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let slot = reminder.kind == .resurfaced ? PlannedReminder.Kind.weekday : reminder.kind
        let id = "\(prefix)\(slot.rawValue).\(Int(reminder.date.timeIntervalSince1970))"
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let route = ReminderRoute(response.notification.request.content.userInfo)
        await MainActor.run { self.route = route }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    #if DEBUG
    func fire(_ reminder: PlannedReminder, calendar: Calendar) {
        route = ReminderRoute(Self.request(for: reminder, calendar: calendar).content.userInfo)
    }
    #endif
}
