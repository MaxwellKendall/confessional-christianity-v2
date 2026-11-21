import XCTest

final class ConfessionsReaderTests: XCTestCase {
    @MainActor
    func testCitationsInLightAppearance() {
        checkCitations(dark: false)
    }

    @MainActor
    func testCitationsInDarkAppearance() {
        checkCitations(dark: true)
    }

    @MainActor
    private func checkCitations(dark: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-VerseReaderFixture", "citations",
            "-VerseReaderFixtureAppearance", dark ? "dark" : "light",
            "-reader.dark", "NO",
            "-reader.showConfessionMarks", "YES"
        ]
        app.launch()

        let verse = app.staticTexts["The Spirit itself beareth witness with our spirit, that we are the children of God:"]
        app.swipeUp()
        XCTAssertTrue(verse.exists)
        let seal = app.buttons["Confessions, 4 citations"]
        XCTAssertTrue(seal.waitForExistence(timeout: 10))
        seal.tap()
        XCTAssertTrue(app.staticTexts["Romans 8:16 is a proof text for 4 clauses."].exists)
        XCTAssertTrue(app.buttons["All"].exists)
        XCTAssertTrue(app.buttons["WCF"].exists)
        XCTAssertTrue(app.buttons["WLC"].exists)
        XCTAssertTrue(app.buttons["Heidelberg"].exists)
        capture("sheet", app: app)
        let first = app.buttons["reader-clause-WCoF-18-2"]
        XCTAssertTrue(first.isHittable)
        first.swipeLeft()
        let dots = app.descendants(matching: .any)["Clause 2 of 4"]
        XCTAssertTrue(dots.waitForExistence(timeout: 5))
        app.buttons["WLC"].tap()
        let card = app.buttons["reader-clause-WLC-80"]
        XCTAssertTrue(card.exists)
        card.tap()
        XCTAssertTrue(app.staticTexts["You came from Romans 8:16"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["and bearing witness with their spirits that they are the children of God,"].exists)
        XCTAssertTrue(app.staticTexts["“The Spirit itself beareth witness with our spirit, that we are the children of God:”"].exists)
        let question = "Can true believers be infallibly assured that they are in the estate of grace, and that they shall persevere therein unto salvation?"
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", question)).firstMatch.exists)
        XCTAssertTrue(app.buttons["reader-clause-share"].exists)
        capture("clause", app: app)
        app.buttons["Back to the verse"].tap()
        XCTAssertTrue(seal.waitForExistence(timeout: 5))
        XCTAssertTrue(verse.isHittable)
        capture("return", app: app)

        if !dark {
            seal.tap()
            app.buttons["WLC"].tap()
            app.buttons["reader-clause-WLC-80"].tap()
            app.buttons["reader-clause-share"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["Copy"].firstMatch.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testBundledVerseCanOpenCitations() {
        let app = XCUIApplication()
        app.launchArguments = ["-VerseReaderFixture", "bundled-citations", "-reader.showConfessionMarks", "YES"]
        app.launch()
        let seal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confessions,'")).firstMatch
        XCTAssertTrue(seal.waitForExistence(timeout: 10))
        seal.tap()
        XCTAssertTrue(app.staticTexts["CITED IN THE CONFESSIONS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Proverbs 31:23 is a proof text for 1 clause."].exists)
        XCTAssertFalse(app.buttons["All"].exists)
        app.buttons["reader-clause-WLC-127"].tap()
        XCTAssertTrue(app.staticTexts["You came from Proverbs 31:23"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The honor which inferiors'")).firstMatch.exists)
    }

    @MainActor
    func testUncitedVerseHasNoSeal() {
        let app = XCUIApplication()
        app.launchArguments = ["-VerseReaderFixture", "uncited"]
        app.launch()
        XCTAssertTrue(app.buttons["In context"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confessions'")).firstMatch.exists)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
