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

    /// TKL-1057: header controls (Review cards pill + camera) and footer actions
    /// (Read full passage + Share) sit fully inside the card's inner padding on
    /// verse and quote cards, with nothing clipped at the card edge.
    @MainActor func testHeaderAndFooterFitInsideCard() throws {
        let app = launch([
            "-LordsDayFeedFixture", "verse",
            "-LordsDayFeedShowHeader", "YES",
            "-LordsDayFeedPendingReviews", "4",
        ])
        assertTodayOnScreen(app)
        let window = app.windows.firstMatch.frame
        // Card border is 16pt from each side; inner padding is 20pt inside the border (= 36pt from screen edges).
        let innerMinX = window.minX + 36 - 1
        let innerMaxX = window.maxX - 36 + 1
        // Bottom border is 104pt above screen bottom; inner bottom is 20pt above that (= 124pt above screen bottom).
        let innerMaxY = window.maxY - 124 + 1

        // The paging stack keeps neighbouring cards loaded, so each control exists once per card: take the on-screen one.
        func onScreen(_ query: XCUIElementQuery) -> XCUIElement {
            _ = query.firstMatch.waitForExistence(timeout: 10)
            let matches = query.allElementsBoundByIndex
            return matches.first { window.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) } ?? query.firstMatch
        }
        let review = onScreen(app.buttons.matching(identifier: "lordsDay.review"))
        let capture = onScreen(app.buttons.matching(identifier: "lordsDay.capture"))
        let journal = onScreen(app.buttons.matching(identifier: "lordsDay.journal"))
        let readFull = onScreen(app.buttons.matching(identifier: "lordsDay.readFullPassage"))
        let share = onScreen(app.buttons.matching(NSPredicate(format: "label == 'Share this card'")))

        XCTAssertTrue(review.waitForExistence(timeout: 10), "Review cards pill missing")
        XCTAssertTrue(capture.waitForExistence(timeout: 10), "Camera button missing")
        XCTAssertTrue(journal.waitForExistence(timeout: 10), "Journal button missing")
        XCTAssertTrue(readFull.waitForExistence(timeout: 10), "Read full passage missing")
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Share button missing")

        for (name, el) in [("review", review), ("journal", journal), ("capture", capture), ("readFullPassage", readFull), ("share", share)] {
            XCTAssertTrue(el.isHittable, "\(name) is not hittable")
            XCTAssertGreaterThanOrEqual(el.frame.minX, innerMinX, "\(name) crosses card inner left edge: \(el.frame)")
            XCTAssertLessThanOrEqual(el.frame.maxX, innerMaxX, "\(name) crosses card inner right edge: \(el.frame)")
            XCTAssertLessThanOrEqual(el.frame.maxY, innerMaxY, "\(name) crosses card inner bottom edge: \(el.frame)")
        }
        // Footer actions share one horizontal row and do not overlap each other.
        XCTAssertLessThan(readFull.frame.maxX, share.frame.minX, "footer actions overlap: read=\(readFull.frame) share=\(share.frame)")
        XCTAssertEqual(readFull.frame.midY, share.frame.midY, accuracy: 4, "footer actions are not in one row")
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
