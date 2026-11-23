// Settings, opened from Today's avatar (TKL-825): the account (sign in with
// an emailed code, TKL-928), the children (pick who is being catechized, add
// another) and About & Credits. The practice reminder joins it in its own ticket.
import SwiftUI
import SwiftData
import DomainKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Query private var observedChildren: [LocalChild]
    @Query private var observedTracks: [ChildCatechismTrack]
    @Query private var observedSettings: [ProgressSettings]
    @State private var showsAddChild = false
    @State private var showsSignIn = false

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }

    var body: some View {
        let _ = observedChildren.map(\.updatedAt)
        let _ = observedTracks.map(\.updatedAt)
        let activeId = observedSettings.first?.activeChildId
        NavigationStack {
            List {
                if auth.isConfigured {
                    Section("Account") {
                        if let user = auth.user {
                            Text(user.email ?? "Signed in")
                                .foregroundStyle(.ccInk)
                                .accessibilityIdentifier("settings.accountEmail")
                            Button("Sign out", action: signOut)
                                .foregroundStyle(.ccDanger)
                                .accessibilityIdentifier("settings.signOut")
                        } else if auth.phase == .restoring {
                            Text("Checking…").foregroundStyle(.ccInk2)
                        } else {
                            Button("Sign in") { showsSignIn = true }
                                .foregroundStyle(.ccChapel)
                                .accessibilityIdentifier("settings.signIn")
                        }
                    }
                }
                Section("Children") {
                    ForEach(store.todayChildren()) { child in
                        Button {
                            try? store.selectChild(childId: child.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.name).foregroundStyle(.ccInk)
                                    Text("\(child.programShortTitle) · \(child.learned) of \(child.totalQuestions) learned")
                                        .font(.ccUI(13))
                                        .foregroundStyle(.ccInk2)
                                }
                                Spacer()
                                if child.id == activeId {
                                    Image(systemName: "checkmark").foregroundStyle(.ccChapel)
                                }
                            }
                        }
                    }
                    Button("Add a child") { showsAddChild = true }
                        .foregroundStyle(.ccChapel)
                }
                Section {
                    NavigationLink("About & Credits") {
                        AboutView(path: .constant(NavigationPath()))
                            .toolbar(.visible, for: .navigationBar)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.ccInk)
        .sheet(isPresented: $showsAddChild) { AddChildView() }
        .sheet(isPresented: $showsSignIn) { SignInSheet() }
        #if DEBUG
        // Screenshot hook: `-OpenSignIn YES` opens the sheet with Settings.
        .onChange(of: auth.phase, initial: true) { _, phase in
            guard auth.isConfigured else { return }
            let defaults = UserDefaults.standard
            if phase == .guest && defaults.bool(forKey: "OpenSignIn") {
                showsSignIn = true
            }
            if phase.isSignedIn && defaults.bool(forKey: "SettingsAutoSignOut") {
                signOut()
            }
        }
        #endif
    }

    private func signOut() {
        Task { await auth.signOut() }
    }
}

/// The Add a child sheet, as in TKL-885's prototype (TKL-941): Chapel title,
/// one filled field, one chapel button and errors inline under the field.
/// Adding is a local write, so there is nothing to wait on and no spinner.
struct AddChildView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var children: [LocalChild]
    @State private var name = ""
    @State private var submitted = false
    @FocusState private var focused: Bool

    private var check: ChildName.Check {
        ChildName.validate(name, existing: children.map(\.name))
    }

    private var error: String? {
        if submitted, check == .empty { return "Type a first name." }
        return check.message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add a child")
                .font(.ccDisplay(22, semibold: true))
                .foregroundStyle(.ccInk)
                .padding(.bottom, 6)
            Text("Starts at Q. 1 of the Shorter Catechism. Only a first name, kept on this iPhone.")
                .font(.ccUI(13))
                .foregroundStyle(.ccInk2)
                .padding(.bottom, 14)
            VStack(alignment: .leading, spacing: ChapelSpace.m) {
                TextField("First name", text: $name)
                    .font(.ccUI(17))
                    .foregroundStyle(.ccInk)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(add)
                    .padding(.horizontal, 14)
                    .frame(height: ChapelSize.buttonHeight)
                    .background(.ccFill, in: RoundedRectangle(cornerRadius: ChapelRadius.control))
                    .overlay {
                        if error != nil {
                            RoundedRectangle(cornerRadius: ChapelRadius.control)
                                .strokeBorder(.ccDanger, lineWidth: 1)
                        }
                    }
                    .accessibilityHint(error ?? "")
                if let error {
                    Text(error)
                        .font(.ccUI(13))
                        .foregroundStyle(.ccDanger)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button("Add", action: add)
                    .buttonStyle(ChapelPrimaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, ChapelSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            #if DEBUG
            // Screenshot hook: `-AddChildName Ruth` pre-fills the field and
            // shows any error as if Add had been tapped.
            if let preset = UserDefaults.standard.string(forKey: "AddChildName") { name = preset; submitted = true }
            #endif
            focused = true
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ChapelRadius.sheet)
        .presentationBackground(.ccSurface)
    }

    private func add() {
        submitted = true
        guard case .valid(let trimmed) = check else { return }
        let store = LocalProgressStore(context: modelContext)
        guard let child = try? store.addChild(name: trimmed) else { return }
        // The newest child becomes the one Today and the Catechism tab show.
        try? store.selectChild(childId: child.id)
        dismiss()
    }
}
