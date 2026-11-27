// App-level account sync coordinator (TKL-1068, TKL-818): wires AuthService's
// Cognito session to DomainKit's SyncEngine, AppSyncTransport and SyncScheduler.
//
// Never runs while signed out, never blocks the UI (no spinner), and stops +
// invalidates any in-flight sync and clears the previous subject's cursors and
// outbox on sign-out so a later sign-in (same or other account) starts clean.
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

    private let container: ModelContainer
    private let auth: AuthService
    private let syncURL: URL?

    private(set) var activeSubject: String?
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false

    var isConfigured: Bool { syncURL != nil }

    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored private var scheduler: SyncScheduler?

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

    /// Reacts to Cognito auth transitions (restore, sign-in, sign-out, session expiry).
    func handleAuthChange(_ user: DomainKit.AuthUser?) {
        let nextSubject = user?.id
        if nextSubject == activeSubject {
            return
        }
        if let previous = activeSubject {
            stopAndClear(subject: previous)
        }
        guard let nextSubject, let syncURL else { return }

        activeSubject = nextSubject
        let auth = self.auth
        let transport = AppSyncTransport(
            endpoint: syncURL,
            tokenProvider: { forceRefresh in
                await auth.accessToken(forceRefresh: forceRefresh)
            },
            isOnline: {
                await NetworkConnectivity.shared.isOnline()
            },
            onRejected: { id, reason in
                Self.logger.warning(
                    "sync change permanently rejected id=\(id.uuidString.lowercased(), privacy: .public) reason=\(reason ?? "unknown", privacy: .public)"
                )
            }
        )
        let engine = SyncEngine(
            context: container.mainContext,
            transport: transport,
            tables: ChildProgressSyncAdapters.all(),
            subject: nextSubject,
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
        appDidBecomeActive()
    }

    /// Synchronously stops and invalidates in-flight sync and clears the active
    /// subject's cursors and outbox right as sign-out begins.
    func willSignOut() {
        guard let subject = activeSubject else { return }
        stopAndClear(subject: subject)
    }

    /// App came to the foreground: trigger an immediate non-blocking sync if signed in.
    func appDidBecomeActive() {
        guard let scheduler else { return }
        isSyncing = true
        scheduler.appDidBecomeActive()
    }

    /// A synced local row was written: trigger a debounced sync if signed in.
    func localWriteOccurred() {
        scheduler?.localWriteOccurred()
    }

    /// Pull-to-refresh: runs a sync when signed in; returns immediately when signed out.
    func refresh() async {
        guard let scheduler else { return }
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

    private func stopAndClear(subject: String) {
        scheduler?.stop()
        engine?.invalidate()
        scheduler = nil
        engine = nil
        activeSubject = nil
        lastSyncedAt = nil
        isSyncing = false
        do {
            try SyncEngine.clearAccountState(for: subject, in: container.mainContext)
        } catch {
            Self.logger.error("failed to clear sync state on sign-out: \(String(describing: error), privacy: .public)")
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
