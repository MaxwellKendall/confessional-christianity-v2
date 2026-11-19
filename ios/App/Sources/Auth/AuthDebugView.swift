// TEMPORARY, DEBUG builds only (TKL-812): proves email-code sign-in end to
// end on the simulator before the real sign-in screens exist (TKL-826).
// Delete when TKL-826 lands. Open it by launching with `-AuthDebug YES`:
//   xcrun simctl launch "CC iPhone 17 Pro" com.confessionalchristianity.app -AuthDebug YES
#if DEBUG
import SwiftUI
import DomainKit

struct AuthDebugView: View {
    @Environment(AuthService.self) private var auth
    @State private var email = ""
    @State private var code = ""
    @State private var tokenInfo = "—"

    var body: some View {
        NavigationStack {
            Form {
                Section("State") {
                    LabeledContent("Configured", value: auth.isConfigured ? "yes" : "no")
                    LabeledContent("Phase", value: phaseLabel)
                    if let user = auth.user {
                        LabeledContent("User id", value: user.id)
                            .accessibilityIdentifier("authDebug.userId")
                        LabeledContent("Email", value: user.email ?? "—")
                    }
                    if let error = auth.lastError {
                        Text(String(describing: error))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("authDebug.error")
                    }
                }

                if !auth.phase.isSignedIn {
                    Section("Email code") {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("authDebug.email")
                        Button("Send code") { Task { await auth.sendCode(email: email) } }
                            .accessibilityIdentifier("authDebug.send")
                        TextField("6-digit code", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("authDebug.code")
                        Button("Verify") { Task { await auth.verify(email: email, code: code) } }
                            .accessibilityIdentifier("authDebug.verify")
                    }
                } else {
                    Section("Session") {
                        // Never show the token itself, only that one exists.
                        LabeledContent("Access token", value: tokenInfo)
                        Button("Fetch access token") {
                            Task {
                                let token = await auth.accessToken()
                                tokenInfo = token.map { "\($0.count) chars" } ?? "none"
                            }
                        }
                        Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
                    }
                }
            }
            .navigationTitle("Auth debug")
        }
    }

    private var phaseLabel: String {
        switch auth.phase {
        case .restoring: "restoring"
        case .guest: "guest"
        case .sendingCode(let email): "sending code to \(email)"
        case .awaitingCode(let email): "awaiting code for \(email)"
        case .verifying(let email, _): "verifying \(email)"
        case .signedIn: "signed in"
        }
    }
}
#endif
