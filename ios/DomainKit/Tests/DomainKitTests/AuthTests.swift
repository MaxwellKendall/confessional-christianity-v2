import Testing
@testable import DomainKit

@Suite struct EmailAddressTests {
    @Test(arguments: [
        ("parent@example.com", "parent@example.com"),
        ("  Parent@Example.COM \n", "parent@example.com"),
        ("first.last+cc@sub.example.co.uk", "first.last+cc@sub.example.co.uk"),
    ])
    func normalizesValidAddresses(raw: String, expected: String) {
        #expect(EmailAddress.normalized(raw) == expected)
    }

    @Test(arguments: [
        "", "   ", "parent", "parent@", "@example.com", "parent@example",
        "parent@@example.com", "par ent@example.com", "parent@example..com",
        "parent@.example.com", "parent@example.com.",
    ])
    func rejectsInvalidAddresses(raw: String) {
        #expect(EmailAddress.normalized(raw) == nil)
    }
}

@Suite struct OTPCodeTests {
    @Test(arguments: [
        ("123456", "123456"),
        (" 123 456 ", "123456"),
        ("123-456", "123456"),
        ("012345", "012345"),
    ])
    func normalizesSixDigitCodes(raw: String, expected: String) {
        #expect(OTPCode.normalized(raw) == expected)
    }

    @Test(arguments: ["", "12345", "1234567", "12345a", "abcdef", "１２３４５６"])
    func rejectsAnythingButSixAsciiDigits(raw: String) {
        #expect(OTPCode.normalized(raw) == nil)
    }
}

@Suite struct AuthMachineTests {
    let user = AuthUser(id: "8c1f3b52-0000-4000-8000-000000000001", email: "parent@example.com")

    @Test func startsRestoring() {
        #expect(AuthMachine().phase == .restoring)
    }

    @Test func restoreWithoutSessionIsGuest() {
        var m = AuthMachine()
        do { let accepted = m.handle(.restored(nil)); #expect(accepted) }
        #expect(m.phase == .guest)
        #expect(!m.phase.isSignedIn)
    }

    @Test func restoreWithSessionIsSignedIn() {
        var m = AuthMachine()
        m.handle(.restored(user))
        #expect(m.phase == .signedIn(user))
        #expect(m.phase.user == user)
    }

    @Test func happyPathGuestToSignedIn() {
        var m = AuthMachine(phase: .guest)
        do { let accepted = m.handle(.requestCode("  Parent@Example.com ")); #expect(accepted) }
        #expect(m.phase == .sendingCode(email: "parent@example.com"))
        do { let accepted = m.handle(.codeSent); #expect(accepted) }
        #expect(m.phase == .awaitingCode(email: "parent@example.com"))
        do { let accepted = m.handle(.submitCode("123 456")); #expect(accepted) }
        #expect(m.phase == .verifying(email: "parent@example.com", code: "123456"))
        do { let accepted = m.handle(.verified(user)); #expect(accepted) }
        #expect(m.phase == .signedIn(user))
        #expect(m.lastError == nil)
    }

    @Test func invalidEmailStaysGuestWithError() {
        var m = AuthMachine(phase: .guest)
        do { let accepted = m.handle(.requestCode("not-an-email")); #expect(!accepted) }
        #expect(m.phase == .guest)
        #expect(m.lastError == .invalidEmail)
    }

    @Test func sendFailureReturnsToGuestWithError() {
        var m = AuthMachine(phase: .sendingCode(email: "parent@example.com"))
        m.handle(.sendFailed("rate limited"))
        #expect(m.phase == .guest)
        #expect(m.lastError == .sendFailed("rate limited"))
    }

    @Test func invalidCodeStaysAwaitingWithError() {
        var m = AuthMachine(phase: .awaitingCode(email: "parent@example.com"))
        do { let accepted = m.handle(.submitCode("12")); #expect(!accepted) }
        #expect(m.phase == .awaitingCode(email: "parent@example.com"))
        #expect(m.lastError == .invalidCode)
    }

    @Test func verifyFailureReturnsToAwaitingSameEmail() {
        var m = AuthMachine(phase: .verifying(email: "parent@example.com", code: "123456"))
        m.handle(.verifyFailed("Token has expired or is invalid"))
        #expect(m.phase == .awaitingCode(email: "parent@example.com"))
        #expect(m.lastError == .verifyFailed("Token has expired or is invalid"))
    }

    @Test func resendFromAwaitingCodeIsAllowed() {
        var m = AuthMachine(phase: .awaitingCode(email: "parent@example.com"))
        do { let accepted = m.handle(.requestCode("other@example.com")); #expect(accepted) }
        #expect(m.phase == .sendingCode(email: "other@example.com"))
    }

    @Test func codeCanBeEnteredForAnEmailWithoutSendingAgain() {
        // e.g. the app was relaunched after the email arrived.
        var m = AuthMachine(phase: .guest)
        do { let accepted = m.handle(.enterCodeFor(" Parent@Example.com")); #expect(accepted) }
        #expect(m.phase == .awaitingCode(email: "parent@example.com"))

        var other = AuthMachine(phase: .awaitingCode(email: "old@example.com"))
        do { let accepted = other.handle(.enterCodeFor("parent@example.com")); #expect(accepted) }
        #expect(other.phase == .awaitingCode(email: "parent@example.com"))

        var bad = AuthMachine(phase: .guest)
        do { let accepted = bad.handle(.enterCodeFor("nope")); #expect(!accepted) }
        #expect(bad.phase == .guest)
        #expect(bad.lastError == .invalidEmail)
    }

    @Test func cancelFromAwaitingCodeIsGuest() {
        var m = AuthMachine(phase: .awaitingCode(email: "parent@example.com"))
        do { let accepted = m.handle(.cancel); #expect(accepted) }
        #expect(m.phase == .guest)
    }

    @Test func newRequestClearsPreviousError() {
        var m = AuthMachine(phase: .guest)
        m.handle(.requestCode("bad"))
        m.handle(.requestCode("parent@example.com"))
        #expect(m.lastError == nil)
    }

    @Test func signOutAndSessionEndFromSignedInAreGuest() {
        var a = AuthMachine(phase: .signedIn(user))
        do { let accepted = a.handle(.signedOut); #expect(accepted) }
        #expect(a.phase == .guest)

        var b = AuthMachine(phase: .signedIn(user))
        do { let accepted = b.handle(.sessionEnded); #expect(accepted) }
        #expect(b.phase == .guest)
    }

    @Test func sessionUpdateWhileSignedInReplacesUser() {
        var m = AuthMachine(phase: .signedIn(user))
        let renamed = AuthUser(id: user.id, email: "new@example.com")
        do { let accepted = m.handle(.sessionUpdated(renamed)); #expect(accepted) }
        #expect(m.phase == .signedIn(renamed))
    }

    @Test func eventsOutOfOrderAreIgnored() {
        var m = AuthMachine(phase: .guest)
        do { let accepted = m.handle(.codeSent); #expect(!accepted) }
        do { let accepted = m.handle(.submitCode("123456")); #expect(!accepted) }
        do { let accepted = m.handle(.verified(user)); #expect(!accepted) }
        #expect(m.phase == .guest)

        var busy = AuthMachine(phase: .sendingCode(email: "parent@example.com"))
        do { let accepted = busy.handle(.requestCode("parent@example.com")); #expect(!accepted) }
        #expect(busy.phase == .sendingCode(email: "parent@example.com"))

        var signedIn = AuthMachine(phase: .signedIn(user))
        do { let accepted = signedIn.handle(.requestCode("parent@example.com")); #expect(!accepted) }
        #expect(signedIn.phase == .signedIn(user))
    }

    @Test func externalSignInFromAnyPhaseIsAccepted() {
        // A session arriving from elsewhere (e.g. restored late, or a future
        // Sign in with Apple) always wins over an in-flight email flow.
        for start in [AuthPhase.restoring, .guest, .awaitingCode(email: "parent@example.com")] {
            var m = AuthMachine(phase: start)
            do { let accepted = m.handle(.sessionUpdated(user)); #expect(accepted) }
            #expect(m.phase == .signedIn(user))
        }
    }
}
