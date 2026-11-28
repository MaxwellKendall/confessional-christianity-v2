// TKL-1115: saving a sermon's details in the reel keeps the reel on that sermon's cover.
// Two sermons share last Sunday (the sample week, then an older note); the reel opens on
// the older one, its title is edited, and the reel must still show its cover afterwards,
// not a card of the other sermon. Seeded data only; sends no events.
import XCTest

final class LordsDayReelEditDetailsUITests: XCTestCase {
    private let shots = URL(fileURLWithPath: "/tmp/factory/TKL-1115/uitest", isDirectory: true)

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
    }

    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
    }

    @MainActor func testSavingDetailsInTheReelStaysOnThatSermonsCover() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SeedSermonWeek", "YES", "-SeedSameDaySermon", "YES", "-StartTab", "lordsDay",
                               "-LordsDayOpenReel", "1", "-SkipNotificationOffer", "YES", "-EsvOffline", "YES"]
        app.launch()

        let title = app.staticTexts["lordsDay.reel.title"]
        let subtitle = app.staticTexts["lordsDay.reel.subtitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the reel didn't open")
        XCTAssertEqual(title.label, "The Morning Lesson")
        XCTAssertTrue(subtitle.label.hasSuffix("1 OF 2"), "not on the cover: \(subtitle.label)")
        shot("before")

        let edit = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "lordsDay.cover.editDetails", "Edit sermon details")).firstMatch
        if edit.waitForExistence(timeout: 5) { edit.tap() }
        else { app.staticTexts["Edit"].firstMatch.tap() }
        let field = app.textFields["sermonDetails.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the details sheet didn't open")
        field.tap()
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 2)
        field.typeText(clear + "Retitled at the Door")
        app.buttons["sermonDetails.done"].tap()

        let retitled = NSPredicate(format: "label == %@", "Retitled at the Door")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: retitled, object: title)], timeout: 5),
                       .completed, "the reel moved off the edited sermon; title is \(title.label)")
        sleep(1)
        shot("after")
        XCTAssertEqual(title.label, "Retitled at the Door")
        XCTAssertTrue(subtitle.label.hasSuffix("1 OF 2"), "left the cover: \(subtitle.label)")
    }
}
