// Sign in with an emailed code (TKL-928 skeleton; the approved look comes in
// TKL-930). Email → "Send code" → code → signed in, then the sheet closes.
// Never a blocking spinner: fields stay editable while a call is in flight
// and the button says what is happening.
import SwiftUI
import DomainKit

struct SignInSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focus: Field?

    private enum Field { case email, code }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($focus, equals: .email)
                        .onSubmit(send)
                        .disabled(isSending || codeEmail != nil)
                        .accessibilityIdentifier("signIn.email")
                    if codeEmail == nil {
                        Button(isSending ? "Sending…" : "Send code", action: send)
                            .disabled(isSending)
                            .foregroundStyle(.ccChapel)
                            .accessibilityIdentifier("signIn.send")
                    }
                } footer: {
                    if codeEmail == nil {
                        Text("We'll email you a code. No password.")
                    }
                }

                if let codeEmail {
                    Section {
                        TextField(codePlaceholder, text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .code)
                            .onSubmit(verify)
                            .accessibilityIdentifier("signIn.code")
                        Button(isVerifying ? "Checking…" : "Sign in", action: verify)
                            .disabled(isVerifying)
                            .foregroundStyle(.ccChapel)
                            .accessibilityIdentifier("signIn.verify")
                        Button("Use a different email") {
                            auth.cancelCode()
                            code = ""
                            focus = .email
                        }
                        .foregroundStyle(.ccInk2)
                    } footer: {
                        Text("Sent to \(codeEmail).")
                    }
                }

                if let message = errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.ccDanger)
                            .accessibilityIdentifier("signIn.error")
                    }
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        auth.cancelCode()
                        dismiss()
                    }
                }
            }
            .onAppear {
                focus = codeEmail == nil ? .email : .code
            }
            #if DEBUG
            .task { await runTestDriver() }
            #endif
            .onChange(of: auth.phase) { _, phase in
                switch phase {
                case .signedIn: dismiss()
                case .awaitingCode: if focus == .email || focus == nil { focus = .code }
                default: break
                }
            }
        }
        .tint(.ccInk)
    }

    /// The address a code was sent to, once one is on its way or being checked.
    private var codeEmail: String? {
        switch auth.phase {
        case .awaitingCode(let email, _), .verifying(let email, _, _), .signingIn(let email): email
        default: nil
        }
    }

    private var codePlaceholder: String {
        if case .awaitingCode(_, .signUp) = auth.phase { return "6-digit code" }
        if case .verifying(_, _, .signUp) = auth.phase { return "6-digit code" }
        return "8-digit code"
    }

    private var isSending: Bool {
        if case .sendingCode = auth.phase { return true }
        return false
    }

    private var isVerifying: Bool {
        switch auth.phase {
        case .verifying, .signingIn: true
        default: false
        }
    }

    private var errorMessage: String? {
        switch auth.lastError {
        case .invalidEmail: "Enter an email address like name@example.com."
        case .invalidCode: "Enter the 6- or 8-digit code from the email."
        case .sendFailed(let message): "Couldn't send the code. \(message)"
        case .verifyFailed(let message): message
        case nil: nil
        }
    }

    #if DEBUG
    /// Test aid for the headless simulator (no taps), driving this sheet's own
    /// buttons: `-SignInEmail <address>` prefills the email, `-SignInAutoSend YES`
    /// sends the code, and `-SignInCodeFile <host path>` types each new code
    /// written to that file and submits it two seconds later (time for a
    /// screenshot of code entry). Only ever the dev pool's test inbox.
    private func runTestDriver() async {
        let defaults = UserDefaults.standard
        if email.isEmpty, let prefill = defaults.string(forKey: "SignInEmail") { email = prefill }
        if defaults.bool(forKey: "SignInAutoSend"), codeEmail == nil { send() }
        guard let path = defaults.string(forKey: "SignInCodeFile") else { return }
        var submitted: String?
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard case .awaitingCode = auth.phase,
                  let raw = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let next = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.isEmpty, next != submitted else { continue }
            submitted = next
            code = next
            try? await Task.sleep(for: .seconds(2))
            verify()
        }
    }
    #endif

    private func send() {
        Task { await auth.sendCode(email: email) }
    }

    private func verify() {
        guard let codeEmail else { return }
        Task { await auth.verify(email: codeEmail, code: code) }
    }
}
