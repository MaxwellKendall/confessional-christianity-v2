// The app's account session against the Cognito user pool (infra/, TKL-850):
// sign in with an emailed code, sign out, and a fresh access token for API
// calls. The transitions live in DomainKit's AuthMachine (unit-tested); this
// class only performs the Amplify calls and feeds their outcomes back in.
//
// Sign-in is passwordless (`USER_AUTH` + `EMAIL_OTP`; the pool's NoPassword
// trigger scrambles any password). `sendCode` tries a passwordless sign-up
// first: a new email gets a 6-digit confirmation code, then auto sign-in once
// it is confirmed; an email that already has an account (`usernameExists`)
// gets an 8-digit sign-in code instead. Sign-up first because the pool hides
// whether a user exists from sign-in (preventUserExistenceErrors) but not
// from sign-up.
//
// Amplify persists and refreshes the session in the Keychain; it is restored
// on launch. A missing or invalid amplify_outputs file (prod until TKL-893)
// leaves the app a guest with no sign-in entry point (`isConfigured`).
@preconcurrency import Amplify
import enum Amplify.AuthError
import AWSCognitoAuthPlugin
import AWSPluginsCore
import Foundation
import Observation
import DomainKit

@MainActor
@Observable
final class AuthService {
    /// Debug builds use ConfessionalChristianity-dev, Release the prod pool.
    /// Each configuration bundles only its own file (project.yml).
    #if DEBUG
    static let outputsResource = "amplify_outputs.dev"
    #else
    static let outputsResource = "amplify_outputs.prod"
    #endif

    private(set) var machine = AuthMachine()

    var phase: AuthPhase { machine.phase }
    var user: DomainKit.AuthUser? { machine.phase.user }
    var lastError: DomainKit.AuthError? { machine.lastError }
    /// False when the bundle lacks a valid amplify_outputs file: the app stays
    /// a guest and Settings shows no sign-in row.
    let isConfigured: Bool

    @ObservationIgnored private var hubToken: UnsubscribeToken?

    init(bundle: Bundle = .main) {
        isConfigured = Self.configureAmplify(bundle: bundle)
        guard isConfigured else {
            machine.handle(.restored(nil))
            return
        }
        listen()
        Task { await restore() }
    }

    /// Emails a code to `email`: a sign-up code the first time the address is
    /// used, otherwise a sign-in code.
    func sendCode(email: String) async {
        guard isConfigured else { return }
        guard machine.handle(.requestCode(email)), case .sendingCode(let normalized) = machine.phase else { return }
        // A half-finished sign-in from an earlier attempt blocks a new one.
        _ = await Amplify.Auth.signOut()
        do {
            _ = try await Amplify.Auth.signUp(
                username: normalized,
                password: nil,
                options: .init(userAttributes: [AuthUserAttribute(.email, value: normalized)])
            )
            machine.handle(.signUpCodeSent)
            return
        } catch let error as AuthError where Self.cognitoError(error) == .usernameExists {
            // Existing account: sign in below.
        } catch {
            machine.handle(.sendFailed(Self.message(for: error)))
            return
        }
        do {
            let result = try await Amplify.Auth.signIn(
                username: normalized,
                options: .init(pluginOptions: AWSAuthSignInOptions(authFlowType: .userAuth(preferredFirstFactor: .emailOTP)))
            )
            switch result.nextStep {
            case .confirmSignInWithOTP:
                machine.handle(.codeSent)
            case .confirmSignUp:
                // Signed up earlier but never confirmed: confirm with a fresh sign-up code.
                _ = try await Amplify.Auth.resendSignUpCode(for: normalized)
                machine.handle(.signUpCodeSent)
            default:
                machine.handle(.sendFailed("Unexpected sign-in step: \(result.nextStep)"))
            }
        } catch let error as AuthError where Self.cognitoError(error) == .userNotConfirmed {
            do {
                _ = try await Amplify.Auth.resendSignUpCode(for: normalized)
                machine.handle(.signUpCodeSent)
            } catch {
                machine.handle(.sendFailed(Self.message(for: error)))
            }
        } catch {
            machine.handle(.sendFailed(Self.message(for: error)))
        }
    }

    /// Checks the emailed code for `email` and signs in.
    func verify(email: String, code: String) async {
        guard isConfigured else { return }
        guard case .awaitingCode(let current, _) = machine.phase, current == EmailAddress.normalized(email) else { return }
        guard machine.handle(.submitCode(code)),
              case .verifying(let normalized, let token, let purpose) = machine.phase else { return }
        switch purpose {
        case .signIn:
            do {
                let result = try await Amplify.Auth.confirmSignIn(challengeResponse: token)
                await finishSignIn(result)
            } catch {
                machine.handle(.verifyFailed(Self.message(for: error)))
            }
        case .signUp:
            let confirmed: AuthSignUpResult
            do {
                confirmed = try await Amplify.Auth.confirmSignUp(for: normalized, confirmationCode: token)
            } catch {
                machine.handle(.verifyFailed(Self.message(for: error)))
                return
            }
            machine.handle(.signUpConfirmed)
            guard case .completeAutoSignIn = confirmed.nextStep else {
                machine.handle(.verifyFailed("Account created. Send a new code to sign in."))
                return
            }
            do {
                await finishSignIn(try await Amplify.Auth.autoSignIn())
            } catch {
                machine.handle(.verifyFailed(Self.message(for: error)))
            }
        }
    }

    /// Verifies `code` for the address the code was sent to (the phase's
    /// address), so an edited email field can't retarget it.
    func verifyCode(_ code: String) async {
        guard case .awaitingCode(let email, _) = machine.phase else { return }
        await verify(email: email, code: code)
    }

    /// Back from "enter code" to guest without signing in.
    func cancelCode() {
        machine.handle(.cancel)
    }

    /// Signs out on this device. Amplify clears the local session even when
    /// the server call fails, so this works offline.
    func signOut() async {
        guard isConfigured else { return }
        _ = await Amplify.Auth.signOut()
        machine.handle(.signedOut)
    }

    /// A valid access token (refreshed if needed), or nil when signed out or
    /// the session can't be refreshed.
    func accessToken() async -> String? {
        guard isConfigured, machine.phase.isSignedIn else { return nil }
        guard let session = try? await Amplify.Auth.fetchAuthSession(),
              let tokens = session as? AuthCognitoTokensProvider else { return nil }
        return try? tokens.getCognitoTokens().get().accessToken
    }

    // MARK: - Private

    private func finishSignIn(_ result: AuthSignInResult) async {
        guard result.isSignedIn, let user = await Self.currentUser() else {
            machine.handle(.verifyFailed("Sign-in didn't finish (\(result.nextStep))"))
            return
        }
        machine.handle(.verified(user))
    }

    private func restore() async {
        let signedIn = (try? await Amplify.Auth.fetchAuthSession())?.isSignedIn == true
        machine.handle(.restored(signedIn ? await Self.currentUser() : nil))
    }

    private func listen() {
        hubToken = Amplify.Hub.listen(to: .auth) { [weak self] payload in
            let name = payload.eventName
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch name {
                case HubPayload.EventName.Auth.sessionExpired, HubPayload.EventName.Auth.signedOut,
                     HubPayload.EventName.Auth.userDeleted:
                    self.machine.handle(.sessionEnded)
                default:
                    break
                }
            }
        }
    }

    private static func currentUser() async -> DomainKit.AuthUser? {
        guard let user = try? await Amplify.Auth.getCurrentUser() else { return nil }
        let attributes = (try? await Amplify.Auth.fetchUserAttributes()) ?? []
        let email = attributes.first { $0.key == .email }?.value
        return DomainKit.AuthUser(id: user.userId, email: email)
    }

    /// Amplify can be configured once per process.
    private static var configured: Bool?

    private static func configureAmplify(bundle: Bundle) -> Bool {
        if let configured { return configured }
        let ok: Bool
        if bundle.url(forResource: outputsResource, withExtension: "json") == nil {
            ok = false
        } else {
            do {
                try Amplify.add(plugin: AWSCognitoAuthPlugin())
                try Amplify.configure(with: .resource(named: outputsResource))
                ok = true
            } catch {
                ok = false
            }
        }
        configured = ok
        return ok
    }

    private static func cognitoError(_ error: AuthError) -> AWSCognitoAuthError? {
        if case .service(_, _, let underlying) = error { return underlying as? AWSCognitoAuthError }
        return nil
    }

    private static func message(for error: Error) -> String {
        if let error = error as? AuthError {
            switch cognitoError(error) {
            case .codeMismatch: return "That code isn't right. Check the email and try again."
            case .codeExpired: return "That code has expired. Send a new one."
            default: return error.errorDescription
            }
        }
        return error.localizedDescription
    }
}
