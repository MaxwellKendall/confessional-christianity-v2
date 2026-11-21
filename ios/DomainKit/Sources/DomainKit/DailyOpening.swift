import Foundation

public enum DailyOpening {
    private static let lastOpeningKey = "LastTitlePageOpening"

    /// Records the first opening in the user's current calendar day.
    @MainActor
    public static func claim(
        in defaults: UserDefaults, now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        if let lastOpening = defaults.object(forKey: lastOpeningKey) as? Date,
           calendar.isDate(lastOpening, inSameDayAs: now) {
            return false
        }
        defaults.set(now, forKey: lastOpeningKey)
        return true
    }
}
