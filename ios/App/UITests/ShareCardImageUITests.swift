// TKL-1060: Share on a Lord's Day card opens the share sheet with the card as
// an image (so "Save Image" is offered), not just its text. Each test leaves a
// screenshot of the sheet in the simulator's tmp directory and as an attachment.
import XCTest

final class ShareCardImageUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor private func shareSheet(fixture: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LordsDayFeedFixture", fixture, "-SkipNotificationOffer", "YES", "-EsvOffline", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Share this card"].firstMatch.waitForExistence(timeout: 20))
        // The image renders off the main thread as the card appears; give it a beat.
        sleep(2)
        let share = try XCTUnwrap(app.buttons.matching(identifier: "Share this card").allElementsBoundByIndex.first { $0.isHittable })
        share.tap()
        let saveImage = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save Image'")).firstMatch
        XCTAssertTrue(saveImage.waitForExistence(timeout: 10), "the share sheet offers no Save Image: it isn't sharing an image")
        sleep(1)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "share-sheet-\(fixture)"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("share-sheet-\(fixture).png"))
        return app
    }

    /// Tapping Copy puts the card on the pasteboard; check its words from the host
    /// afterwards with `xcrun simctl pbpaste "CC iPhone 17 Pro"` (reading it here
    /// would raise the paste permission prompt).
    @MainActor func testQuoteCardSharesAnImage() throws {
        let app = try shareSheet(fixture: "quote")
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        sleep(1)
    }

    @MainActor func testVerseCardSharesAnImage() throws {
        _ = try shareSheet(fixture: "verse")
    }
}
