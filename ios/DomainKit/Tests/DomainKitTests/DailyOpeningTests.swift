import Foundation
import Testing
@testable import DomainKit

@Suite struct DailyOpeningTests {
    @Test @MainActor func playsOnceAcrossLaunchesAndResetsAtLocalMidnight() throws {
        let suite = "DailyOpeningTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21)))

        #expect(DailyOpening.claim(in: defaults, now: midnight.addingTimeInterval(-3600), calendar: calendar))
        let nextLaunch = try #require(UserDefaults(suiteName: suite))
        #expect(!DailyOpening.claim(in: nextLaunch, now: midnight.addingTimeInterval(-1), calendar: calendar))
        #expect(DailyOpening.claim(in: nextLaunch, now: midnight, calendar: calendar))
        #expect(!DailyOpening.claim(in: defaults, now: midnight.addingTimeInterval(3600), calendar: calendar))
    }
}
