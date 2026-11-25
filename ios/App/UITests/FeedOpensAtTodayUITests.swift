// TKL-1020: the Lord's Day week feed opens at today's card, not Monday's.
// On Sunday and Monday today's card is the first one, so these pass trivially then.
import XCTest

final class FeedOpensAtTodayUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-SkipNotificationOffer", "YES", "-EsvOffline", "YES"]
        app.launch()
        return app
    }

    /// Today's card carries the "Today" day label; it must be the card on screen.
    private func assertTodayOnScreen(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let today = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Today'")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 20), "no Today card", file: file, line: line)
        // Let the first layout settle before reading what is on screen.
        sleep(2)
        XCTAssertTrue(today.isHittable, "today's card is not the one on screen", file: file, line: line)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(CGPoint(x: today.frame.midX, y: today.frame.midY)), "today's label is off screen: \(today.frame)", file: file, line: line)
        // The bug opened on Monday's card: when today isn't Monday (or Sunday), Monday's label must be off screen.
        let weekday = Calendar.current.component(.weekday, from: Date())
        if weekday > 2 {
            let monday = app.staticTexts["Monday"]
            if monday.exists {
                XCTAssertFalse(window.contains(CGPoint(x: monday.frame.midX, y: monday.frame.midY)), "Monday's card is on screen", file: file, line: line)
            }
        }
    }

    @MainActor func testFixtureOpensAtTodaysVerseCard() throws {
        let app = launch(["-LordsDayFeedFixture", "verse"])
        assertTodayOnScreen(app)
        let ref = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'John 3:16'")).firstMatch
        XCTAssertTrue(ref.exists && ref.isHittable, "John 3:16 is not on screen")
        assertRailMatchesToday(app)
    }

    @MainActor func testRealTabOpensAtTodaysCard() throws {
        let app = launch(["-SeedSermonWeek", "YES", "-StartTab", "lordsDay"])
        assertTodayOnScreen(app)
        assertRailMatchesToday(app)
    }

    /// The dot rail says "Card N of M"; N is today's position (Monday = 1, Sunday opens at 1).
    private func assertRailMatchesToday(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let weekday = Calendar.current.component(.weekday, from: Date()) // 1 = Sunday
        let expected = weekday == 1 ? 1 : weekday - 1
        let rail = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Card '")).firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 5), "no dot rail", file: file, line: line)
        XCTAssertTrue(rail.label.hasPrefix("Card \(expected) of"), "rail says \(rail.label), expected card \(expected)", file: file, line: line)
    }
}
