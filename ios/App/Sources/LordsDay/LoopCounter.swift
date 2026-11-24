// Counts the Lord's Day loop (TKL-947) through DomainKit's LoopAnalytics: a
// sermon kept, a day of the week opened, a card shared. What each event sends
// is fixed (and tested) in LoopAnalytics.captureRequest. Sending happens off
// the main actor and never blocks or fails anything on screen.
import Foundation
import os
import DomainKit

enum LoopCounter {
    private static let log = Logger(subsystem: "com.confessionalchristianity.app", category: "analytics")

    private static let analytics: LoopAnalytics = {
        #if DEBUG
        let environment = "debug"
        #else
        let environment = "release"
        #endif
        return LoopAnalytics(config: LoopAnalyticsConfig(info: Bundle.main.infoDictionary ?? [:], environment: environment))
    }()

    static func record(_ event: LoopEvent) {
        Task.detached(priority: .utility) {
            report(event.name, await analytics.record(event))
        }
    }

    /// Once per local day, however often the feed comes on screen.
    static func dayOpened() {
        Task.detached(priority: .utility) {
            if let status = await analytics.recordDayOpened() { report(LoopEvent.dayOpened.name, status) }
        }
    }

    /// The event name and HTTP status only (the UI test reads these lines).
    private static func report(_ name: String, _ status: Int?) {
        log.notice("loop event \(name, privacy: .public) status \(status.map(String.init) ?? "not sent", privacy: .public)")
    }
}
