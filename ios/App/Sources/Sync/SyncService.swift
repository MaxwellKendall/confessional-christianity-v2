// App-level account sync coordinator (TKL-1068, TKL-818, TKL-1070): wires
// AuthService's Cognito session to DomainKit's SyncEngine, AppSyncTransport
// and SyncScheduler.
//
// Never runs while signed out, never blocks the UI (no spinner), pauses on
// first sign-in when guest data exists so the user can confirm "Keep what's on
// this phone in your account", and clears all synced account data on confirmed
// sign-out so a later sign-in (same or other account) starts clean.
import DomainKit
import Foundation
import Observation
import OSLog
import SwiftData
import WidgetKit

@MainActor
@Observable
final class SyncService {
    nonisolated private static let logger = Logger(subsystem: "com.confessionalchristianity.app", category: "sync")
    private static let lastSyncedSubjectKey = "AccountSyncLastSubject"

    struct PendingGuestMerge: Equatable {
        let user: DomainKit.AuthUser
        let summary: GuestDataSummary
    }

    enum GuestMergePhase: Equatable {
        case idle
        case saving(completedRows: Int)
        case failed(String)
    }

    private let container: ModelContainer
    private let auth: AuthService
    private let syncURL: URL?

    private(set) var activeSubject: String?
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false
    private(set) var pendingGuestMerge: PendingGuestMerge?
    private(set) var guestMergePhase: GuestMergePhase = .idle
    /// Coordinates full-screen cover ownership between SettingsView and RootView
    /// so SwiftUI never attempts nested presentations simultaneously.
    var isSettingsPresenting = false

    var isConfigured: Bool { syncURL != nil }

    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored private var scheduler: SyncScheduler?
    @ObservationIgnored private var connectivityTask: Task<Void, Never>?
    @ObservationIgnored private var mergeTask: Task<Void, Never>?

    private var lastSyncedSubject: String? {
        get { UserDefaults.standard.string(forKey: Self.lastSyncedSubjectKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.lastSyncedSubjectKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncedSubjectKey)
            }
        }
    }

    init(container: ModelContainer, auth: AuthService, bundle: Bundle = .main) {
        self.container = container
        self.auth = auth
        self.syncURL = Self.resolveSyncURL(bundle: bundle)
    }

    /// Returns a `LocalProgressStore` bound to the active signed-in Cognito subject
    /// (atomically queueing sync outbox entries and scheduling debounced sync), or a
    /// strictly local store when signed out.
    func progressStore(in context: ModelContext) -> LocalProgressStore {
        guard let subject = activeSubject else {
            return LocalProgressStore(context: context)
        }
        return LocalProgressStore(
            context: context,
            syncSubject: subject,
            onLocalWrite: { [weak self] in self?.localWriteOccurred() }
        )
    }

    /// Returns a `LordsDayStore` bound to the active signed-in Cognito subject
    /// (atomically queueing sync outbox entries and scheduling debounced sync), or a
    /// strictly local store when signed out.
    func lordsDayStore(in context: ModelContext) -> LordsDayStore {
        guard let subject = activeSubject else {
            return LordsDayStore(context: context)
        }
        return LordsDayStore(
            context: context,
            syncSubject: subject,
            onLocalWrite: { [weak self] in self?.localWriteOccurred() }
        )
    }

    /// Reacts to Cognito auth transitions (restore, sign-in, sign-out, session expiry).
    func handleAuthChange(_ user: DomainKit.AuthUser?) {
        let nextSubject = user?.id
        if nextSubject == activeSubject && pendingGuestMerge == nil {
            return
        }
        if let nextSubject, pendingGuestMerge?.user.id == nextSubject {
            return
        }
        if activeSubject != nil {
            stopRuntime()
        }
        guard let user, let nextSubject, let syncURL else {
            pendingGuestMerge = nil
            guestMergePhase = .idle
            return
        }
        _ = syncURL

        // If another account previously owned local data and exited uncleanly
        // (e.g. session expiry without explicit sign-out), clear its data so it
        // is never treated as guest data or uploaded to the new account.
        if let previousOwner = lastSyncedSubject, previousOwner != nextSubject {
            clearLocalAccountData(subject: previousOwner)
            lastSyncedSubject = nil
        }

        let alreadySyncedHere = lastSyncedSubject == nextSubject
            || ((try? SyncEngine.hasSyncedState(for: nextSubject, in: container.mainContext)) ?? false)
        if alreadySyncedHere {
            lastSyncedSubject = nextSubject
            pendingGuestMerge = nil
            guestMergePhase = .idle
            startRuntime(for: nextSubject, triggerImmediately: true)
            return
        }

        // First sign-in on this device for this account: check for local guest data.
        let summary = (try? GuestDataMerge.summary(in: container.mainContext)) ?? .empty
        if summary.hasData {
            pendingGuestMerge = PendingGuestMerge(user: user, summary: summary)
            guestMergePhase = .idle
            Self.logger.info("holding sync for guest data merge confirmation")
        } else {
            lastSyncedSubject = nextSubject
            pendingGuestMerge = nil
            guestMergePhase = .idle
            startRuntime(for: nextSubject, triggerImmediately: true)
        }
    }

    /// User confirmed "Keep it in my account": atomically enqueues every guest
    /// row into the outbox, then runs a union merge sync (pull first, then push)
    /// without blocking the user from continuing to the app.
    func confirmGuestMerge() {
        guard let pending = pendingGuestMerge else { return }
        if case .saving = guestMergePhase { return }
        let subject = pending.user.id
        if activeSubject != subject {
            do {
                let count = try GuestDataMerge.enqueueGuestData(for: subject, in: container.mainContext)
                Self.logger.info("enqueued \(count) guest rows for account merge")
            } catch {
                Self.logger.error("failed to enqueue guest data: \(String(describing: error), privacy: .public)")
                guestMergePhase = .failed(String(describing: error))
                return
            }
            lastSyncedSubject = subject
            startRuntime(for: subject, triggerImmediately: false)
        }

        guard let currentEngine = engine else { return }
        guestMergePhase = .saving(completedRows: 0)
        isSyncing = true
        let totalRows = pending.summary.rows.count
        mergeTask?.cancel()
        mergeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await currentEngine.mergeSync()
                guard !Task.isCancelled, self.engine === currentEngine else { return }
                self.isSyncing = false
                self.lastSyncedAt = Date()
                WidgetCenter.shared.reloadTimelines(ofKind: "CatechismWidget")
                Self.logger.info("account sync succeeded (guest merge)")
                if self.pendingGuestMerge?.user.id == subject {
                    self.guestMergePhase = .saving(completedRows: totalRows)
                    self.pendingGuestMerge = nil
                    self.guestMergePhase = .idle
                }
            } catch {
                guard !Task.isCancelled, self.engine === currentEngine else { return }
                self.isSyncing = false
                Self.logger.error("account sync failed (guest merge): \(String(describing: error), privacy: .public)")
                if self.pendingGuestMerge?.user.id == subject {
                    self.guestMergePhase = .failed(String(describing: error))
                } else {
                    self.scheduler?.appDidBecomeActive()
                }
            }
        }
    }

    /// Dismisses the merge confirmation while saving continues in the background.
    func continueInBackgroundFromGuestMerge() {
        pendingGuestMerge = nil
        guestMergePhase = .idle
    }

    /// Synchronously stops and invalidates in-flight sync and clears all synced
    /// account data from the device back to an empty guest state (TKL-1070).
    func signOutAndClearLocalData() {
        let departingSubject = activeSubject ?? lastSyncedSubject
        stopRuntime()
        pendingGuestMerge = nil
        guestMergePhase = .idle
        clearLocalAccountData(subject: departingSubject)
        lastSyncedSubject = nil
        WidgetCenter.shared.reloadTimelines(ofKind: "CatechismWidget")
        Self.logger.info("signed out and cleared local synced data")
    }

    /// App came to the foreground: trigger an immediate non-blocking sync if signed in.
    func appDidBecomeActive() {
        guard pendingGuestMerge == nil, let scheduler else { return }
        isSyncing = true
        scheduler.appDidBecomeActive()
    }

    /// A synced local row was written: trigger a debounced sync if signed in.
    func localWriteOccurred() {
        guard pendingGuestMerge == nil else { return }
        scheduler?.localWriteOccurred()
    }

    /// Pull-to-refresh: runs a sync when signed in; returns immediately when signed out.
    func refresh() async {
        guard pendingGuestMerge == nil, let scheduler else { return }
        isSyncing = true
        _ = await scheduler.refresh()
    }

    static func lastSyncedLine(lastSyncedAt: Date?, now: Date = Date()) -> String {
        guard let lastSyncedAt else { return "Not synced yet" }
        if now.timeIntervalSince(lastSyncedAt) < 45 {
            return "Last synced just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last synced \(formatter.localizedString(for: lastSyncedAt, relativeTo: now))"
    }

    // MARK: - Private

    private func startRuntime(for subject: String, triggerImmediately: Bool) {
        guard let syncURL else { return }
        activeSubject = subject
        let auth = self.auth
        let transport = AppSyncTransport(
            endpoint: syncURL,
            tokenProvider: { forceRefresh in
                await auth.accessToken(forceRefresh: forceRefresh)
            },
            isOnline: {
                await NetworkConnectivity.shared.isOnline()
            }
        )
        let engine = SyncEngine(
            context: container.mainContext,
            transport: transport,
            tables: AccountSyncAdapters.all(subject: subject),
            subject: subject,
            pushBatchSize: AppSyncTransport.maxPushBatchSize,
            pullPageSize: 50
        )
        let scheduler = SyncScheduler(syncer: engine, debounce: .seconds(2))
        scheduler.runDidFinish = { [weak self] succeeded in
            guard let self, self.scheduler === scheduler else { return }
            self.isSyncing = false
            if succeeded {
                self.lastSyncedAt = scheduler.lastSuccessAt
                WidgetCenter.shared.reloadTimelines(ofKind: "CatechismWidget")
                Self.logger.info("account sync succeeded")
            } else if let error = scheduler.lastError {
                Self.logger.error("account sync failed: \(String(describing: error), privacy: .public)")
            }
        }
        self.engine = engine
        self.scheduler = scheduler
        connectivityTask = Task { [weak self] in
            var wasOffline = false
            for await online in NetworkConnectivity.shared.onlineUpdates() {
                guard !Task.isCancelled, let self else { return }
                if !online {
                    wasOffline = true
                } else if wasOffline {
                    wasOffline = false
                    self.appDidBecomeActive()
                }
            }
        }
        if triggerImmediately {
            appDidBecomeActive()
        }
    }

    private func stopRuntime() {
        mergeTask?.cancel()
        mergeTask = nil
        connectivityTask?.cancel()
        connectivityTask = nil
        scheduler?.stop()
        engine?.invalidate()
        scheduler = nil
        engine = nil
        activeSubject = nil
        lastSyncedAt = nil
        isSyncing = false
    }

    private func clearLocalAccountData(subject: String?) {
        ReviewModel.cancelAllSessions()
        try? CaptureDraft.setActive(nil)
        UserDefaults.standard.removeObject(forKey: LordsDayTabView.memoryKey)
        do {
            try AccountDataCleanup.clearSyncedData(for: subject, in: container.mainContext)
        } catch {
            Self.logger.error("failed to clear synced local data on sign-out: \(String(describing: error), privacy: .public)")
        }
    }

    private static func resolveSyncURL(bundle: Bundle) -> URL? {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "AccountSyncEndpoint"),
           let url = URL(string: raw),
           let scheme = url.scheme?.lowercased(),
           (scheme == "https" || scheme == "http"),
           url.host != nil {
            return url
        }
        #endif
        return AccountSyncConfig.syncURL(in: bundle, resourceName: AuthService.outputsResource)
    }
}
