import Foundation

public struct ReminderTime: Codable, Equatable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }
}

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var weekday: ReminderTime?
    public var saturday: ReminderTime?
    public var catechism: ReminderTime?

    public init(weekday: ReminderTime? = nil, saturday: ReminderTime? = nil, catechism: ReminderTime? = nil) {
        self.weekday = weekday
        self.saturday = saturday
        self.catechism = catechism
    }
}

public struct PlannedReminder: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case weekday, saturday, resurfaced, catechism
    }

    public let kind: Kind
    public let date: Date
    public let body: String
    public let sermonID: UUID?
    public let page: Int?
    public let attribution: String?
}

public enum ReminderPlanner {
    public static func plan(settings: ReminderSettings, now: Date, calendar: Calendar,
                            entries: [JournalEntry], days: Int = 14, seed: UInt64 = 0) -> [PlannedReminder] {
        guard days > 0, settings != ReminderSettings() else { return [] }
        let today = calendar.startOfDay(for: now)
        let entries = entries.filter { !$0.cards.isEmpty }.sorted {
            ($0.serviceDate, $0.id.uuidString) > ($1.serviceDate, $1.id.uuidString)
        }
        let weeks = Dictionary(grouping: entries) { lastSunday(onOrBefore: $0.serviceDate, calendar: calendar) }
        let earlierLines = settings.weekday == nil ? [:] : resurfacing(weeks, calendar: calendar, seed: seed)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d, yyyy"

        var requests: [PlannedReminder] = []
        for offset in 0..<days {
            guard requests.count < 60,
                  let day = calendar.date(byAdding: .day, value: offset, to: today) else { break }
            var daily: [PlannedReminder] = []
            if let date = fireDate(on: day, time: settings.catechism, after: now, calendar: calendar) {
                daily.append(PlannedReminder(kind: .catechism, date: date, body: "Continue today's catechism session.",
                                             sermonID: nil, page: nil, attribution: nil))
            }

            let weekday = calendar.component(.weekday, from: day)
            let sunday = lastSunday(onOrBefore: day, calendar: calendar)
            let time = weekday == 7 ? settings.saturday : settings.weekday
            if weekday != 1, let sermon = weeks[sunday]?.first,
               let date = fireDate(on: day, time: time, after: now, calendar: calendar) {
                if weekday == 4, let line = earlierLines[sunday] {
                    let attribution = [formatter.string(from: line.date), line.preacher].compactMap { $0 }
                    daily.append(PlannedReminder(kind: .resurfaced, date: date, body: line.text,
                                                 sermonID: line.id, page: nil, attribution: attribution.joined(separator: " · ")))
                } else {
                    let index = weekday == 7 ? sermon.cards.count - 1 : min(weekday - 2, sermon.cards.count - 1)
                    let fallback = weekday == 7 ? "Prepare for the Lord's Day." : "Return to this week's sermon."
                    daily.append(PlannedReminder(kind: weekday == 7 ? .saturday : .weekday, date: date,
                                                 body: normalizedNoteField(sermon.cards[index].text) ?? fallback,
                                                 sermonID: sermon.id, page: index + 1, attribution: nil))
                }
            }
            requests.append(contentsOf: daily.sorted { $0.date < $1.date }.prefix(60 - requests.count))
        }
        return requests
    }

    private static func fireDate(on day: Date, time: ReminderTime?, after now: Date, calendar: Calendar) -> Date? {
        // If spring-forward skips this time, use the first valid local time that day.
        guard let time, (0..<24).contains(time.hour), (0..<60).contains(time.minute),
              let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day,
                                       matchingPolicy: .nextTime),
              calendar.isDate(date, inSameDayAs: day), date > now else { return nil }
        return date
    }

    private struct Line {
        let id: UUID
        let date: Date
        let preacher: String?
        let text: String
    }

    /// Compute a week's choice even when the window starts midweek so refills
    /// keep the same line and can avoid the preceding week's choice.
    private static func resurfacing(_ weeks: [Date: [JournalEntry]], calendar: Calendar, seed: UInt64) -> [Date: Line] {
        var archive: [Line] = []
        var previous: String?
        var result: [Date: Line] = [:]
        for sunday in weeks.keys.sorted() {
            let choices = archive.filter { $0.text != previous }
            let weights = choices.map { line in
                let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: line.date), to: sunday).day ?? 7
                return max(1, 52 / max(1, age / 7))
            }
            let total = weights.reduce(0, +)
            if total > 0 {
                // SplitMix64 mixing keeps the draw reproducible across processes.
                var random = UInt64(bitPattern: Int64(sunday.timeIntervalSince1970)) &+ seed &+ 0x9e3779b97f4a7c15
                random = (random ^ (random >> 30)) &* 0xbf58476d1ce4e5b9
                random = (random ^ (random >> 27)) &* 0x94d049bb133111eb
                var pick = Int((random ^ (random >> 31)) % UInt64(total))
                for (line, weight) in zip(choices, weights) {
                    if pick < weight {
                        result[sunday] = line
                        previous = line.text
                        break
                    }
                    pick -= weight
                }
            }
            for sermon in weeks[sunday] ?? [] {
                archive.append(contentsOf: sermon.keyLines.map {
                    Line(id: sermon.id, date: sermon.serviceDate, preacher: sermon.preacher, text: $0)
                })
            }
        }
        return result
    }
}
