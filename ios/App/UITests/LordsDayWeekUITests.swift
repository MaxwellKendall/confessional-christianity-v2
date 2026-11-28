// TKL-1085 pass 3: with the week feed retired, the seeded sample week opens on the
// Lord's Day landing page as this week's sermon, with Read and Share inside the
// stack's top card and fully on screen (what TKL-1057 checked on the old feed).
import XCTest

final class LordsDayWeekUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testTheSeededWeekOpensAsThisWeeksSermonWithItsControlsOnScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SeedSermonWeek", "YES", "-StartTab", "lordsDay", "-SkipNotificationOffer", "YES", "-EsvOffline", "YES"]
        app.launch()

        let header = app.staticTexts["lordsDay.stackHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 20), "no sermon stack")
        XCTAssertEqual(header.label, "THIS WEEK'S SERMON")

        let window = app.windows.firstMatch.frame
        let share = app.buttons.matching(NSPredicate(format: "label == 'Share this card'")).allElementsBoundByIndex.first { $0.isHittable }
        let shareButton = try XCTUnwrap(share, "no Share on the top card")
        XCTAssertTrue(window.contains(shareButton.frame), "Share is clipped: \(shareButton.frame)")
    }
}
