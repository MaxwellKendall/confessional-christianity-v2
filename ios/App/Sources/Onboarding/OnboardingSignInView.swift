import SwiftUI
import DomainKit

struct OnboardingSignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                if auth.isConfigured {
                    Section {
                        if case .awaitingCode = auth.phase {
                            codeFields
                        } else if case .verifying = auth.phase {
                            codeFields.disabled(true)
                        } else {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(isSending)
                            Button(isSending ? "Sending…" : "Send code") {
                                Task { await auth.sendCode(email: email) }
                            }
                            .disabled(isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if let error = auth.lastError {
                        Text(message(for: error)).foregroundStyle(.ccDanger)
                    }
                } else {
                    Text("Sign-in is unavailable on this device.")
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
        }
        .tint(.ccChapel)
        .interactiveDismissDisabled(isWorking)
    }

    private var codeFields: some View {
        Group {
            Text("Enter the code sent to \(auth.phase.pendingEmail ?? email).")
            TextField("6-digit code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
            Button("Verify code") { Task { await auth.verifyCode(code) } }
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Use a different email") {
                code = ""
                auth.cancelCode()
            }
        }
    }

    private var isWorking: Bool {
        if case .verifying = auth.phase { return true }
        return isSending
    }

    private var isSending: Bool {
        if case .sendingCode = auth.phase { return true }
        return false
    }

    private func message(for error: DomainKit.AuthError) -> String {
        switch error {
        case .invalidEmail: "Enter a valid email address."
        case .invalidCode: "Enter the six digits from your email."
        case .sendFailed: "The code couldn’t be sent. Please try again."
        case .verifyFailed: "The code couldn’t be verified. Check the code and try again."
        }
    }
}
