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
        // Cognito EMAIL_OTP sign-in codes are 8 digits; sign-up codes are 6.
        ("12345678", "12345678"),
        ("1234 5678", "12345678"),
        ("0123-4567", "01234567"),
    ])
    func normalizesSixOrEightDigitCodes(raw: String, expected: String) {
        #expect(OTPCode.normalized(raw) == expected)
    }

    @Test(arguments: ["", "12345", "1234567", "123456789", "12345a", "abcdef", "１２３４５６", "1234567a"])
    func rejectsAnythingButSixOrEightAsciiDigits(raw: String) {
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

    @Test func signUpCodeThenAutoSignIn() {
        // A first-time email: Cognito sends a 6-digit sign-up code; once it is
        // confirmed the app signs in automatically.
        var m = AuthMachine(phase: .guest)
        m.handle(.requestCode("new@example.com"))
        do { let accepted = m.handle(.signUpCodeSent); #expect(accepted) }
        #expect(m.phase == .awaitingCode(email: "new@example.com", purpose: .signUp))
        do { let accepted = m.handle(.submitCode("123456")); #expect(accepted) }
        #expect(m.phase == .verifying(email: "new@example.com", code: "123456", purpose: .signUp))
        do { let accepted = m.handle(.signUpConfirmed); #expect(accepted) }
        #expect(m.phase == .signingIn(email: "new@example.com"))
        #expect(!m.phase.isSignedIn)
        do { let accepted = m.handle(.verified(user)); #expect(accepted) }
        #expect(m.phase == .signedIn(user))
        #expect(m.lastError == nil)
    }

    @Test func returningEmailGetsSignInCode() {
        var m = AuthMachine(phase: .guest)
        m.handle(.requestCode("parent@example.com"))
        m.handle(.codeSent)
        #expect(m.phase == .awaitingCode(email: "parent@example.com", purpose: .signIn))
        do { let accepted = m.handle(.submitCode("1234 5678")); #expect(accepted) }
        #expect(m.phase == .verifying(email: "parent@example.com", code: "12345678", purpose: .signIn))
    }

    @Test func wrongSignUpCodeKeepsPurpose() {
        var m = AuthMachine(phase: .awaitingCode(email: "new@example.com", purpose: .signUp))
        m.handle(.submitCode("000000"))
        do { let accepted = m.handle(.verifyFailed("Invalid code")); #expect(accepted) }
        #expect(m.phase == .awaitingCode(email: "new@example.com", purpose: .signUp))
        #expect(m.lastError == .verifyFailed("Invalid code"))
    }

    @Test func autoSignInFailureAfterSignUpIsGuestWithError() {
        // The account exists now; asking for a new code takes the sign-in path.
        var m = AuthMachine(phase: .signingIn(email: "new@example.com"))
        do { let accepted = m.handle(.verifyFailed("Auto sign-in failed")); #expect(accepted) }
        #expect(m.phase == .guest)
        #expect(m.lastError == .verifyFailed("Auto sign-in failed"))
    }

    @Test func signUpConfirmedOnlyWhileVerifyingASignUp() {
        var signIn = AuthMachine(phase: .verifying(email: "parent@example.com", code: "12345678", purpose: .signIn))
        do { let accepted = signIn.handle(.signUpConfirmed); #expect(!accepted) }
        var guest = AuthMachine(phase: .guest)
        do { let accepted = guest.handle(.signUpConfirmed); #expect(!accepted) }
        do { let accepted = guest.handle(.signUpCodeSent); #expect(!accepted) }
        #expect(guest.phase == .guest)
    }

    @Test func cancelFromSignUpCodeIsGuest() {
        var m = AuthMachine(phase: .awaitingCode(email: "new@example.com", purpose: .signUp))
        do { let accepted = m.handle(.cancel); #expect(accepted) }
        #expect(m.phase == .guest)
    }
}

/// TKL-950 review: the code is sent to the address captured when Send was
/// tapped, so the prompt and Verify must use that address, not the text field.
@Suite struct AuthPendingEmailTests {
    @Test func carriesTheAddressTheCodeWasSentTo() {
        var machine = AuthMachine(phase: .guest)
        #expect(machine.phase.pendingEmail == nil)
        machine.handle(.requestCode("First@Example.com"))
        #expect(machine.phase.pendingEmail == "first@example.com")
        // A slow send: an edited field can't retarget the pending code.
        #expect(machine.handle(.enterCodeFor("second@example.com")) == false)
        #expect(machine.handle(.requestCode("second@example.com")) == false)
        machine.handle(.codeSent)
        #expect(machine.phase.pendingEmail == "first@example.com")
        machine.handle(.submitCode("123456"))
        #expect(machine.phase == .verifying(email: "first@example.com", code: "123456"))
        #expect(machine.phase.pendingEmail == "first@example.com")
        machine.handle(.verified(AuthUser(id: "u", email: "first@example.com")))
        #expect(machine.phase.pendingEmail == nil)
    }

    @Test func carriesPendingEmailThroughSignUpAutoSignIn() {
        var machine = AuthMachine(phase: .guest)
        machine.handle(.requestCode("New@Example.com"))
        #expect(machine.phase.pendingEmail == "new@example.com")
        machine.handle(.signUpCodeSent)
        #expect(machine.phase.pendingEmail == "new@example.com")
        machine.handle(.submitCode("123456"))
        #expect(machine.phase.pendingEmail == "new@example.com")
        machine.handle(.signUpConfirmed)
        #expect(machine.phase == .signingIn(email: "new@example.com"))
        #expect(machine.phase.pendingEmail == "new@example.com")
        machine.handle(.verified(AuthUser(id: "u", email: "new@example.com")))
        #expect(machine.phase.pendingEmail == nil)
    }
}
