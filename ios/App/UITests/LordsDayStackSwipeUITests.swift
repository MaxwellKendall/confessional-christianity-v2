// TKL-1096: the Lord's Day landing stack swipes sideways between sermons in place,
// while a vertical drag still scrolls the page. Fixture data only; sends no events.
import XCTest

final class LordsDayStackSwipeUITests: XCTestCase {
    private let shots = URL(fileURLWithPath: "/tmp/factory/TKL-1096/uitest", isDirectory: true)

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
    }

    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
    }

    @MainActor func testSwipingTheStackMovesBetweenSermonsAndVerticalDragStillScrolls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SkipNotificationOffer", "YES", "-StartTab", "lordsDay", "-LordsDayLandingFixture", "week"]
        app.launch()

        let header = app.staticTexts["lordsDay.stackHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 20))
        let thisWeek = NSPredicate(format: "label == %@", "THIS WEEK'S SERMON")
        func headerIs(_ predicate: NSPredicate, _ message: String) {
            let met = XCTNSPredicateExpectation(predicate: predicate, object: header)
            XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: 5), .completed, "\(message); header is \(header.label)")
        }
        headerIs(thisWeek, "opens on this week")
        let deck = app.descendants(matching: .any)["lordsDay.deck"]
        XCTAssertTrue(deck.exists)

        // Right at the newest sermon: it resists, nothing changes and nothing opens.
        deck.swipeRight()
        headerIs(thisWeek, "swiping past the newest sermon moved the stack")

        // Left: the previous sermon, in place.
        deck.swipeLeft()
        sleep(1)
        shot("swiped-left")
        headerIs(NSPredicate(format: "label == %@", "NOV 15"), "swiping left didn't move to the previous sermon")
        XCTAssertTrue(app.descendants(matching: .any)["lordsDay.landing"].exists, "the swipe left the landing page")

        // And back.
        deck.swipeRight()
        headerIs(thisWeek, "swiping right didn't come back to this week")
        shot("swiped-back")

        // A vertical drag on the stack scrolls the page instead of moving the stack.
        let before = deck.frame.minY
        deck.swipeUp()
        XCTAssertLessThan(deck.frame.minY, before - 40, "vertical drag on the stack did not scroll the page")
        headerIs(thisWeek, "a vertical drag moved the stack to another sermon")
        shot("scrolled")
    }
}
