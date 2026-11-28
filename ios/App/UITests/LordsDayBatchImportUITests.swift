import XCTest

final class LordsDayBatchImportUITests: XCTestCase {
    @MainActor
    private func launch(_ scene: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-SkipNotificationOffer", "YES", "-LordsDayBatchFixture", scene]
        app.launch()
        return app
    }

    @MainActor
    func testMergeAndSplitRestoreTheProposedGroups() {
        let app = launch("groups")
        let draft = app.buttons["batch.finish"]
        XCTAssertTrue(draft.waitForExistence(timeout: 15))
        XCTAssertEqual(draft.label, "Draft 3 sermons")

        app.buttons["batch.merge.0"].tap()
        XCTAssertEqual(draft.label, "Draft 2 sermons")

        let split = app.buttons["Start a new sermon at page 3"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        split.tap()
        XCTAssertEqual(draft.label, "Draft 3 sermons")
    }

    @MainActor
    func testDraggingPageMovesItBetweenSermons() {
        let app = launch("groups")
        let page = app.buttons["batch.page.1"].firstMatch
        let destination = app.staticTexts["Gospel Partnership"]
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        XCTAssertTrue(destination.exists)
        page.press(forDuration: 0.8, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(app.staticTexts["No title on the page"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGuessedDateOpensEditDetailsOnDate() {
        let app = launch("queue")
        let progress = app.staticTexts["batch.queue.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        XCTAssertTrue(progress.label.contains("1 of 3"))

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A Tale of Two Prayers")).firstMatch
        XCTAssertTrue(row.exists)
        if !row.isHittable { app.swipeUp() }
        row.tap()
        let date = app.buttons["batch.queue.guessedDate"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        date.tap()
        XCTAssertTrue(app.staticTexts["sermonDetails.dateGuess"].waitForExistence(timeout: 10))
    }
}
