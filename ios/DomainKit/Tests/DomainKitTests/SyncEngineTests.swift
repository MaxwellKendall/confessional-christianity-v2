// TKL-813: the local-first sync engine, driven by a fake transport and a fake
// table adapter so every rule (outbox order, ack-before-remove, cursor
// advance, last-write-wins, soft delete, backoff) runs on the host Mac.
import Foundation
import SwiftData
import Testing
@testable import DomainKit

// MARK: - Fakes

/// An in-memory "server": rows per table plus scripted failures. Applies
/// pushed changes with the same last-write-wins rule the real backend uses.
final class FakeTransport: SyncTransport, @unchecked Sendable {
    var rows: [String: [String: SyncRecord]] = [:]
    /// The server's change counter: every accepted write gets the next value,
    /// whatever its `updatedAt` (like a Postgres sequence bumped by trigger).
    private(set) var lastChangeId: Int64 = 0
    var offline = false
    /// Acknowledge only this many changes of the next push, then stop.
    var ackLimit: Int?
    private(set) var pushedBatches: [[SyncChange]] = []
    private(set) var pullCalls: [(table: String, after: SyncCursor?)] = []

    func seed(_ record: SyncRecord) {
        var record = record
        lastChangeId += 1
        record.changeId = lastChangeId
        rows[record.table, default: [:]][record.id] = record
    }

    func push(_ changes: [SyncChange]) async throws -> Set<UUID> {
        if offline { throw URLError(.notConnectedToInternet) }
        pushedBatches.append(changes)
        var acked = Set<UUID>()
        for (index, change) in changes.enumerated() {
            if let limit = ackLimit, index >= limit { break }
            let existing = rows[change.table]?[change.rowId]
            if existing == nil || existing!.updatedAt < change.updatedAt {
                seed(SyncRecord(
                    table: change.table, id: change.rowId, payload: change.payload,
                    updatedAt: change.updatedAt, deletedAt: change.deletedAt
                ))
            }
            acked.insert(change.id)
        }
        ackLimit = nil
        return acked
    }

    func pull(table: String, after cursor: SyncCursor?, limit: Int) async throws -> [SyncRecord] {
        if offline { throw URLError(.notConnectedToInternet) }
        pullCalls.append((table, cursor))
        let sorted = (rows[table].map { Array($0.values) } ?? [])
            .sorted { $0.changeId < $1.changeId }
            .filter { $0.changeId > (cursor?.changeId ?? 0) }
        return Array(sorted.prefix(limit))
    }
}

/// A local table backed by a dictionary, standing in for a SwiftData store.
@MainActor
final class FakeTable: SyncTableAdapter {
    let table: String
    var rows: [String: (payload: Data?, updatedAt: Date)] = [:]

    init(_ table: String) { self.table = table }

    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date? { rows[id]?.updatedAt }
    func apply(_ record: SyncRecord, in context: ModelContext) throws { rows[record.id] = (record.payload, record.updatedAt) }
    func remove(id: String, in context: ModelContext) throws { rows[id] = nil }
}

private func t(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }
private func json(_ s: String) -> Data { Data(s.utf8) }

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: syncSchema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

// MARK: - Engine

@MainActor
@Suite("SyncEngine")
struct SyncEngineTests {
    @Test("offline writes queue in the outbox and flush in order once online")
    func offlineQueueThenFlush() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let prayers = FakeTable("prayer_requests")
        let engine = SyncEngine(context: context, transport: server, tables: [prayers])
        server.offline = true

        try engine.recordLocalWrite(table: "prayer_requests", id: "a", payload: json("{\"t\":1}"), updatedAt: t(1))
        try engine.recordLocalWrite(table: "prayer_requests", id: "b", payload: json("{\"t\":2}"), updatedAt: t(2))
        try engine.recordLocalWrite(table: "prayer_requests", id: "a", payload: json("{\"t\":3}"), updatedAt: t(3))

        await #expect(throws: (any Error).self) { try await engine.sync() }
        #expect(try engine.pendingChanges().map(\.rowId) == ["a", "b", "a"])

        server.offline = false
        try await engine.sync()
        #expect(try engine.pendingChanges().isEmpty)
        #expect(server.pushedBatches.flatMap { $0 }.map(\.rowId) == ["a", "b", "a"])
        #expect(server.rows["prayer_requests"]?["a"]?.payload == json("{\"t\":3}"))
        #expect(server.rows["prayer_requests"]?["b"]?.updatedAt == t(2))
    }

    @Test("the outbox survives a relaunch (persisted in SwiftData)")
    func outboxIsPersisted() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sync-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let container = try ModelContainer(for: syncSchema, configurations: [ModelConfiguration(schema: syncSchema, url: url)])
            let engine = SyncEngine(context: ModelContext(container), transport: FakeTransport(), tables: [])
            try engine.recordLocalWrite(table: "favorites", id: "x", payload: json("{}"), updatedAt: t(1))
        }
        let container = try ModelContainer(for: syncSchema, configurations: [ModelConfiguration(schema: syncSchema, url: url)])
        let engine = SyncEngine(context: ModelContext(container), transport: FakeTransport(), tables: [])
        #expect(try engine.pendingChanges().map(\.rowId) == ["x"])
    }

    @Test("a push failure keeps the whole outbox")
    func pushFailureKeepsOutbox() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let engine = SyncEngine(context: context, transport: server, tables: [])
        try engine.recordLocalWrite(table: "favorites", id: "x", payload: json("{}"), updatedAt: t(1))
        try engine.recordLocalWrite(table: "favorites", id: "y", payload: json("{}"), updatedAt: t(2))
        server.offline = true
        await #expect(throws: (any Error).self) { try await engine.push() }
        #expect(try engine.pendingChanges().map(\.rowId) == ["x", "y"])
    }

    @Test("only acknowledged entries leave the outbox; the rest stay in order")
    func partialAckKeepsRemainder() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let engine = SyncEngine(context: context, transport: server, tables: [])
        for (i, id) in ["x", "y", "z"].enumerated() {
            try engine.recordLocalWrite(table: "favorites", id: id, payload: json("{}"), updatedAt: t(Double(i)))
        }
        server.ackLimit = 1
        await #expect(throws: SyncError.self) { try await engine.push() }
        #expect(try engine.pendingChanges().map(\.rowId) == ["y", "z"])
        try await engine.push()
        #expect(try engine.pendingChanges().isEmpty)
    }

    @Test("push sends batches in outbox order")
    func pushBatchesInOrder() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let engine = SyncEngine(context: context, transport: server, tables: [], pushBatchSize: 2)
        for i in 0..<5 {
            try engine.recordLocalWrite(table: "favorites", id: "r\(i)", payload: json("{}"), updatedAt: t(Double(i)))
        }
        try await engine.push()
        #expect(server.pushedBatches.map { $0.map(\.rowId) } == [["r0", "r1"], ["r2", "r3"], ["r4"]])
    }

    @Test("pull applies rows since the cursor and advances it per table")
    func pullAdvancesCursor() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let prayers = FakeTable("prayer_requests")
        let favorites = FakeTable("favorites")
        let engine = SyncEngine(context: context, transport: server, tables: [prayers, favorites], pullPageSize: 2)
        server.seed(SyncRecord(table: "prayer_requests", id: "a", payload: json("1"), updatedAt: t(1)))
        server.seed(SyncRecord(table: "prayer_requests", id: "b", payload: json("2"), updatedAt: t(2)))
        server.seed(SyncRecord(table: "prayer_requests", id: "c", payload: json("3"), updatedAt: t(2)))
        server.seed(SyncRecord(table: "favorites", id: "f", payload: json("4"), updatedAt: t(5)))

        try await engine.pull()
        #expect(Set(prayers.rows.keys) == ["a", "b", "c"])
        #expect(favorites.rows["f"]?.payload == json("4"))
        #expect(try engine.cursor(for: "prayer_requests") == SyncCursor(changeId: 3))
        #expect(try engine.cursor(for: "favorites") == SyncCursor(changeId: 4))

        // A second pull asks only for what's newer than the stored cursor.
        server.seed(SyncRecord(table: "prayer_requests", id: "d", payload: json("5"), updatedAt: t(9)))
        let callsBefore = server.pullCalls.count
        try await engine.pull()
        let prayerCalls = server.pullCalls[callsBefore...].filter { $0.table == "prayer_requests" }
        #expect(prayerCalls.first?.after == SyncCursor(changeId: 3))
        #expect(prayers.rows["d"] != nil)
        #expect(try engine.cursor(for: "prayer_requests") == SyncCursor(changeId: 5))
    }

    @Test("a failed pull leaves the cursor where it was")
    func failedPullKeepsCursor() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let engine = SyncEngine(context: context, transport: server, tables: [FakeTable("favorites")])
        server.seed(SyncRecord(table: "favorites", id: "f", payload: json("1"), updatedAt: t(1)))
        try await engine.pull()
        server.offline = true
        await #expect(throws: (any Error).self) { try await engine.pull() }
        #expect(try engine.cursor(for: "favorites") == SyncCursor(changeId: 1))
    }

    @Test("last write wins: a newer remote row replaces an older local one")
    func lwwRemoteWins() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let prayers = FakeTable("prayer_requests")
        let engine = SyncEngine(context: context, transport: server, tables: [prayers])
        prayers.rows["a"] = (json("\"local\""), t(1))
        server.seed(SyncRecord(table: "prayer_requests", id: "a", payload: json("\"remote\""), updatedAt: t(2)))
        try await engine.pull()
        #expect(prayers.rows["a"]?.payload == json("\"remote\""))
    }

    @Test("last write wins: a newer local row is kept over an older remote one, then pushed")
    func lwwLocalWins() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let prayers = FakeTable("prayer_requests")
        let engine = SyncEngine(context: context, transport: server, tables: [prayers])
        server.seed(SyncRecord(table: "prayer_requests", id: "a", payload: json("\"remote\""), updatedAt: t(1)))
        prayers.rows["a"] = (json("\"local\""), t(2))
        try engine.recordLocalWrite(table: "prayer_requests", id: "a", payload: json("\"local\""), updatedAt: t(2))

        try await engine.pull()
        #expect(prayers.rows["a"]?.payload == json("\"local\""))
        try await engine.sync()
        #expect(server.rows["prayer_requests"]?["a"]?.payload == json("\"local\""))
        #expect(prayers.rows["a"]?.payload == json("\"local\""))
    }

    @Test("a pending local write wins over an older remote row even before push")
    func pendingOutboxCountsForLWW() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let prayers = FakeTable("prayer_requests")
        let engine = SyncEngine(context: context, transport: server, tables: [prayers])
        // Deleted locally (row gone, tombstone queued); the server still has an older live copy.
        try engine.recordLocalWrite(table: "prayer_requests", id: "a", payload: nil, updatedAt: t(5), deletedAt: t(5))
        server.seed(SyncRecord(table: "prayer_requests", id: "a", payload: json("\"old\""), updatedAt: t(1)))
        try await engine.pull()
        #expect(prayers.rows["a"] == nil)
    }

    @Test("a newer remote row drops older pending local writes for that row")
    func remoteWinDropsStaleOutbox() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let prayers = FakeTable("prayer_requests")
        let engine = SyncEngine(context: context, transport: server, tables: [prayers])
        prayers.rows["a"] = (json("\"local\""), t(1))
        try engine.recordLocalWrite(table: "prayer_requests", id: "a", payload: json("\"local\""), updatedAt: t(1))
        try engine.recordLocalWrite(table: "prayer_requests", id: "b", payload: json("\"b\""), updatedAt: t(1))
        server.seed(SyncRecord(table: "prayer_requests", id: "a", payload: json("\"remote\""), updatedAt: t(3)))
        try await engine.pull()
        #expect(try engine.pendingChanges().map(\.rowId) == ["b"])
        #expect(prayers.rows["a"]?.payload == json("\"remote\""))
    }

    @Test("a remote soft delete removes the local row")
    func remoteSoftDelete() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let prayers = FakeTable("prayer_requests")
        let engine = SyncEngine(context: context, transport: server, tables: [prayers])
        prayers.rows["a"] = (json("\"x\""), t(1))
        server.seed(SyncRecord(table: "prayer_requests", id: "a", payload: nil, updatedAt: t(2), deletedAt: t(2)))
        try await engine.pull()
        #expect(prayers.rows["a"] == nil)
        #expect(try engine.cursor(for: "prayer_requests") == SyncCursor(changeId: 1))
    }

    @Test("a local delete is pushed as a soft delete (deleted_at set)")
    func localSoftDeletePushed() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let engine = SyncEngine(context: context, transport: server, tables: [FakeTable("prayer_requests")])
        server.seed(SyncRecord(table: "prayer_requests", id: "a", payload: json("\"x\""), updatedAt: t(1)))
        try engine.recordLocalWrite(table: "prayer_requests", id: "a", payload: nil, updatedAt: t(2), deletedAt: t(2))
        try await engine.push()
        #expect(server.rows["prayer_requests"]?["a"]?.deletedAt == t(2))
    }

    @Test("rows for tables with no adapter are skipped without failing the pull")
    func unknownTableIgnored() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let engine = SyncEngine(context: context, transport: server, tables: [FakeTable("favorites")])
        try await engine.pull()
        #expect(server.pullCalls.map(\.table) == ["favorites"])
    }

    // MARK: Late offline arrivals ([verify] round 1, finding 1)

    @Test("a row written offline earlier than the cursor's newest row still reaches other devices")
    func lateOfflineUploadIsPulled() async throws {
        let server = FakeTransport()
        let tableA = FakeTable("prayer_requests")
        let tableB = FakeTable("prayer_requests")
        let deviceA = SyncEngine(context: try makeContext(), transport: server, tables: [tableA])
        let deviceB = SyncEngine(context: try makeContext(), transport: server, tables: [tableB])

        // Device B writes "late" offline at t=100.
        tableB.rows["late"] = (json("\"b\""), t(100))
        try deviceB.recordLocalWrite(table: "prayer_requests", id: "late", payload: json("\"b\""), updatedAt: t(100))

        // Device A writes and syncs "early" at t=200, so A has already seen t=200.
        tableA.rows["early"] = (json("\"a\""), t(200))
        try deviceA.recordLocalWrite(table: "prayer_requests", id: "early", payload: json("\"a\""), updatedAt: t(200))
        try await deviceA.sync()

        // B reconnects and uploads its older-timestamped row; A must still get it.
        try await deviceB.sync()
        try await deviceA.sync()
        #expect(tableA.rows["late"]?.payload == json("\"b\""))
        #expect(tableB.rows["early"]?.payload == json("\"a\""))

        // A soft delete B made offline, stamped before A's newest row, also arrives.
        tableB.rows["late"] = nil
        try deviceB.recordLocalWrite(table: "prayer_requests", id: "late", payload: nil, updatedAt: t(150), deletedAt: t(150))
        try await deviceB.sync()
        try await deviceA.sync()
        #expect(tableA.rows["late"] == nil)
    }

    // MARK: Storage failures ([verify] round 1, finding 2)

    @Test("a failed save makes recordLocalWrite throw and leaves nothing queued")
    func recordLocalWriteSurfacesSaveFailure() async throws {
        let context = try makeContext()
        let saver = FailingSaver()
        let engine = SyncEngine(context: context, transport: FakeTransport(), tables: [], save: saver.save)
        saver.failNext = true
        #expect(throws: DiskFull.self) {
            try engine.recordLocalWrite(table: "favorites", id: "x", payload: json("{}"), updatedAt: t(1))
        }
        #expect(try engine.pendingChanges().isEmpty)
        try engine.recordLocalWrite(table: "favorites", id: "y", payload: json("{}"), updatedAt: t(2))
        #expect(try engine.pendingChanges().map(\.rowId) == ["y"])
    }

    @Test("a failed save after a push keeps the outbox and fails the sync")
    func pushSurfacesSaveFailure() async throws {
        let context = try makeContext()
        let saver = FailingSaver()
        let server = FakeTransport()
        let engine = SyncEngine(context: context, transport: server, tables: [], save: saver.save)
        try engine.recordLocalWrite(table: "favorites", id: "x", payload: json("{}"), updatedAt: t(1))
        saver.failNext = true
        await #expect(throws: DiskFull.self) { try await engine.sync() }
        #expect(try engine.pendingChanges().map(\.rowId) == ["x"])
        // The retry re-sends it; the server's LWW makes that harmless.
        try await engine.sync()
        #expect(try engine.pendingChanges().isEmpty)
    }

    @Test("a failed save during pull fails the sync and does not advance the cursor")
    func pullSurfacesSaveFailure() async throws {
        let context = try makeContext()
        let saver = FailingSaver()
        let server = FakeTransport()
        let favorites = FakeTable("favorites")
        let engine = SyncEngine(context: context, transport: server, tables: [favorites], save: saver.save)
        server.seed(SyncRecord(table: "favorites", id: "f", payload: json("1"), updatedAt: t(1)))
        try await engine.pull()
        server.seed(SyncRecord(table: "favorites", id: "g", payload: json("2"), updatedAt: t(2)))
        saver.failNext = true
        await #expect(throws: DiskFull.self) { try await engine.pull() }
        #expect(try engine.cursor(for: "favorites") == SyncCursor(changeId: 1))
        try await engine.pull()
        #expect(try engine.cursor(for: "favorites") == SyncCursor(changeId: 2))
    }

    @Test("an adapter error fails the pull and does not advance the cursor")
    func adapterErrorKeepsCursor() async throws {
        let context = try makeContext()
        let server = FakeTransport()
        let table = BrokenTable("favorites")
        let engine = SyncEngine(context: context, transport: server, tables: [table])
        server.seed(SyncRecord(table: "favorites", id: "f", payload: json("1"), updatedAt: t(1)))
        await #expect(throws: DiskFull.self) { try await engine.pull() }
        #expect(try engine.cursor(for: "favorites") == nil)
    }
}

struct DiskFull: Error {}

/// Stands in for a full disk: fails the next save, then saves normally.
@MainActor
final class FailingSaver {
    var failNext = false
    var save: SyncEngine.Save {
        { [unowned self] context in
            if self.failNext {
                self.failNext = false
                throw DiskFull()
            }
            try context.save()
        }
    }
}

@MainActor
final class BrokenTable: SyncTableAdapter {
    let table: String
    init(_ table: String) { self.table = table }
    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date? { nil }
    func apply(_ record: SyncRecord, in context: ModelContext) throws { throw DiskFull() }
    func remove(id: String, in context: ModelContext) throws { throw DiskFull() }
}

// MARK: - Scheduler
//
// TKL-901: these tests never poll against a wall-clock deadline. The fakes
// record each scheduler event (sync started or held, sleep requested, run
// finished) in order, and each test awaits the exact sequence it expects, so a
// busy machine only makes them slower, never wrong. The suite's time limit
// stops a real hang.

enum SchedulerEvent: Equatable, CustomStringConvertible {
    case syncStarted(Int)
    case syncHeld
    case sleepRequested(Duration)
    case runFinished(succeeded: Bool)

    var description: String {
        switch self {
        case .syncStarted(let n): "syncStarted(\(n))"
        case .syncHeld: "syncHeld"
        case .sleepRequested(let d): "sleepRequested(\(d))"
        case .runFinished(let ok): "runFinished(\(ok))"
        }
    }
}

/// An ordered event log the test can await one event at a time.
@MainActor
final class SchedulerEvents {
    private(set) var log: [SchedulerEvent] = []
    private var cursor = 0
    private var waiter: CheckedContinuation<SchedulerEvent, Never>?

    func record(_ event: SchedulerEvent) {
        log.append(event)
        if let waiter {
            self.waiter = nil
            cursor += 1
            waiter.resume(returning: event)
        }
    }

    func next() async -> SchedulerEvent {
        if cursor < log.count {
            defer { cursor += 1 }
            return log[cursor]
        }
        return await withCheckedContinuation { waiter = $0 }
    }

    /// The next `count` events, in the order they happened.
    func next(_ count: Int) async -> [SchedulerEvent] {
        var events: [SchedulerEvent] = []
        for _ in 0..<count { events.append(await next()) }
        return events
    }

    /// Wires the scheduler's own end-of-run event into the log.
    func observe(_ scheduler: SyncScheduler) {
        scheduler.runDidFinish = { [unowned self] ok in self.record(.runFinished(succeeded: ok)) }
    }
}

@MainActor
final class FakeSyncer: SyncRunning {
    let events: SchedulerEvents
    var calls = 0
    var failuresLeft = 0
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false
    private var running = 0
    private(set) var maxConcurrent = 0

    init(events: SchedulerEvents) { self.events = events }

    func sync() async throws {
        calls += 1
        running += 1
        maxConcurrent = max(maxConcurrent, running)
        defer { running -= 1 }
        events.record(.syncStarted(calls))
        if holdNext {
            holdNext = false
            await withCheckedContinuation {
                gate = $0
                events.record(.syncHeld)
            }
        }
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw URLError(.notConnectedToInternet)
        }
    }
}

/// Stands in for `Task.sleep`: records each request, then either returns at
/// once (`autoWake`) or waits until the test calls `wakeAll()`. A cancelled
/// sleeper throws, like `Task.sleep`.
@MainActor
final class FakeSleeper {
    let events: SchedulerEvents
    let autoWake: Bool
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nextId = 0

    init(events: SchedulerEvents, autoWake: Bool = false) {
        self.events = events
        self.autoWake = autoWake
    }

    var sleep: SyncScheduler.Sleep {
        { [self] duration in try await self.sleep(for: duration) }
    }

    var pendingCount: Int { pending.count }

    func wakeAll() {
        let sleepers = pending.values
        pending.removeAll()
        for sleeper in sleepers { sleeper.resume() }
    }

    private func sleep(for duration: Duration) async throws {
        events.record(.sleepRequested(duration))
        if autoWake { return }
        try Task.checkCancellation()
        let id = nextId
        nextId += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    private func cancel(_ id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

@Suite("SyncBackoff")
struct SyncBackoffTests {
    @Test("delays double from the base and stop at the cap")
    func doublesAndCaps() {
        let backoff = SyncBackoff(base: .seconds(2), max: .seconds(60))
        #expect(backoff.delay(afterFailures: 1) == .seconds(2))
        #expect(backoff.delay(afterFailures: 2) == .seconds(4))
        #expect(backoff.delay(afterFailures: 3) == .seconds(8))
        #expect(backoff.delay(afterFailures: 10) == .seconds(60))
        #expect(backoff.delay(afterFailures: 500) == .seconds(60))
    }
}

@MainActor
@Suite("SyncScheduler", .timeLimit(.minutes(1)))
struct SyncSchedulerTests {
    let events = SchedulerEvents()

    @Test("many local writes in quick succession trigger one debounced sync")
    func debouncesLocalWrites() async {
        let syncer = FakeSyncer(events: events)
        let sleeper = FakeSleeper(events: events)
        let scheduler = SyncScheduler(syncer: syncer, debounce: .milliseconds(60), sleep: sleeper.sleep)
        events.observe(scheduler)
        for _ in 0..<5 { scheduler.localWriteOccurred() }
        #expect(syncer.calls == 0)
        // Every write asks for the debounce delay; the first four are cancelled.
        #expect(await events.next(5) == Array(repeating: .sleepRequested(.milliseconds(60)), count: 5))
        #expect(syncer.calls == 0)
        sleeper.wakeAll()
        #expect(await events.next(2) == [.syncStarted(1), .runFinished(succeeded: true)])
        #expect(syncer.calls == 1)
        #expect(sleeper.pendingCount == 0)
    }

    @Test("foreground syncs right away")
    func foregroundSyncsNow() async {
        let syncer = FakeSyncer(events: events)
        let sleeper = FakeSleeper(events: events)
        let scheduler = SyncScheduler(syncer: syncer, debounce: .seconds(30), sleep: sleeper.sleep)
        events.observe(scheduler)
        scheduler.appDidBecomeActive()
        #expect(await events.next(2) == [.syncStarted(1), .runFinished(succeeded: true)])
        #expect(syncer.calls == 1)
        #expect(sleeper.pendingCount == 0)
    }

    @Test("manual refresh runs a sync and reports the outcome")
    func manualRefresh() async {
        let syncer = FakeSyncer(events: events)
        let sleeper = FakeSleeper(events: events)
        let scheduler = SyncScheduler(syncer: syncer, sleep: sleeper.sleep)
        events.observe(scheduler)
        #expect(await scheduler.refresh() == true)
        syncer.failuresLeft = 1
        #expect(await scheduler.refresh() == false)
        #expect(scheduler.lastError != nil)
        #expect(await events.next(5) == [
            .syncStarted(1), .runFinished(succeeded: true),
            .syncStarted(2), .runFinished(succeeded: false), .sleepRequested(.seconds(2)),
        ])
        // Let the scheduled retry run, so nothing is left waiting.
        sleeper.wakeAll()
        #expect(await events.next(2) == [.syncStarted(3), .runFinished(succeeded: true)])
        #expect(scheduler.lastError == nil)
    }

    @Test("failures retry with growing backoff, then reset on success")
    func backsOffThenResets() async {
        let syncer = FakeSyncer(events: events)
        syncer.failuresLeft = 3
        let sleeper = FakeSleeper(events: events, autoWake: true)
        let scheduler = SyncScheduler(
            syncer: syncer,
            backoff: SyncBackoff(base: .seconds(2), max: .seconds(60)),
            sleep: sleeper.sleep
        )
        events.observe(scheduler)
        scheduler.appDidBecomeActive()
        let expected: [SchedulerEvent] = [
            .syncStarted(1), .runFinished(succeeded: false), .sleepRequested(.seconds(2)),
            .syncStarted(2), .runFinished(succeeded: false), .sleepRequested(.seconds(4)),
            .syncStarted(3), .runFinished(succeeded: false), .sleepRequested(.seconds(8)),
            .syncStarted(4), .runFinished(succeeded: true),
        ]
        #expect(await events.next(expected.count) == expected)
        #expect(syncer.calls == 4)
        #expect(scheduler.consecutiveFailures == 0)
        #expect(scheduler.lastError == nil)
        #expect(!scheduler.isSyncing)
    }

    @Test("a trigger during an in-flight sync runs one more sync afterwards, never two at once")
    func coalescesWhileRunning() async {
        let syncer = FakeSyncer(events: events)
        syncer.holdNext = true
        let sleeper = FakeSleeper(events: events)
        let scheduler = SyncScheduler(syncer: syncer, sleep: sleeper.sleep)
        events.observe(scheduler)
        scheduler.appDidBecomeActive()
        #expect(await events.next(2) == [.syncStarted(1), .syncHeld])
        scheduler.appDidBecomeActive()
        scheduler.appDidBecomeActive()
        #expect(syncer.calls == 1)
        #expect(scheduler.isSyncing)
        syncer.gate?.resume()
        // One rerun inside the same run, then the run ends: nothing else follows.
        #expect(await events.next(2) == [.syncStarted(2), .runFinished(succeeded: true)])
        #expect(syncer.calls == 2)
        #expect(syncer.maxConcurrent == 1)
        #expect(!scheduler.isSyncing)
        #expect(sleeper.pendingCount == 0)
    }

    @Test("triggers return immediately (they never wait on the network)")
    func triggersDoNotBlock() async {
        let syncer = FakeSyncer(events: events)
        syncer.holdNext = true
        let sleeper = FakeSleeper(events: events)
        let scheduler = SyncScheduler(syncer: syncer, sleep: sleeper.sleep)
        events.observe(scheduler)
        scheduler.appDidBecomeActive() // would hang here if it awaited the sync
        scheduler.localWriteOccurred()
        #expect(syncer.calls == 0) // both calls returned before any sync ran
        let started = await events.next(3)
        // The run and the debounce are separate tasks, so only their own order is fixed.
        #expect(started.filter { $0 != .sleepRequested(.seconds(2)) } == [.syncStarted(1), .syncHeld])
        #expect(started.contains(.sleepRequested(.seconds(2))))
        syncer.gate?.resume()
        #expect(await events.next() == .runFinished(succeeded: true))
        sleeper.wakeAll()
        #expect(await events.next(2) == [.syncStarted(2), .runFinished(succeeded: true)])
    }
}
