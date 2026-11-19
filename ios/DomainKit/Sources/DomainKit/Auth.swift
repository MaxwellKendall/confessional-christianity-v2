// Pure sign-in logic for the app's Supabase account: email validation, the
// 6-digit code format, and the state machine the app's AuthService drives.
// No networking here — AuthService (app target) performs the Supabase calls
// and feeds their outcomes back in as events, so every transition is
// unit-testable on the host Mac.
import Foundation

public enum EmailAddress {
    /// Trimmed, lowercased address if it looks deliverable, else nil.
    /// Deliberately modest: one "@", a non-empty local part without spaces,
    /// and a dotted domain with no empty labels. Supabase does the real check.
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
    public static let length = 6

    /// The code with spaces and dashes removed, if it is exactly six ASCII digits.
    public static func normalized(_ raw: String) -> String? {
        let code = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard code.count == length, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return code
    }
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
    case awaitingCode(email: String)
    case verifying(email: String, code: String)
    case signedIn(AuthUser)

    public var user: AuthUser? {
        if case .signedIn(let user) = self { return user }
        return nil
    }

    public var isSignedIn: Bool { user != nil }
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
    case codeSent
    /// Enter a code for `email` without sending one (e.g. after a relaunch).
    case enterCodeFor(String)
    case sendFailed(String)
    case submitCode(String)
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
            phase = .awaitingCode(email: email)

        case (.sendingCode, .sendFailed(let message)):
            lastError = .sendFailed(message)
            phase = .guest

        case (.awaitingCode(let email), .submitCode(let raw)):
            guard let code = OTPCode.normalized(raw) else {
                lastError = .invalidCode
                return false
            }
            lastError = nil
            phase = .verifying(email: email, code: code)

        case (.verifying, .verified(let user)):
            lastError = nil
            phase = .signedIn(user)

        case (.verifying(let email, _), .verifyFailed(let message)):
            lastError = .verifyFailed(message)
            phase = .awaitingCode(email: email)

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
