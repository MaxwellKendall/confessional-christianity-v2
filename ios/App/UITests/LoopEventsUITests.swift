// TKL-947: drives the real Lord's Day screens on a simulator so each of the
// loop's three events is sent the way a person would cause it. The app logs
// each send's HTTP status ("loop event <name> status <code>", subsystem
// com.confessionalchristianity.app, category analytics); read them with
// `xcrun simctl spawn <device> log show --last 5m --predicate 'category == "analytics"'`.
import XCTest

final class LoopEventsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // An empty last-counted day, so this launch counts the day afresh.
        app.launchArguments = arguments + ["-SkipNotificationOffer", "YES", "-EsvOffline", "YES", "-LoopAnalyticsLastDayOpened", ""]
        app.launch()
        return app
    }

    /// The feed opens at today's card (lords_day_day_opened); Share on it opens the share sheet (lords_day_card_shared).
    @MainActor func testOpeningTheWeekAndSharingACard() throws {
        let app = launch(["-LordsDayFeedFixture", "key_point"])
        XCTAssertTrue(app.buttons["Share this card"].firstMatch.waitForExistence(timeout: 15))
        // Every card has a Share button; only today's is on screen.
        let share = try XCTUnwrap(app.buttons.matching(identifier: "Share this card").allElementsBoundByIndex.first { $0.isHittable })
        share.tap()
        // Leave the share sheet up long enough for the send to finish.
        sleep(3)
    }

    /// "Add N cards to my week" keeps the sermon (lords_day_sermon_kept).
    @MainActor func testKeepingASermon() throws {
        let app = launch(["-LordsDayReviewFixture", "complete"])
        let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label ENDSWITH 'to my week'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: add)
        wait(for: [enabled], timeout: 20)
        add.tap()
        sleep(3)
    }
}
