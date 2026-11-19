// The app's account session against the website's Supabase project: email
// 6-digit code sign-in, sign out, and a fresh access token for API calls.
// The transitions live in DomainKit's AuthMachine (unit-tested); this class
// only performs the Supabase calls and feeds their outcomes back in.
//
// The session is persisted by supabase-swift in the Keychain
// (KeychainLocalStorage) and restored on launch through the SDK's
// `.initialSession` event. Guest mode is the default: the app works fully
// without signing in.
import Foundation
import Observation
import DomainKit
import Supabase

@MainActor
@Observable
final class AuthService {
    private(set) var machine = AuthMachine()

    var phase: AuthPhase { machine.phase }
    var user: AuthUser? { machine.phase.user }
    var lastError: DomainKit.AuthError? { machine.lastError }
    /// False when Info.plist lacks the Supabase settings: the app stays a
    /// guest and the sign-in calls do nothing.
    var isConfigured: Bool { client != nil }

    @ObservationIgnored private let client: AuthClient?
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(config: SupabaseConfig? = .fromBundle()) {
        guard let config else {
            client = nil
            machine.handle(.restored(nil))
            return
        }
        let supabase = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainLocalStorage(service: "com.confessionalchristianity.app.auth"),
                    // Local first: a stored (possibly expired) session counts as
                    // signed in at launch; the SDK refreshes it and reports
                    // `.signedOut` if the refresh token is no longer valid.
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        client = supabase.auth
        listen()
    }

    deinit {
        listener?.cancel()
    }

    /// Sends a 6-digit code to `email` (creating the account on first use).
    func sendCode(email: String) async {
        guard let client else { return }
        guard machine.handle(.requestCode(email)), case .sendingCode(let normalized) = machine.phase else { return }
        do {
            try await client.signInWithOTP(email: normalized, shouldCreateUser: true)
            machine.handle(.codeSent)
        } catch {
            machine.handle(.sendFailed(Self.message(for: error)))
        }
    }

    /// Verifies the emailed code for `email` and signs in.
    func verify(email: String, code: String) async {
        guard let client else { return }
        if case .awaitingCode(let current) = machine.phase, current == EmailAddress.normalized(email) {
            // Already waiting on this address.
        } else {
            guard machine.handle(.enterCodeFor(email)) else { return }
        }
        guard machine.handle(.submitCode(code)), case .verifying(let normalized, let token) = machine.phase else { return }
        do {
            let response = try await client.verifyOTP(email: normalized, token: token, type: .email)
            if let session = response.session {
                machine.handle(.verified(Self.user(from: session.user)))
            } else {
                machine.handle(.verifyFailed("No session returned"))
            }
        } catch {
            machine.handle(.verifyFailed(Self.message(for: error)))
        }
    }

    /// Back from "enter code" to guest without signing in.
    func cancelCode() {
        machine.handle(.cancel)
    }

    /// Signs out on this device. The local session is removed before the
    /// network call, so this succeeds offline.
    func signOut() async {
        guard let client else { return }
        do {
            try await client.signOut(scope: .local)
        } catch {
            // Session already removed locally; the server call is best effort.
        }
        machine.handle(.signedOut)
    }

    /// A valid access token (refreshed if needed), or nil when signed out
    /// or the session can't be refreshed.
    func accessToken() async -> String? {
        guard let client, machine.phase.isSignedIn else { return nil }
        return try? await client.session.accessToken
    }

    private func listen() {
        guard let client else { return }
        listener = Task { [weak self] in
            for await (event, session) in client.authStateChanges {
                guard let self else { return }
                self.apply(event: event, session: session)
            }
        }
    }

    private func apply(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession:
            machine.handle(.restored(session.map { Self.user(from: $0.user) }))
        case .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            if let session { machine.handle(.sessionUpdated(Self.user(from: session.user))) }
        case .signedOut, .userDeleted:
            machine.handle(.sessionEnded)
        default:
            break
        }
    }

    private static func user(from user: User) -> AuthUser {
        AuthUser(id: user.id.uuidString.lowercased(), email: user.email)
    }

    private static func message(for error: Error) -> String {
        if let error = error as? Auth.AuthError { return error.message }
        return error.localizedDescription
    }
}
