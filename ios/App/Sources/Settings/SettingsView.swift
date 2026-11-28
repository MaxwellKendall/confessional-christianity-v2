// Settings, opened from Today's avatar (TKL-825), as in TKL-885's approved
// prototype (TKL-941): a sheet on surface with lists on paper. The account
// slot (sign in with an emailed code, TKL-928; its look is TKL-930's), the
// children (tap one to make them the active child, or add another), the
// reminders set on this iPhone, and About & Credits.
import SwiftUI
import SwiftData
import DomainKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Query private var observedChildren: [LocalChild]
    @Query private var observedTracks: [ChildCatechismTrack]
    @Query private var observedSettings: [ProgressSettings]
    @State private var showsAddChild = false
    @State private var showsSignIn = false
    @State private var showsSignOutConfirm = false
    @State private var signOutFlush: SignOutFlushOutcome?
    @State private var isFlushingSignOut = false
    @State private var showsGuestMerge = false
    @State private var showsAbout = false
    @State private var showsReminders = false

    private var store: LocalProgressStore { sync.progressStore(in: modelContext) }

    var body: some View {
        let _ = observedChildren.map(\.updatedAt)
        let _ = observedTracks.map(\.updatedAt)
        let activeId = observedSettings.first?.activeChildId
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.ccDisplay(22, semibold: true))
                        .foregroundStyle(.ccInk)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 6)
                    Text("On this iPhone")
                        .font(.ccUI(13))
                        .foregroundStyle(.ccInk3)
                        .padding(.bottom, 14)
                    if auth.isConfigured { account }
                    section("Children")
                    children(activeId: activeId)
                    section("Reminders")
                    reminders
                    section("About")
                    list {
                        Button { showsAbout = true } label: {
                            ChapelListRow(title: "About & Credits", detail: nil, trailing: .chevron)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ChapelSpace.gutter)
                .padding(.top, ChapelSpace.xl)
                .padding(.bottom, 36)
            }
            .refreshable { await sync.refresh() }
            .background(Color.ccSurface)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsReminders) {
                ReminderSettingsView()
            }
            .navigationDestination(isPresented: $showsAbout) {
                AboutView(path: .constant(NavigationPath()))
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .tint(.ccInk)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ChapelRadius.sheet)
        .presentationBackground(.ccSurface)
        #if DEBUG
        .task { showsReminders = UserDefaults.standard.bool(forKey: "OpenReminders") }
        #endif
        .onAppear { sync.isSettingsPresenting = true }
        .onDisappear { sync.isSettingsPresenting = false }
        .sheet(isPresented: $showsAddChild) { AddChildView() }
        .sheet(isPresented: $showsSignIn, onDismiss: {
            auth.cancelCode()
            if sync.pendingGuestMerge != nil {
                showsGuestMerge = true
            }
        }) { SignInSheet() }
        .sheet(isPresented: $showsSignOutConfirm, onDismiss: {
            signOutFlush = nil
            isFlushingSignOut = false
        }) {
            SignOutConfirmationSheet(
                flushOutcome: signOutFlush,
                isFlushing: isFlushingSignOut,
                onConfirm: confirmSignOutTapped,
                onCancel: { showsSignOutConfirm = false }
            )
        }
        .fullScreenCover(isPresented: $showsGuestMerge) {
            GuestDataMergeHostView(onDone: { showsGuestMerge = false })
        }
        .onChange(of: sync.pendingGuestMerge, initial: true) { _, pending in
            if pending == nil {
                showsGuestMerge = false
            } else if !showsSignIn {
                showsGuestMerge = true
            }
        }
        #if DEBUG
        // Screenshot hook: `-OpenSignIn YES` opens the sheet with Settings.
        .onChange(of: auth.phase, initial: true) { _, phase in
            guard auth.isConfigured else { return }
            let defaults = UserDefaults.standard
            if phase == .guest && defaults.bool(forKey: "OpenSignIn") {
                showsSignIn = true
            }
            if phase.isSignedIn && defaults.bool(forKey: "OpenSignOutConfirm") {
                showsSignOutConfirm = true
            }
            if phase.isSignedIn && defaults.bool(forKey: "SettingsAutoSignOut") {
                confirmSignOut()
            }
        }
        #endif
    }

    // MARK: sections

    /// The account slot, in the prototype's place. Its look is TKL-930's.
    @ViewBuilder
    private var account: some View {
        if let user = auth.user {
            list {
                ChapelListRow(title: "Signed in", detail: user.email ?? "", trailing: .nothing) {
                    Text(String((user.email ?? "?").prefix(1)).uppercased())
                }
                .accessibilityIdentifier("settings.accountEmail")
            }
            if sync.isConfigured {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(SyncService.lastSyncedLine(lastSyncedAt: sync.lastSyncedAt, now: context.date))
                        .font(.ccUI(13))
                        .foregroundStyle(.ccInk3)
                        .padding(.top, ChapelSpace.s)
                        .accessibilityIdentifier("settings.lastSynced")
                }
            }
            Button("Sign out") { showsSignOutConfirm = true }
                .buttonStyle(ChapelQuietButtonStyle())
                .padding(.top, ChapelSpace.m)
                .accessibilityIdentifier("settings.signOut")
        } else if auth.phase == .restoring {
            list {
                ChapelListRow(title: "Checking…", detail: nil, trailing: .nothing) { Text("•") }
            }
        } else {
            list {
                Button { showsSignIn = true } label: {
                    ChapelListRow(title: "Sign in to sync", detail: "Keep progress and notes if you lose this iPhone", trailing: .chevron) {
                        Text("•")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.signIn")
            }
        }
    }

    private func children(activeId: UUID?) -> some View {
        let children = store.todayChildren()
        return list {
            ForEach(children) { child in
                Button {
                    try? store.selectChild(childId: child.id)
                } label: {
                    ChapelListRow(
                        title: child.name,
                        detail: "\(child.programShortTitle) · Q. \(child.questionNumber)",
                        // With one child there is nothing to choose between.
                        trailing: children.count > 1 && child.id == activeId ? .selected : .chevron
                    ) {
                        Text(String(child.name.prefix(1)))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(child.id == activeId ? .isSelected : [])
                ChapelRowDivider()
            }
            Button { showsAddChild = true } label: {
                ChapelListRow(title: "Add a child", detail: nil, trailing: .nothing) { Text("+") }
            }
            .buttonStyle(.plain)
        }
    }

    private var reminders: some View {
        list {
            Button { showsReminders = true } label: {
                ChapelListRow(title: "Reminders", detail: nil, trailing: .chevron)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: pieces

    private func section(_ title: String) -> some View {
        Text(title)
            .chapelCaps()
            .padding(.top, ChapelSpace.xl)
            .padding(.bottom, ChapelSpace.s)
            .accessibilityAddTraits(.isHeader)
    }

    /// A list card on paper, as lists sit inside a sheet.
    private func list<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }.chapelCard(fill: .ccPaper)
    }

    /// First tap pushes unsynced changes (TKL-1084). Signs out when nothing is
    /// left unsynced; otherwise the sheet warns and a second tap signs out anyway.
    private func confirmSignOutTapped() {
        guard !isFlushingSignOut else { return }
        if case .unsynced = signOutFlush {
            showsSignOutConfirm = false
            confirmSignOut()
            return
        }
        isFlushingSignOut = true
        Task {
            let outcome = await sync.flushBeforeSignOut()
            isFlushingSignOut = false
            guard showsSignOutConfirm else { return }
            if case .unsynced = outcome {
                signOutFlush = outcome
            } else {
                showsSignOutConfirm = false
                confirmSignOut()
            }
        }
    }

    private func confirmSignOut() {
        sync.signOutAndClearLocalData()
        Task { await auth.signOut() }
    }
}

/// The Add a child sheet, as in TKL-885's prototype (TKL-941): Chapel title,
/// one filled field, one chapel button and errors inline under the field.
/// Adding is a local write, so there is nothing to wait on and no spinner.
struct AddChildView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var sync
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
        let store = sync.progressStore(in: modelContext)
        guard let child = try? store.addChild(name: trimmed) else { return }
        // The newest child becomes the one Today and the Catechism tab show.
        try? store.selectChild(childId: child.id)
        dismiss()
    }
}
