// TKL-928 review regression: Cancel, swipe-dismiss and "Use a different email"
// stay locked while verification or auto sign-in is in flight so a delayed
// completion can't sign the user in behind a dismissed sheet.
import XCTest

final class SignInSheetUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(delaySeconds: String, purpose: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "-SkipNotificationOffer", "YES",
            "-EsvOffline", "YES",
            "-OpenSheet", "settings",
            "-OpenSignIn", "YES",
            "-SignInStubVerifyDelay", delaySeconds,
        ]
        if let purpose {
            args += ["-SignInStubPurpose", purpose]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func sendCode(in app: XCUIApplication, email: String) {
        let emailField = app.textFields["signIn.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 15), "sign-in email field did not appear")
        emailField.tap()
        emailField.typeText(email)

        let sendButton = app.buttons["signIn.send"]
        XCTAssertTrue(sendButton.exists && sendButton.isEnabled)
        sendButton.tap()

        let codeField = app.textFields["signIn.code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "code field did not appear")
    }

    @MainActor func testDelayedSignInLocksCancelAndAccountSwitchUntilComplete() {
        let app = launch(delaySeconds: "3")
        sendCode(in: app, email: "parent@example.com")

        let cancel = app.buttons["signIn.cancel"]
        let differentEmail = app.buttons["signIn.differentEmail"]
        let codeField = app.textFields["signIn.code"]
        let verifyButton = app.buttons["signIn.verify"]

        XCTAssertTrue(cancel.isEnabled, "Cancel should be enabled while awaiting code")
        XCTAssertTrue(differentEmail.isEnabled, "Use a different email should be enabled while awaiting code")

        codeField.tap()
        codeField.typeText("12345678")
        verifyButton.tap()

        // While verification is in flight ("Checking…"), dismissal and account-switch controls must be locked.
        XCTAssertTrue(
            NSPredicate(format: "label == 'Checking…'").evaluate(with: verifyButton) ||
            app.buttons["Checking…"].waitForExistence(timeout: 2),
            "verify button should show Checking…"
        )
        XCTAssertFalse(cancel.isEnabled, "Cancel must be disabled during verification")
        XCTAssertFalse(differentEmail.isEnabled, "Use a different email must be disabled during verification")
        XCTAssertFalse(verifyButton.isEnabled, "Sign in button must be disabled during verification")
        XCTAssertFalse(codeField.isEnabled, "Code field must be disabled during verification")

        // Attempting to swipe down the sheet must not dismiss it while verification is in flight.
        let navBar = app.navigationBars["Sign in"]
        if navBar.exists {
            navBar.swipeDown()
        }
        XCTAssertTrue(verifyButton.exists, "Sheet must stay open while verification is in flight")

        // Once the delayed verification completes, the sheet auto-dismisses and Settings shows the account.
        let accountEmail = app.staticTexts["settings.accountEmail"]
        XCTAssertTrue(accountEmail.waitForExistence(timeout: 10), "Settings should show signed-in email after delayed verification")
        XCTAssertEqual(accountEmail.label, "parent@example.com")
    }

    @MainActor func testDelayedSignUpAutoSignInLocksControlsUntilComplete() {
        let app = launch(delaySeconds: "2", purpose: "signUp")
        sendCode(in: app, email: "new@example.com")

        let cancel = app.buttons["signIn.cancel"]
        let differentEmail = app.buttons["signIn.differentEmail"]
        let codeField = app.textFields["signIn.code"]
        let verifyButton = app.buttons["signIn.verify"]

        codeField.tap()
        codeField.typeText("123456")
        verifyButton.tap()

        // Controls stay locked during code confirmation AND the auto sign-in phase that follows.
        XCTAssertFalse(cancel.isEnabled, "Cancel must be disabled during sign-up verification")
        XCTAssertFalse(differentEmail.isEnabled, "Use a different email must be disabled during sign-up verification")
        sleep(2)
        // Still locked during auto sign-in (or already signed in if timing was fast).
        if verifyButton.exists {
            XCTAssertFalse(cancel.isEnabled, "Cancel must stay disabled during auto sign-in")
            XCTAssertFalse(differentEmail.isEnabled, "Use a different email must stay disabled during auto sign-in")
        }

        let accountEmail = app.staticTexts["settings.accountEmail"]
        XCTAssertTrue(accountEmail.waitForExistence(timeout: 10), "Settings should show signed-in email after auto sign-in")
        XCTAssertEqual(accountEmail.label, "new@example.com")
    }

    @MainActor func testDelayedWrongCodeReEnablesCancelAndAccountSwitch() {
        let app = launch(delaySeconds: "2")
        sendCode(in: app, email: "parent@example.com")

        let cancel = app.buttons["signIn.cancel"]
        let differentEmail = app.buttons["signIn.differentEmail"]
        let codeField = app.textFields["signIn.code"]
        let verifyButton = app.buttons["signIn.verify"]

        codeField.tap()
        codeField.typeText("00000000")
        verifyButton.tap()

        XCTAssertFalse(cancel.isEnabled, "Cancel must be disabled while checking wrong code")
        XCTAssertFalse(differentEmail.isEnabled, "Use a different email must be disabled while checking wrong code")

        let error = app.staticTexts["signIn.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), "Inline error should appear after delayed wrong code")
        XCTAssertTrue(cancel.isEnabled, "Cancel should re-enable after verify failure")
        XCTAssertTrue(differentEmail.isEnabled, "Use a different email should re-enable after verify failure")

        cancel.tap()
        let signInRow = app.buttons["settings.signIn"]
        XCTAssertTrue(signInRow.waitForExistence(timeout: 10), "Canceling after verify failure should return to guest Settings")
    }
}
