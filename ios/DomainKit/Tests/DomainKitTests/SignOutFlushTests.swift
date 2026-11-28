// TKL-1084: signing out first tries one push of the outbox with a short
// timeout; if it fails, the confirmation sheet says unsynced changes will be
// removed instead of "Everything is kept in your account."
import Foundation
import SwiftData
import Testing
@testable import DomainKit

@MainActor
private func flushContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: progressSchema,
        configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

private enum FlushTransportMode: Sendable { case ack, offline, hang, reject }

private final class FlushTransport: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _pushCalls = 0
    let mode: FlushTransportMode
    init(_ mode: FlushTransportMode) { self.mode = mode }
    var pushCalls: Int { lock.withLock { _pushCalls } }

    func push(_ changes: [SyncChange]) async throws -> Set<UUID> {
        lock.withLock { _pushCalls += 1 }
        switch mode {
        case .ack: return Set(changes.map(\.id))
        case .offline: throw AppSyncTransportError.offline
        case .hang:
            try await Task.sleep(for: .seconds(30))
            return Set(changes.map(\.id))
        case .reject:
            // As AppSyncTransport: a permanent rejection counts as acknowledged.
            return Set(changes.map(\.id))
        }
    }

    func pushReportingRejections(_ changes: [SyncChange]) async throws -> SyncPushResult {
        let acknowledged = try await push(changes)
        return SyncPushResult(acknowledged: acknowledged, rejected: mode == .reject ? acknowledged : [])
    }

    func pull(table: String, after cursor: SyncCursor?, limit: Int) async throws -> [SyncRecord] { [] }
}

@MainActor
private func engine(_ transport: FlushTransport, pending: Int, in ctx: ModelContext) throws -> SyncEngine {
    let engine = SyncEngine(context: ctx, transport: transport, tables: [], subject: "sub-flush")
    for i in 0..<pending {
        try engine.recordLocalWrite(table: SyncTable.children, id: UUID().uuidString, payload: Data("{}".utf8),
                                    updatedAt: Date(timeIntervalSince1970: 1_795_200_000 + Double(i)))
    }
    return engine
}

@MainActor
@Suite("Sign-out flush (TKL-1084)")
struct SignOutFlushTests {
    @Test("an empty outbox signs out without a push")
    func emptyOutboxSkipsPush() async throws {
        let transport = FlushTransport(.ack)
        let e = try engine(transport, pending: 0, in: try flushContext())
        #expect(await SignOutFlush.run(e) == .nothingPending)
        #expect(transport.pushCalls == 0)
    }

    @Test("pending changes are pushed before sign-out")
    func pendingChangesPushed() async throws {
        let transport = FlushTransport(.ack)
        let e = try engine(transport, pending: 2, in: try flushContext())
        #expect(await SignOutFlush.run(e) == .pushed)
        #expect(try e.pendingChanges().isEmpty)
        #expect(transport.pushCalls == 1)
    }

    @Test("a failed push reports how many changes are still unsynced and keeps them")
    func failedPushReportsUnsynced() async throws {
        let transport = FlushTransport(.offline)
        let e = try engine(transport, pending: 3, in: try flushContext())
        #expect(await SignOutFlush.run(e) == .unsynced(count: 3))
        #expect(try e.pendingChanges().count == 3)
        #expect(transport.pushCalls == 1)
    }

    @Test("a push that hangs gives up after the timeout and keeps the outbox")
    func hangingPushTimesOut() async throws {
        let transport = FlushTransport(.hang)
        let e = try engine(transport, pending: 1, in: try flushContext())
        let clock = ContinuousClock()
        let started = clock.now
        let outcome = await SignOutFlush.run(e, timeout: .milliseconds(100))
        #expect(outcome == .unsynced(count: 1))
        // Well under the transport's 30 s hang (the full suite keeps the main actor busy).
        #expect(clock.now - started < .seconds(20))
        // A late acknowledgement after the timeout never removes entries.
        try await Task.sleep(for: .milliseconds(50))
        #expect(try e.pendingChanges().count == 1)
    }

    @Test("a permanently rejected change is reported as unsynced and kept for the sheet")
    func rejectedPushReportsUnsynced() async throws {
        let transport = FlushTransport(.reject)
        let e = try engine(transport, pending: 2, in: try flushContext())
        #expect(await SignOutFlush.run(e) == .unsynced(count: 2))
        #expect(try e.pendingChanges().count == 2)
        // Ordinary sync still drops permanent rejections so they never block later writes.
        try await e.push()
        #expect(try e.pendingChanges().isEmpty)
    }

    @Test("a CLOCK_SKEW rejection from the real AppSync transport is not reported as pushed")
    func appSyncClockSkewRejectionIsUnsynced() async throws {
        final class FakeHTTP: @unchecked Sendable {
            private let lock = NSLock()
            private var _calls = 0
            var calls: Int { lock.withLock { _calls } }
            func fetch(_ req: URLRequest) async throws -> (Data, URLResponse) {
                lock.withLock { _calls += 1 }
                let json = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any]
                let changes = ((json?["variables"] as? [String: Any])?["changes"] as? [[String: Any]]) ?? []
                // The first change is rejected for clock skew, the rest are accepted.
                let results = changes.enumerated().map { i, c -> String in
                    let id = c["id"] as? String ?? ""
                    return i == 0
                        ? #"{"id":"\#(id)","status":"REJECTED","reason":"CLOCK_SKEW"}"#
                        : #"{"id":"\#(id)","status":"ACCEPTED","reason":null}"#
                }
                let body = #"{"data":{"pushSync":[\#(results.joined(separator: ","))]}}"#
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), resp)
            }
        }
        let http = FakeHTTP()
        var rejectedReasons: [String?] = []
        let lock = NSLock()
        let transport = AppSyncTransport(
            endpoint: URL(string: "https://sync.example.com/graphql")!,
            tokenProvider: { _ in "tok" },
            fetch: { try await http.fetch($0) },
            onRejected: { _, reason in lock.withLock { rejectedReasons.append(reason) } }
        )
        let ctx = try flushContext()
        let e = SyncEngine(context: ctx, transport: transport, tables: [], subject: "sub-flush")
        for i in 0..<3 {
            try e.recordLocalWrite(table: SyncTable.children, id: UUID().uuidString.lowercased(), payload: Data("{}".utf8),
                                   updatedAt: Date(timeIntervalSince1970: 1_795_200_000 + Double(i)))
        }
        let rejectedId = try #require(try e.pendingChanges().first?.id)

        #expect(await SignOutFlush.run(e) == .unsynced(count: 1))
        // The accepted two left the outbox; the rejected one stays, so cancelling keeps it.
        #expect(try e.pendingChanges().map(\.id) == [rejectedId])
        #expect(lock.withLock { rejectedReasons } == ["CLOCK_SKEW"])
        #expect(SignOutConfirmationCopy.confirmTitle(for: .unsynced(count: 1)) == "Sign out anyway")
        #expect(http.calls == 1)
    }

    @Test("the default timeout is short")
    func defaultTimeoutIsShort() {
        #expect(SignOutFlush.defaultTimeout <= .seconds(5))
        #expect(SignOutFlush.defaultTimeout >= .seconds(1))
    }

    @Test("the confirmation sheet keeps its promise only when nothing is left unsynced")
    func confirmationCopy() {
        let kept = SignOutConfirmationCopy.body(for: nil)
        #expect(kept.hasPrefix("Everything is kept in your account."))
        #expect(SignOutConfirmationCopy.body(for: .pushed) == kept)
        #expect(SignOutConfirmationCopy.body(for: .nothingPending) == kept)
        #expect(SignOutConfirmationCopy.confirmTitle(for: nil) == "Sign out")

        let one = SignOutConfirmationCopy.body(for: .unsynced(count: 1))
        #expect(!one.contains("Everything is kept"))
        #expect(one.contains("1 change on this iPhone hasn’t synced yet"))
        #expect(one.contains("will be removed"))
        let many = SignOutConfirmationCopy.body(for: .unsynced(count: 4))
        #expect(many.contains("4 changes on this iPhone haven’t synced yet"))
        #expect(SignOutConfirmationCopy.confirmTitle(for: .unsynced(count: 4)) == "Sign out anyway")
    }
}
