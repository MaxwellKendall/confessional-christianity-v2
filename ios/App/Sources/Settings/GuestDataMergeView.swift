// "Keep what's on this phone in your account" confirmation (TKL-1070, prototype TKL-833)
// and the Sign out confirmation sheet (TKL-833). Built strictly with Chapel tokens
// and components from DesignSystem.swift; never a blocking spinner.
import SwiftUI
import DomainKit

struct GuestDataMergeHostView: View {
    @Environment(SyncService.self) private var sync
    let onDone: () -> Void

    var body: some View {
        if let pending = sync.pendingGuestMerge {
            GuestDataMergeView(
                email: pending.user.email,
                summary: pending.summary,
                phase: sync.guestMergePhase,
                onConfirm: { sync.confirmGuestMerge() },
                onContinueInBackground: {
                    sync.continueInBackgroundFromGuestMerge()
                    onDone()
                }
            )
            #if DEBUG
            .task {
                if UserDefaults.standard.bool(forKey: "GuestMergeAutoConfirm") {
                    sync.confirmGuestMerge()
                }
            }
            #endif
        } else {
            Color.ccPaper
                .ignoresSafeArea()
                .onAppear(perform: onDone)
        }
    }
}

struct GuestDataMergeView: View {
    let email: String?
    let summary: GuestDataSummary
    let phase: SyncService.GuestMergePhase
    let onConfirm: () -> Void
    let onContinueInBackground: () -> Void

    private var eyebrow: String {
        if let email, !email.isEmpty {
            return "Signed in as \(email)"
        }
        return "Signed in"
    }

    private var isSaving: Bool {
        if case .saving = phase { return true }
        return false
    }

    private var completedRows: Int {
        if case .saving(let count) = phase { return count }
        return 0
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChapelSpace.l) {
                Text(eyebrow)
                    .chapelCaps()
                    .accessibilityIdentifier("guestMerge.eyebrow")

                Text("Keep what’s on this phone in your account")
                    .font(.ccDisplay(23, semibold: true))
                    .foregroundStyle(.ccInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("guestMerge.title")

                Text("This iPhone already has your progress. We’ll add it to your account so it’s on every device. Nothing is deleted, and anything already in your account stays too.")
                    .chapelReading()
                    .foregroundStyle(.ccInk2)

                VStack(spacing: 0) {
                    ForEach(Array(summary.rows.enumerated()), id: \.element.id) { index, row in
                        let done = isSaving && index < completedRows
                        HStack(alignment: .firstTextBaseline, spacing: ChapelSpace.m) {
                            Text(row.label)
                                .font(.ccUI(15))
                                .foregroundStyle(.ccInk)
                            Spacer(minLength: 0)
                            Text(isSaving ? (done ? "Saved" : "Saving…") : row.value)
                                .font(.ccUI(15))
                                .monospacedDigit()
                                .foregroundStyle(done ? Color.ccGilt : Color.ccInk3)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 12)
                        ChapelRowDivider()
                    }
                }
                .accessibilityIdentifier("guestMerge.rows")

                if isFailed {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "wifi.slash")
                            .font(.ccUI(15, weight: .semibold))
                            .foregroundStyle(.ccDanger)
                            .padding(.top, 1)
                            .accessibilityHidden(true)
                        (Text("We couldn’t reach your account. ").fontWeight(.semibold)
                            + Text("Everything is still on this iPhone. Try again when you’re online."))
                            .font(.ccUI(14))
                            .foregroundStyle(.ccDanger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ccDangerFill, in: RoundedRectangle(cornerRadius: ChapelRadius.control, style: .circular))
                    .accessibilityIdentifier("guestMerge.error")
                }

                if isSaving {
                    SavingProgressButton(title: "Saving to your account…")
                        .accessibilityIdentifier("guestMerge.saving")

                    Text("You can leave this screen. Saving carries on in the background.")
                        .font(.ccUI(13))
                        .foregroundStyle(.ccInk3)

                    Button("Continue to the app", action: onContinueInBackground)
                        .font(.ccUI(16.5, weight: .medium))
                        .foregroundStyle(.ccInk2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("guestMerge.continue")
                } else {
                    Button(isFailed ? "Try again" : "Keep it in my account", action: onConfirm)
                        .buttonStyle(ChapelPrimaryButtonStyle())
                        .accessibilityIdentifier("guestMerge.confirm")
                }
            }
            .padding(.horizontal, ChapelSpace.gutter)
            .padding(.top, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.ccPaper.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }
}

/// Inline progress bar inside the primary button (no blocking spinner, per Chapel rules).
private struct SavingProgressButton: View {
    let title: String
    @State private var sweep = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChapelRadius.control, style: .circular)
        ZStack(alignment: .bottomLeading) {
            Text(title)
                .font(.ccUI(16.5, weight: .semibold))
                .foregroundStyle(.ccOnChapel)
                .frame(maxWidth: .infinity, minHeight: ChapelSize.buttonHeight)
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.ccOnChapel.opacity(0.5))
                    .frame(width: geo.size.width * 0.55, height: 3)
                    .offset(x: sweep ? geo.size.width : -geo.size.width * 0.55)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false), value: sweep)
            }
            .frame(height: 3)
        }
        .background(Color.ccChapel, in: shape)
        .clipShape(shape)
        .opacity(0.45)
        .onAppear { sweep = true }
    }
}

/// Sign-out confirmation sheet (TKL-833 / TKL-1070): explains that synced account
/// data stays in the account while the local copies on this iPhone are cleared.
/// Sign out first pushes unsynced changes (`isFlushing`); if that fails, the
/// sheet says how many will be removed and offers Sign out anyway (TKL-1084).
struct SignOutConfirmationSheet: View {
    var flushOutcome: SignOutFlushOutcome? = nil
    var isFlushing = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var isUnsynced: Bool {
        if case .unsynced = flushOutcome { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ChapelSpace.l) {
            Text("Sign out?")
                .font(.ccH2)
                .foregroundStyle(.ccInk)
                .accessibilityAddTraits(.isHeader)

            Text(SignOutConfirmationCopy.body(for: flushOutcome))
                .chapelReading()
                .foregroundStyle(.ccInk2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.signOutBody")

            if isFlushing {
                SavingProgressButton(title: "Syncing your changes…")
                    .accessibilityIdentifier("settings.signOutConfirm")
            } else {
                Button(SignOutConfirmationCopy.confirmTitle(for: flushOutcome), action: onConfirm)
                    .buttonStyle(ChapelPrimaryButtonStyle())
                    .accessibilityIdentifier("settings.signOutConfirm")
            }

            Button("Cancel", action: onCancel)
                .font(.ccUI(16.5, weight: .medium))
                .foregroundStyle(.ccInk2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.signOutCancel")
        }
        .padding(.horizontal, 22)
        .padding(.top, ChapelSpace.xl)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(isUnsynced ? 380 : 340)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ChapelRadius.sheet)
        .presentationBackground(.ccSurface)
    }
}

#if DEBUG
/// Screenshot hook (TKL-1084): `-SignOutConfirmFixture kept|flushing|unsynced`
/// renders the sign-out sheet over paper in that state (no account needed).
struct SignOutConfirmFixture: View {
    let scene: String

    var body: some View {
        Color.ccPaper.ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                SignOutConfirmationSheet(
                    flushOutcome: scene == "unsynced" ? .unsynced(count: 3) : nil,
                    isFlushing: scene == "flushing",
                    onConfirm: {},
                    onCancel: {}
                )
            }
    }
}

/// Screenshot hook (TKL-1070): `-GuestMergeFixture full|loading|error` renders
/// the merge confirmation screen directly for side-by-side comparison with
/// TKL-833's prototype.
struct GuestDataMergeFixture: View {
    let scene: String

    private var summary: GuestDataSummary {
        GuestDataSummary(
            childCount: 2,
            trackCount: 2,
            milestoneCount: 11,
            singleTrack: nil,
            noteCount: 1,
            cardCount: 6
        )
    }

    private var phase: SyncService.GuestMergePhase {
        switch scene {
        case "loading": .saving(completedRows: 1)
        case "error": .failed("offline")
        default: .idle
        }
    }

    var body: some View {
        GuestDataMergeView(
            email: "anna.calvin@example.com",
            summary: summary,
            phase: phase,
            onConfirm: {},
            onContinueInBackground: {}
        )
    }
}
#endif
