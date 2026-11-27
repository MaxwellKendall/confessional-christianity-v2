// Local-first sync (TKL-813). SwiftData stays the store the UI reads; every
// local write to a synced table also appends a change to a persisted outbox.
// The engine pushes the outbox in order and pulls each table's rows changed
// since a stored cursor. Conflicts resolve per row, last write wins by
// `updated_at`; deletes are soft (`deleted_at`) so they travel like any other
// write and remove the local row on arrival.
//
// The pull cursor is NOT `updated_at`. `updated_at` is the writer's clock, so
// a device that comes back online can upload a row stamped earlier than rows
// other devices have already pulled; an `updated_at` cursor would skip it
// forever. Instead the server stamps every accepted write with `change_id`, a
// monotonically increasing number, and pulls resume after the last one seen.
// `updated_at` only decides conflicts.
//
// Storage errors are never swallowed: a local write, a push's outbox removal
// and a pull page plus its cursor each commit in one save, roll back together
// on failure, and throw to the caller.
//
// No networking or Supabase here: the app supplies a `SyncTransport`
// (Supabase under RLS, TKL-818) and one `SyncTableAdapter` per synced table
// (prayer list, favorites, day completions...), so every rule is unit-tested
// on the host Mac with a fake transport.
import Foundation
import SwiftData

// MARK: - Wire types

/// One row as the server holds it. `payload` is the row's JSON (nil for a
/// tombstone); `updatedAt`/`deletedAt` mirror the `updated_at`/`deleted_at`
/// columns every synced table carries. `changeId` is the server-assigned
/// `change_id` of the row's latest accepted write (see `SyncTransport`).
public struct SyncRecord: Equatable, Sendable {
    public var table: String
    public var id: String
    public var childId: String?
    public var noteId: String?
    public var payload: Data?
    public var updatedAt: Date
    public var deletedAt: Date?
    public var changeId: Int64

    public init(table: String, id: String, childId: String? = nil, noteId: String? = nil, payload: Data?,
                updatedAt: Date, deletedAt: Date? = nil, changeId: Int64 = 0) {
        self.table = table
        self.id = id
        self.childId = childId
        self.noteId = noteId
        self.payload = payload
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.changeId = changeId
    }

    public var isDeleted: Bool { deletedAt != nil }
}

/// One outbox entry on its way to the server. `id` is the entry's own id,
/// which the transport echoes back to acknowledge it.
public struct SyncChange: Equatable, Sendable {
    public var id: UUID
    public var table: String
    public var rowId: String
    public var childId: String?
    public var noteId: String?
    public var payload: Data?
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, table: String, rowId: String, childId: String? = nil, noteId: String? = nil,
                payload: Data?, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.table = table
        self.rowId = rowId
        self.childId = childId
        self.noteId = noteId
        self.payload = payload
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Where a table's pull resumes: strictly after this server `change_id`.
public struct SyncCursor: Equatable, Hashable, Sendable {
    public var changeId: Int64

    public init(changeId: Int64) {
        self.changeId = changeId
    }
}

/// The server side, supplied by the app.
public protocol SyncTransport: Sendable {
    /// Writes the changes (in order) and returns the ids of the ones the
    /// server acknowledged. The server applies each with last-write-wins on
    /// `updated_at`; an older change it ignores still counts as acknowledged
    /// (and keeps the row's `change_id`). Every write it accepts gets a new
    /// `change_id` greater than any it has handed out for that user, whatever
    /// the write's `updated_at`, and must not become visible to a pull after a
    /// higher `change_id` already has (e.g. assign it in a trigger under a
    /// per-user transaction lock).
    func push(_ changes: [SyncChange]) async throws -> Set<UUID>

    /// Up to `limit` rows of `table` with `change_id` strictly greater than
    /// `cursor` (all rows when nil), soft-deleted rows included, ascending by
    /// `change_id`.
    func pull(table: String, after cursor: SyncCursor?, limit: Int) async throws -> [SyncRecord]
}

/// The local side of one synced table, supplied by the app. Read and write
/// through the given context and don't save it: the engine saves the page and
/// its cursor together, or rolls both back.
@MainActor
public protocol SyncTableAdapter: AnyObject {
    /// The server table name (e.g. "prayer_requests").
    var table: String { get }
    /// `updated_at` of the local row, or nil if there is none.
    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date?
    /// Insert or replace the local row from a (non-deleted) server row.
    func apply(_ record: SyncRecord, in context: ModelContext) throws
    /// Remove the local row (a server soft delete won).
    func remove(id: String, in context: ModelContext) throws
    /// Remove with full tombstone metadata (e.g. `updatedAt` / `deletedAt`) for soft-deleted tables.
    func remove(_ record: SyncRecord, in context: ModelContext) throws
    /// When true, live (non-deleted) incoming records are always passed to
    /// `apply(_:in:)` so the adapter can merge (e.g. unioning milestones so the
    /// more advanced state wins) instead of LWW short-circuiting. Tombstones
    /// (`record.isDeleted`) still follow LWW.
    var mergesLiveRecords: Bool { get }
}

public extension SyncTableAdapter {
    func remove(_ record: SyncRecord, in context: ModelContext) throws {
        try remove(id: record.id, in: context)
    }

    var mergesLiveRecords: Bool { false }
}

public enum SyncError: Error, Equatable {
    /// The server acknowledged only part of a push; the rest stays queued.
    case partialAcknowledgement(acknowledged: Int, sent: Int)
}

// MARK: - Persisted state (part of the shared SwiftData schema)

@Model
public final class SyncOutboxEntry {
    @Attribute(.unique) public var entryId: UUID
    /// Monotonic order of local writes; push sends ascending.
    public var sequence: Int
    /// Cognito subject this outbox entry belongs to (nil in unscoped unit tests).
    public var subject: String?
    public var table: String
    public var rowId: String
    /// Stable child UUID for child-scoped tables (`child_id` in AppSync).
    public var childId: String?
    /// Stable note UUID for Lord's Day tables (`note_id` in AppSync).
    public var noteId: String?
    public var payload: Data?
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(entryId: UUID = UUID(), sequence: Int, subject: String? = nil, table: String,
                rowId: String, childId: String? = nil, noteId: String? = nil, payload: Data?,
                updatedAt: Date, deletedAt: Date?) {
        self.entryId = entryId
        self.sequence = sequence
        self.subject = subject
        self.table = table
        self.rowId = rowId
        self.childId = childId
        self.noteId = noteId
        self.payload = payload
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var change: SyncChange {
        SyncChange(id: entryId, table: table, rowId: rowId, childId: childId, noteId: noteId,
                   payload: payload, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

@Model
public final class SyncCursorRecord {
    /// Storage key: `table` when unscoped, or `"<subject>::<table>"` when scoped to a Cognito subject.
    @Attribute(.unique) public var table: String
    /// The last server `change_id` applied for this table.
    public var changeId: Int64

    public init(table: String, changeId: Int64) {
        self.table = table
        self.changeId = changeId
    }
}

/// Persisted mapping between a server sync row ID and its local domain identity
/// plus its own per-row `updatedAt`. Needed so (1) a co-guardian's server-assigned
/// UUID is reused on future edits, (2) tombstones (which carry no payload) know
/// which local milestone/assignment/pacing row to remove, and (3) LWW resolves
/// independently per table/milestone even when multiple server tables map to one
/// local SwiftData model (`ChildCatechismTrack`).
@Model
public final class SyncRowMeta {
    @Attribute(.unique) public var lookupKey: String
    public var table: String
    public var rowId: String
    public var childId: String
    public var naturalKey: String
    public var updatedAt: Date

    public init(table: String, rowId: String, childId: String, naturalKey: String, updatedAt: Date) {
        let lowerRow = rowId.lowercased()
        self.lookupKey = "\(table):\(lowerRow)"
        self.table = table
        self.rowId = lowerRow
        self.childId = childId.lowercased()
        self.naturalKey = naturalKey
        self.updatedAt = updatedAt
    }
}

/// The sync engine's own models; `progressSchema` includes them so the
/// outbox lives in the shared App Group store beside the data it describes.
public let syncModelTypes: [any PersistentModel.Type] = [
    SyncOutboxEntry.self, SyncCursorRecord.self, SyncRowMeta.self,
]
public let syncSchema = Schema(syncModelTypes)

// MARK: - Engine

/// Anything the scheduler can run; `SyncEngine` in the app, a fake in tests.
@MainActor
public protocol SyncRunning: AnyObject {
    func sync() async throws
}

@MainActor
public final class SyncEngine: SyncRunning {
    /// Commits the context; injectable so tests can simulate a full disk.
    public typealias Save = @MainActor (ModelContext) throws -> Void

    private let context: ModelContext
    private let save: Save
    private let transport: any SyncTransport
    private let adapters: [any SyncTableAdapter]
    public let subject: String?
    private let pushBatchSize: Int
    private let pullPageSize: Int
    private var isInvalidated = false

    public init(context: ModelContext, transport: any SyncTransport, tables: [any SyncTableAdapter],
                subject: String? = nil, pushBatchSize: Int = 100, pullPageSize: Int = 500,
                save: @escaping Save = { try $0.save() }) {
        self.context = context
        self.save = save
        self.transport = transport
        self.adapters = tables
        self.subject = subject
        self.pushBatchSize = max(1, pushBatchSize)
        self.pullPageSize = max(1, pullPageSize)
    }

    /// Invalidates this engine instance (called on sign-out). Any in-flight push
    /// or pull stops before committing rows, advancing cursors, or mutating the outbox.
    public func invalidate() {
        isInvalidated = true
    }

    /// True when this store already holds cursors or outbox entries for `subject`,
    /// meaning this device previously synced as `subject` (e.g. upgrading from an
    /// earlier build before a separate last-synced-subject marker existed).
    public static func hasSyncedState(for subject: String, in context: ModelContext) throws -> Bool {
        let prefix = "\(subject)::"
        let cursors = try context.fetch(FetchDescriptor<SyncCursorRecord>())
        if cursors.contains(where: { $0.table.hasPrefix(prefix) }) {
            return true
        }
        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        return entries.contains(where: { $0.subject == subject })
    }

    /// Deletes every persisted outbox entry and pull cursor owned by `subject`.
    /// Called on sign-out so a later sign-in (same or other account) never sees
    /// the previous session's cursors or outbox.
    public static func clearAccountState(for subject: String, in context: ModelContext) throws {
        do {
            let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            for entry in entries where entry.subject == subject {
                context.delete(entry)
            }
            let prefix = "\(subject)::"
            let cursors = try context.fetch(FetchDescriptor<SyncCursorRecord>())
            for cursor in cursors where cursor.table.hasPrefix(prefix) {
                context.delete(cursor)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Local writes

    /// Queue a local write for upload and save. Write the row into this
    /// engine's context first, without saving, with the same `updatedAt`: the
    /// row and its outbox entry then commit in one save. A delete passes
    /// `deletedAt` (and usually a nil payload) after removing the local row.
    /// Throws if the save fails; both the entry and the unsaved row change are
    /// rolled back, so the caller must not report the write as saved.
    public func recordLocalWrite(table: String, id: String, childId: String? = nil, noteId: String? = nil,
                                 payload: Data?, updatedAt: Date, deletedAt: Date? = nil) throws {
        try commit {
            let entry = SyncOutboxEntry(sequence: try nextSequence(), subject: subject, table: table,
                                        rowId: id, childId: childId, noteId: noteId, payload: payload,
                                        updatedAt: updatedAt, deletedAt: deletedAt)
            context.insert(entry)
        }
    }

    /// The queued changes, oldest first.
    public func pendingChanges() throws -> [SyncChange] {
        try outbox().map(\.change)
    }

    public func cursor(for table: String) throws -> SyncCursor? {
        try cursorRecord(for: table).map { SyncCursor(changeId: $0.changeId) }
    }

    // MARK: Sync

    /// Push, then pull. A push failure stops the run (the outbox is kept and
    /// the next run retries); the caller's scheduler backs off. If pull merges
    /// a live conflict (e.g. a more advanced local milestone) and queues an
    /// upgraded row, pushes it immediately so both sides converge.
    public func sync() async throws {
        try checkActive()
        try await push()
        try checkActive()
        try await pull()
        if !(try outbox().isEmpty) {
            try checkActive()
            try await push()
        }
    }

    /// Initial guest-data union sync (TKL-1070): pulls existing account rows
    /// first (resolving same-ID rows by LWW and unioning milestones so the more
    /// advanced state wins without letting a less-advanced guest row overwrite
    /// the server), then pushes all surviving outbox entries.
    public func mergeSync() async throws {
        try checkActive()
        try await pull()
        try checkActive()
        try await push()
    }

    /// Sends the outbox in order, in batches; removes an entry only once the
    /// server has acknowledged it. Stops at the first batch that isn't fully
    /// acknowledged so later writes never overtake earlier ones.
    public func push() async throws {
        while true {
            try checkActive()
            let batch = Array(try outbox().prefix(pushBatchSize))
            guard !batch.isEmpty else { return }
            let acknowledged = try await transport.push(batch.map(\.change))
            try checkActive()
            var removed = 0
            try commit {
                for entry in batch where acknowledged.contains(entry.entryId) {
                    context.delete(entry)
                    removed += 1
                }
            }
            if removed < batch.count {
                throw SyncError.partialAcknowledgement(acknowledged: removed, sent: batch.count)
            }
        }
    }

    /// For each table, fetch pages of rows after the stored cursor, apply
    /// them with last-write-wins, and advance the cursor after each page (the
    /// page and the cursor commit in one save).
    public func pull() async throws {
        for adapter in adapters {
            try checkActive()
            try await pull(adapter)
        }
    }

    private func pull(_ adapter: any SyncTableAdapter) async throws {
        while true {
            try checkActive()
            let cursor = try cursor(for: adapter.table)
            let page = try await transport.pull(table: adapter.table, after: cursor, limit: pullPageSize)
                .sorted { $0.changeId < $1.changeId }
            try checkActive()
            guard let last = page.last else { return }
            try commit {
                for record in page where record.table == adapter.table {
                    try apply(record, to: adapter)
                }
                try setCursor(SyncCursor(changeId: max(last.changeId, cursor?.changeId ?? 0)), for: adapter.table)
            }
            if page.count < pullPageSize { return }
        }
    }

    /// Last write wins. The local side's time is the newer of the stored row
    /// and any write still queued for it (so a queued delete, whose row is
    /// already gone, still beats an older server copy). Ties keep local.
    private func apply(_ record: SyncRecord, to adapter: any SyncTableAdapter) throws {
        let lowerId = record.id.lowercased()
        let queued = try outbox().filter { $0.table == record.table && $0.rowId.lowercased() == lowerId }
        if !record.isDeleted && adapter.mergesLiveRecords {
            for entry in queued {
                context.delete(entry)
            }
            try adapter.apply(record, in: context)
            return
        }
        let localTimes = [try adapter.localUpdatedAt(id: record.id, in: context)].compactMap { $0 } + queued.map(\.updatedAt)
        if let localLatest = localTimes.max(), localLatest >= record.updatedAt {
            return
        }
        if record.isDeleted {
            try adapter.remove(record, in: context)
        } else {
            try adapter.apply(record, in: context)
        }
        // The server's copy is newer than anything queued for this row, so
        // those queued writes are stale: drop them instead of pushing them.
        for entry in queued {
            context.delete(entry)
        }
    }

    // MARK: Storage

    private func checkActive() throws {
        if isInvalidated || Task.isCancelled {
            throw CancellationError()
        }
    }

    /// Runs the changes and saves them as one unit. On any error the context
    /// is rolled back (nothing half-applied stays in memory to be saved by a
    /// later call) and the error is rethrown.
    private func commit(_ changes: () throws -> Void) throws {
        do {
            try changes()
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func outbox() throws -> [SyncOutboxEntry] {
        let descriptor = FetchDescriptor<SyncOutboxEntry>(sortBy: [SortDescriptor(\.sequence)])
        return try context.fetch(descriptor).filter { $0.subject == subject }
    }

    private func nextSequence() throws -> Int {
        var descriptor = FetchDescriptor<SyncOutboxEntry>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        let last = try context.fetch(descriptor).first?.sequence ?? 0
        return last + 1
    }

    private func cursorStorageKey(for table: String) -> String {
        if let subject { return "\(subject)::\(table)" }
        return table
    }

    private func cursorRecord(for table: String) throws -> SyncCursorRecord? {
        let key = cursorStorageKey(for: table)
        let predicate = #Predicate<SyncCursorRecord> { $0.table == key }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    private func setCursor(_ cursor: SyncCursor, for table: String) throws {
        let key = cursorStorageKey(for: table)
        if let existing = try cursorRecord(for: table) {
            existing.changeId = cursor.changeId
        } else {
            context.insert(SyncCursorRecord(table: key, changeId: cursor.changeId))
        }
    }
}

// MARK: - Scheduling

/// Exponential retry delay: base, 2×base, 4×base... capped at `max`.
public struct SyncBackoff: Equatable, Sendable {
    public var base: Duration
    public var max: Duration

    public init(base: Duration = .seconds(2), max: Duration = .seconds(300)) {
        self.base = base
        self.max = max
    }

    public func delay(afterFailures failures: Int) -> Duration {
        guard failures > 0 else { return .zero }
        let exponent = Swift.min(failures - 1, 30)
        let delay = base * (1 << exponent)
        return delay > max ? max : delay
    }
}

/// When sync runs: on app foreground, debounced after a local write, and on
/// manual refresh. Triggers return immediately and the work runs in a task,
/// so nothing waits on the network; a failure schedules a retry with backoff
/// and is visible in `lastError` / `consecutiveFailures`. Runs never overlap:
/// a trigger during a run queues exactly one more run.
@MainActor
public final class SyncScheduler {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let syncer: any SyncRunning
    private let debounce: Duration
    private let backoff: SyncBackoff
    private let sleep: Sleep

    public private(set) var isSyncing = false
    public private(set) var lastError: (any Error)?
    public private(set) var consecutiveFailures = 0
    public private(set) var lastSuccessAt: Date?
    /// Called once each run ends (after any reruns it absorbed and after a
    /// retry is scheduled), with whether its last sync succeeded. Lets the UI
    /// and tests react to the end of a run instead of polling.
    public var runDidFinish: (@MainActor (_ succeeded: Bool) -> Void)?

    private var rerunRequested = false
    private var isStopped = false
    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var runTask: Task<Bool, Never>?

    public init(syncer: any SyncRunning, debounce: Duration = .seconds(2),
                backoff: SyncBackoff = SyncBackoff(),
                sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.syncer = syncer
        self.debounce = debounce
        self.backoff = backoff
        self.sleep = sleep
    }

    /// Stops and cancels any pending debounce, retry, or in-flight sync run.
    /// Once stopped, this scheduler never starts another run or records results.
    public func stop() {
        isStopped = true
        rerunRequested = false
        debounceTask?.cancel()
        debounceTask = nil
        retryTask?.cancel()
        retryTask = nil
        runTask?.cancel()
        runTask = nil
        isSyncing = false
    }

    /// The app came to the foreground: sync now.
    public func appDidBecomeActive() {
        guard !isStopped else { return }
        trigger()
    }

    /// A synced row was written locally: sync once writes settle.
    public func localWriteOccurred() {
        guard !isStopped else { return }
        debounceTask?.cancel()
        let delay = debounce
        let sleep = self.sleep
        debounceTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.trigger()
        }
    }

    /// Pull-to-refresh: runs a sync and returns whether it succeeded.
    @discardableResult
    public func refresh() async -> Bool {
        guard !isStopped else { return false }
        trigger()
        // Either a fresh run, or the in-flight one that will loop once more
        // for this request; its result covers the refresh.
        guard let task = runTask else { return false }
        return await task.value
    }

    private func trigger() {
        guard !isStopped else { return }
        retryTask?.cancel()
        retryTask = nil
        if isSyncing {
            rerunRequested = true
            return
        }
        start()
    }

    private func start() {
        guard !isStopped else { return }
        isSyncing = true
        runTask = Task { [weak self] in
            guard let self else { return false }
            return await self.run()
        }
    }

    private func run() async -> Bool {
        var succeeded = false
        repeat {
            if isStopped || Task.isCancelled {
                isSyncing = false
                return false
            }
            rerunRequested = false
            do {
                try await syncer.sync()
                if isStopped || Task.isCancelled {
                    isSyncing = false
                    return false
                }
                succeeded = true
                consecutiveFailures = 0
                lastError = nil
                lastSuccessAt = Date()
            } catch {
                if isStopped || Task.isCancelled {
                    isSyncing = false
                    return false
                }
                succeeded = false
                consecutiveFailures += 1
                lastError = error
            }
        } while rerunRequested && !isStopped && !Task.isCancelled
        isSyncing = false
        if isStopped || Task.isCancelled { return false }
        if !succeeded {
            scheduleRetry()
        }
        runDidFinish?(succeeded)
        return succeeded
    }

    private func scheduleRetry() {
        guard !isStopped else { return }
        let delay = backoff.delay(afterFailures: consecutiveFailures)
        let sleep = self.sleep
        retryTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self, !self.isStopped, !self.isSyncing else { return }
            self.retryTask = nil
            self.start()
        }
    }
}
