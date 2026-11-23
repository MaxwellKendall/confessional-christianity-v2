// Pure sign-in logic for the app's Cognito account (infra/, TKL-850): email
// validation, the emailed code format, and the state machine the app's
// AuthService drives. No networking here — AuthService (app target) performs
// the Amplify calls and feeds their outcomes back in as events, so every
// transition is unit-testable on the host Mac.
//
// A returning email gets an 8-digit sign-in code (Cognito's fixed EMAIL_OTP
// length); a first-time email gets a 6-digit sign-up confirmation code, and
// once it is confirmed the app signs in automatically (`.signingIn`).
import Foundation

public enum EmailAddress {
    /// Trimmed, lowercased address if it looks deliverable, else nil.
    /// Deliberately modest: one "@", a non-empty local part without spaces,
    /// and a dotted domain with no empty labels. Cognito does the real check.
    public static func normalized(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.contains(where: { $0.isWhitespace }) else { return nil }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return nil }
        return email
    }
}

public enum OTPCode {
    /// Sign-up confirmation codes are 6 digits, EMAIL_OTP sign-in codes 8.
    public static let lengths: Set<Int> = [6, 8]

    /// The code with spaces and dashes removed, if it is six or eight ASCII digits.
    public static func normalized(_ raw: String) -> String? {
        let code = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard lengths.contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return code
    }
}

/// What the emailed code is for, which decides the call that checks it.
public enum CodePurpose: Equatable, Sendable {
    /// An existing account: `confirmSignIn` with the 8-digit code.
    case signIn
    /// A first-time email: `confirmSignUp` with the 6-digit code, then auto sign-in.
    case signUp
}

public struct AuthUser: Equatable, Hashable, Sendable {
    public let id: String
    public let email: String?

    public init(id: String, email: String?) {
        self.id = id
        self.email = email
    }
}

public enum AuthPhase: Equatable, Sendable {
    /// Launch: the persisted session hasn't been checked yet.
    case restoring
    case guest
    case sendingCode(email: String)
    case awaitingCode(email: String, purpose: CodePurpose = .signIn)
    case verifying(email: String, code: String, purpose: CodePurpose = .signIn)
    /// Sign-up confirmed; the automatic sign-in that follows is in flight.
    case signingIn(email: String)
    case signedIn(AuthUser)

    public var user: AuthUser? {
        if case .signedIn(let user) = self { return user }
        return nil
    }

    public var isSignedIn: Bool { user != nil }

    /// The address a code is being sent to, or was sent to and is being
    /// entered or verified for. Show and verify this, not an editable field.
    public var pendingEmail: String? {
        switch self {
        case .sendingCode(let email), .awaitingCode(let email, _), .verifying(let email, _, _), .signingIn(let email): email
        default: nil
        }
    }
}

public enum AuthError: Equatable, Sendable {
    case invalidEmail
    case invalidCode
    case sendFailed(String)
    case verifyFailed(String)
}

public enum AuthEvent: Equatable, Sendable {
    /// Result of reading the persisted session at launch.
    case restored(AuthUser?)
    case requestCode(String)
    /// A sign-in code went out (the account exists).
    case codeSent
    /// A sign-up code went out (first time this email is used).
    case signUpCodeSent
    /// Enter a code for `email` without sending one (e.g. after a relaunch).
    case enterCodeFor(String)
    case sendFailed(String)
    case submitCode(String)
    /// The sign-up code was accepted; auto sign-in follows.
    case signUpConfirmed
    case verified(AuthUser)
    case verifyFailed(String)
    case cancel
    case signedOut
    /// The SDK reports the session is gone (expired refresh token, revoked).
    case sessionEnded
    /// The SDK reports a (new or refreshed) session for this user.
    case sessionUpdated(AuthUser)
}

public struct AuthMachine: Equatable, Sendable {
    public private(set) var phase: AuthPhase
    public private(set) var lastError: AuthError?

    public init(phase: AuthPhase = .restoring) {
        self.phase = phase
    }

    /// Applies `event`; returns false (and leaves the phase alone) when the
    /// event isn't valid in the current phase or its input is rejected.
    @discardableResult
    public mutating func handle(_ event: AuthEvent) -> Bool {
        switch (phase, event) {
        case (.restoring, .restored(let user)):
            phase = user.map(AuthPhase.signedIn) ?? .guest

        case (.guest, .requestCode(let raw)), (.awaitingCode, .requestCode(let raw)):
            guard let email = EmailAddress.normalized(raw) else {
                lastError = .invalidEmail
                return false
            }
            lastError = nil
            phase = .sendingCode(email: email)

        case (.guest, .enterCodeFor(let raw)), (.awaitingCode, .enterCodeFor(let raw)):
            guard let email = EmailAddress.normalized(raw) else {
                lastError = .invalidEmail
                return false
            }
            lastError = nil
            phase = .awaitingCode(email: email)

        case (.sendingCode(let email), .codeSent):
            phase = .awaitingCode(email: email, purpose: .signIn)

        case (.sendingCode(let email), .signUpCodeSent):
            phase = .awaitingCode(email: email, purpose: .signUp)

        case (.sendingCode, .sendFailed(let message)):
            lastError = .sendFailed(message)
            phase = .guest

        case (.awaitingCode(let email, let purpose), .submitCode(let raw)):
            guard let code = OTPCode.normalized(raw) else {
                lastError = .invalidCode
                return false
            }
            lastError = nil
            phase = .verifying(email: email, code: code, purpose: purpose)

        case (.verifying(let email, _, .signUp), .signUpConfirmed):
            phase = .signingIn(email: email)

        case (.verifying, .verified(let user)), (.signingIn, .verified(let user)):
            lastError = nil
            phase = .signedIn(user)

        case (.verifying(let email, _, let purpose), .verifyFailed(let message)):
            lastError = .verifyFailed(message)
            phase = .awaitingCode(email: email, purpose: purpose)

        case (.signingIn, .verifyFailed(let message)):
            // The account exists now; a new code request takes the sign-in path.
            lastError = .verifyFailed(message)
            phase = .guest

        case (.awaitingCode, .cancel):
            lastError = nil
            phase = .guest

        case (.signedIn, .signedOut), (.signedIn, .sessionEnded):
            phase = .guest

        case (_, .sessionUpdated(let user)):
            lastError = nil
            phase = .signedIn(user)

        default:
            return false
        }
        return true
    }
}
