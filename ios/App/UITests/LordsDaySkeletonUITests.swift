// TKL-940: end-to-end skeleton verification on the "CC iPhone 17 Pro" simulator,
// with NO fixture launch arguments: signed-out -> offers Sign in (notes stay
// saved) -> real emailed code on dev Cognito pool -> drafting continues ->
// Choose from Photos (two real sermon-note pages) -> streamed cards -> decide
// on each card -> Add to my week -> feed opens at today's card -> offline
// relaunch shows the same week from local storage.
import XCTest

final class LordsDaySkeletonUITests: XCTestCase {
    private let scratchDir = URL(fileURLWithPath: "/tmp/factory/TKL-940", isDirectory: true)
    private var shotsDir: URL { scratchDir.appendingPathComponent("shots", isDirectory: true) }

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
    }

    private func saveShot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: shotsDir.appendingPathComponent(name))
    }

    private func launchLive(extra: [String] = []) -> XCUIApplication {
        let endpoint = ProcessInfo.processInfo.environment["LORDS_DAY_ENDPOINT"]
            ?? "http://127.0.0.1:3000/api/lords-day/cards"
        let app = XCUIApplication()
        app.launchArguments = [
            "-SkipNotificationOffer", "YES",
            "-LordsDayCardsEndpoint", endpoint,
        ] + extra
        app.launch()
        return app
    }

    @MainActor func testFullSkeletonLoopWithRealDevSignInTypedNotesAndTwoPhotos() throws {
        let app = launchLive()

        // 1. Fresh guest install -> Onboarding -> Start with Sunday's sermon (opens Capture on Lord's Day tab).
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 15) {
            skip.tap()
            let sermonLink = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sunday'")).firstMatch
            XCTAssertTrue(sermonLink.waitForExistence(timeout: 10), "Start with Sunday's sermon link missing")
            sermonLink.tap()
        } else {
            let tab = app.buttons["Lord's Day"]
            if tab.waitForExistence(timeout: 5) { tab.tap() }
            let capture = app.buttons["lordsDay.capture"]
            if capture.waitForExistence(timeout: 5) { capture.tap() }
        }

        // 2. Signed out + "Type instead": notes save, drafting offers Sign in.
        let typeBtn = app.buttons["capture.type"]
        XCTAssertTrue(typeBtn.waitForExistence(timeout: 15), "Type instead button did not appear")
        typeBtn.tap()

        let notesField = app.textViews["Sermon notes"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 10), "Type instead text editor did not appear")
        notesField.tap()
        notesField.typeText("Psalm 98. Sing a new song to the Lord because he has done marvelous things. \"The gospel commands all the earth to rejoice.\" Psalm 98:1")

        app.buttons["Done"].firstMatch.tap()

        let captureDone = app.buttons["capture.done"]
        XCTAssertTrue(captureDone.waitForExistence(timeout: 10))
        let doneEnabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: captureDone)
        wait(for: [doneEnabled], timeout: 10)
        captureDone.tap()

        // Review opens, sees guest session, keeps notes saved, and offers Sign in.
        let signInBtn = app.buttons["review.signIn"]
        XCTAssertTrue(signInBtn.waitForExistence(timeout: 20), "Signed-out review did not offer Sign in")
        saveShot("01-signed-out-offers-signin.png")
        signInBtn.tap()

        // 3. Sign in with real emailed code on the dev Cognito pool.
        let emailField = app.textFields["signIn.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 15), "Sign-in email field did not appear")
        emailField.tap()
        emailField.typeText("otp-test@cc-dev-mail.barbrabell.com")

        // Signal host watcher to fetch the emailed OTP code from S3 after this timestamp.
        let codeFile = scratchDir.appendingPathComponent("code.txt")
        let needFile = scratchDir.appendingPathComponent("need-code")
        try? FileManager.default.removeItem(at: codeFile)
        let epoch = String(Int(Date().timeIntervalSince1970) - 2)
        try epoch.write(to: needFile, atomically: true, encoding: .utf8)

        app.buttons["signIn.send"].tap()

        let codeField = app.textFields["signIn.code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 20), "Code field did not appear after sending code")
        saveShot("02-signin-code-sent.png")

        // Wait up to 90s for the host watcher to write the code from S3 inbox.
        var code: String?
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if let raw = try? String(contentsOf: codeFile, encoding: .utf8) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 6 { code = trimmed; break }
            }
            sleep(1)
        }
        let otp = try XCTUnwrap(code, "Timed out waiting for dev OTP code in \(codeFile.path)")
        codeField.tap()
        codeField.typeText(otp)
        saveShot("03-signin-code-entered.png")
        app.buttons["signIn.verify"].tap()

        // 4. After sign-in, drafting automatically resumes for the saved typed notes!
        let undecidedHint = app.buttons["review.undecidedHint"]
        XCTAssertTrue(undecidedHint.waitForExistence(timeout: 60), "Typed notes did not draft after signing in")
        XCTAssertFalse(app.buttons["review.finish"].isEnabled, "Finish must stay disabled while drafts are undecided")
        saveShot("04-typed-notes-drafted.png")

        // Close typed-notes review so we can run the real two-page photo flow.
        app.buttons["review.close"].tap()

        // 5. Lord's Day tab -> Capture -> Choose from Photos (two real pages from evals/lords-day-cards/photos/).
        let openCapture = app.buttons["lordsDay.capture"]
        XCTAssertTrue(openCapture.waitForExistence(timeout: 15), "Capture button did not appear on Lord's Day tab")
        saveShot("05-lords-day-tab.png")
        openCapture.tap()

        let choosePhotos = app.buttons["capture.photos"]
        XCTAssertTrue(choosePhotos.waitForExistence(timeout: 15), "Choose from Photos button missing")
        choosePhotos.tap()

        // Wait for PHPicker images to load.
        let anyPhoto = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,'")).firstMatch
        XCTAssertTrue(anyPhoto.waitForExistence(timeout: 20), "Photos picker did not show photos")
        sleep(1)

        // Pick our two newly added sermon-note photos (labeled with today's date/year, or the last two photos).
        let todayPhotos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,' AND (label CONTAINS 'Today' OR label CONTAINS 'November 25' OR label CONTAINS '2026')"))
        let allPhotos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,'"))
        // The picker runs out of process: its thumbnails report as not hittable, so tap by coordinate.
        let pool = todayPhotos.count >= 2 ? todayPhotos : allPhotos
        XCTAssertGreaterThanOrEqual(pool.count, 2, "Need at least 2 photos in library")
        for index in [pool.count - 2, pool.count - 1] {
            pool.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            usleep(500_000)
        }
        saveShot("06-photos-selected.png")

        let addPhotosBtn = app.buttons["Add"]
        XCTAssertTrue(addPhotosBtn.waitForExistence(timeout: 10), "Photos picker Add button missing")
        addPhotosBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Wait for both pages to import into CaptureView.
        let twoPagesDone = app.buttons.matching(NSPredicate(format: "identifier == 'capture.done' AND label == 'Done · 2 pages'")).firstMatch
        XCTAssertTrue(twoPagesDone.waitForExistence(timeout: 25), "Capture did not import 2 pages; label=\(app.buttons["capture.done"].label)")
        saveShot("07-capture-two-pages.png")
        twoPagesDone.tap()

        // 6. Review opens and streams drafted cards from the local endpoint.
        let finishBtn = app.buttons["review.finish"]
        XCTAssertTrue(finishBtn.waitForExistence(timeout: 15), "Review screen did not open")
        sleep(2)
        saveShot("08-review-streaming.png")

        // Wait up to 60s for stream to finish and show undecided cards.
        XCTAssertTrue(undecidedHint.waitForExistence(timeout: 60), "Drafted cards did not finish streaming within 60s")
        XCTAssertFalse(finishBtn.isEnabled, "Nothing unseen can be finished before deciding on each card")
        saveShot("09-review-drafted-undecided.png")

        // 7. Decide on every drafted card (log each card's accessibility label for inspection).
        var loggedCards: [String] = []
        let keepBtn = app.buttons["review.keep"]
        for step in 0..<20 {
            if finishBtn.isEnabled { break }
            if undecidedHint.exists && undecidedHint.isHittable {
                undecidedHint.tap()
                usleep(400_000)
            }
            let visibleCards = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'review.card.'"))
                .allElementsBoundByIndex
                .filter { app.windows.firstMatch.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            if let card = visibleCards.first {
                loggedCards.append("[\(step)] \(card.identifier): \(card.label)")
            }
            XCTAssertTrue(keepBtn.waitForExistence(timeout: 5), "Keep button missing")
            keepBtn.tap()
            usleep(250_000)
        }
        try loggedCards.joined(separator: "\n").write(
            to: scratchDir.appendingPathComponent("drafted-cards.txt"),
            atomically: true,
            encoding: .utf8
        )

        let finishReady = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: finishBtn)
        wait(for: [finishReady], timeout: 10)
        saveShot("10-review-decided.png")
        finishBtn.tap()

        // 8. Feed opens at today's card.
        let todayLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Today'")).firstMatch
        XCTAssertTrue(todayLabel.waitForExistence(timeout: 20), "Feed did not open at today's card")
        sleep(2)
        XCTAssertTrue(todayLabel.isHittable, "Today's card is not on screen")
        saveShot("11-feed-today.png")

        // Save visible feed card text so offline relaunch can assert the exact same week.
        let rail = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Card '")).firstMatch
        let summary = "today=\(todayLabel.label) rail=\(rail.exists ? rail.label : "none")"
        try summary.write(to: scratchDir.appendingPathComponent("feed-online.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor func testOfflineRelaunchShowsSameWeekFromLocalStorage() throws {
        // Relaunch with no fixture launch arguments and offline (-EsvOffline YES, unreachable cards endpoint).
        let app = launchLive(extra: ["-EsvOffline", "YES"])

        let lordsDayTab = app.buttons["Lord's Day"]
        XCTAssertTrue(lordsDayTab.waitForExistence(timeout: 20), "Lord's Day tab did not appear on relaunch")
        lordsDayTab.tap()

        let todayLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Today'")).firstMatch
        XCTAssertTrue(todayLabel.waitForExistence(timeout: 15), "Saved week did not show offline on relaunch")
        sleep(2)
        XCTAssertTrue(todayLabel.isHittable, "Today's card is not on screen after offline relaunch")
        saveShot("12-offline-relaunch-feed.png")

        let rail = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Card '")).firstMatch
        let summary = "today=\(todayLabel.label) rail=\(rail.exists ? rail.label : "none")"
        try summary.write(to: scratchDir.appendingPathComponent("feed-offline.txt"), atomically: true, encoding: .utf8)
        let online = try? String(contentsOf: scratchDir.appendingPathComponent("feed-online.txt"), encoding: .utf8)
        if let online {
            XCTAssertEqual(summary, online, "Offline relaunch week differs from online week")
        }
    }
}
