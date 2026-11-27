import Foundation
import Testing
@testable import DomainKit

struct ReminderPlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func sermon(_ day: Int, lines: [String] = ["A kept line"], preacher: String? = nil) -> JournalEntry {
        JournalEntry(id: UUID(), serviceDate: date(day), passage: nil, title: nil, preacher: preacher,
                     transcript: nil, cards: lines.map { JournalCard(kind: .keyPoint, body: $0) }, calendar: calendar)
    }

    @Test func weekdaySaturdayGapAndRefill() {
        let settings = ReminderSettings(weekday: .init(hour: 9, minute: 30), saturday: .init(hour: 11))
        let entries = [sermon(1), sermon(8), sermon(22)]
        let first = ReminderPlanner.plan(settings: settings, now: date(1), calendar: calendar, entries: entries)
        #expect(first.count == 12)
        #expect(first.filter { $0.kind == .weekday }.allSatisfy {
            calendar.component(.hour, from: $0.date) == 9 && calendar.component(.minute, from: $0.date) == 30
        })
        #expect(first.filter { $0.kind == .saturday }.map(\.date) == [date(7, 11), date(14, 11)])
        let next = ReminderPlanner.plan(settings: settings, now: date(12), calendar: calendar, entries: entries)
        #expect(next.contains { calendar.isDate($0.date, inSameDayAs: date(23)) })
        #expect(!next.contains { calendar.isDate($0.date, inSameDayAs: date(16)) })
        #expect(ReminderPlanner.plan(settings: .init(), now: date(1), calendar: calendar, entries: entries).isEmpty)
    }

    @Test func resurfacesOneEarlierLineAndDoesNotRepeatAcrossRefills() {
        let settings = ReminderSettings(weekday: .init(hour: 9))
        let first = sermon(1, lines: ["First", "Second"], preacher: "John Smith")
        let second = sermon(8, lines: ["Third"])
        let third = sermon(15)
        let entries = [first, second, third]
        let plan = ReminderPlanner.plan(settings: settings, now: date(1), calendar: calendar,
                                        entries: entries, days: 21, seed: 7)
        let resurfaced = plan.filter { $0.attribution != nil }
        #expect(resurfaced.count == 2)
        #expect(resurfaced.first?.sermonID == first.id)
        #expect(resurfaced.first?.body == "First")

        #expect(resurfaced.first?.attribution == "Mar 1, 2026 · John Smith")
        #expect(resurfaced.first?.body != resurfaced.last?.body)
        let refill = ReminderPlanner.plan(settings: settings, now: date(8), calendar: calendar,
                                          entries: entries, seed: 7)
        #expect(refill == plan.filter { $0.date >= date(8) })
    }

    @Test func capAndDST() {
        let settings = ReminderSettings(catechism: .init(hour: 2, minute: 30))
        let plan = ReminderPlanner.plan(settings: settings, now: date(7), calendar: calendar, entries: [], days: 1000)
        #expect(plan.count == 60)
        #expect(plan[0].date == date(7, 2).addingTimeInterval(1800))
        #expect(plan[1].date == date(8, 3))
        #expect(plan[2].date == date(9, 2).addingTimeInterval(1800))
    }
}
