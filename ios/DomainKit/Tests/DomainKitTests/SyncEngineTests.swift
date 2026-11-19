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

@MainActor
final class FakeSyncer: SyncRunning {
    var calls = 0
    var failuresLeft = 0
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false

    func sync() async throws {
        calls += 1
        if holdNext {
            holdNext = false
            await withCheckedContinuation { gate = $0 }
        }
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw URLError(.notConnectedToInternet)
        }
    }
}

final class WaitLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Duration] = []
    var values: [Duration] { lock.withLock { stored } }
    func append(_ d: Duration) { lock.withLock { stored.append(d) } }
}

@MainActor
private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
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
@Suite("SyncScheduler")
struct SyncSchedulerTests {
    @Test("many local writes in quick succession trigger one debounced sync")
    func debouncesLocalWrites() async {
        let syncer = FakeSyncer()
        let scheduler = SyncScheduler(syncer: syncer, debounce: .milliseconds(60))
        for _ in 0..<5 { scheduler.localWriteOccurred() }
        #expect(syncer.calls == 0)
        await waitUntil { syncer.calls >= 1 }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(syncer.calls == 1)
    }

    @Test("foreground syncs right away")
    func foregroundSyncsNow() async {
        let syncer = FakeSyncer()
        let scheduler = SyncScheduler(syncer: syncer, debounce: .seconds(30))
        scheduler.appDidBecomeActive()
        await waitUntil { syncer.calls == 1 }
        #expect(syncer.calls == 1)
    }

    @Test("manual refresh runs a sync and reports the outcome")
    func manualRefresh() async {
        let syncer = FakeSyncer()
        let scheduler = SyncScheduler(syncer: syncer)
        #expect(await scheduler.refresh() == true)
        syncer.failuresLeft = 1
        #expect(await scheduler.refresh() == false)
        #expect(scheduler.lastError != nil)
    }

    @Test("failures retry with growing backoff, then reset on success")
    func backsOffThenResets() async {
        let syncer = FakeSyncer()
        syncer.failuresLeft = 3
        let waits = WaitLog()
        let scheduler = SyncScheduler(
            syncer: syncer,
            backoff: SyncBackoff(base: .seconds(2), max: .seconds(60)),
            sleep: { duration in
                waits.append(duration)
            }
        )
        scheduler.appDidBecomeActive()
        await waitUntil { syncer.calls == 4 }
        #expect(syncer.calls == 4)
        #expect(waits.values == [.seconds(2), .seconds(4), .seconds(8)])
        await waitUntil { scheduler.consecutiveFailures == 0 }
        #expect(scheduler.consecutiveFailures == 0)
        #expect(scheduler.lastError == nil)
    }

    @Test("a trigger during an in-flight sync runs one more sync afterwards, never two at once")
    func coalescesWhileRunning() async {
        let syncer = FakeSyncer()
        syncer.holdNext = true
        let scheduler = SyncScheduler(syncer: syncer)
        scheduler.appDidBecomeActive()
        await waitUntil { syncer.gate != nil }
        scheduler.appDidBecomeActive()
        scheduler.appDidBecomeActive()
        #expect(syncer.calls == 1)
        #expect(scheduler.isSyncing)
        syncer.gate?.resume()
        await waitUntil { syncer.calls == 2 && !scheduler.isSyncing }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(syncer.calls == 2)
    }

    @Test("triggers return immediately (they never wait on the network)")
    func triggersDoNotBlock() async {
        let syncer = FakeSyncer()
        syncer.holdNext = true
        let scheduler = SyncScheduler(syncer: syncer)
        scheduler.appDidBecomeActive() // would hang here if it awaited the sync
        scheduler.localWriteOccurred()
        await waitUntil { syncer.gate != nil }
        syncer.gate?.resume()
    }
}
