// TKL-1068: Account sync transport (AppSync), per-subject outbox/cursor
// isolation, sign-out invalidation, and bidirectional children + catechism
// progress mapping (round trip, co-guardian shared children, LWW on milestones).
import Foundation
import SwiftData
import Testing
@testable import DomainKit

private func stamp(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_795_000_000 + seconds)
}

@MainActor
private func makeProgressContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: progressSchema,
        configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

// MARK: - Config & Timestamps

@Suite("AccountSyncConfig")
struct AccountSyncConfigTests {
    @Test("reads custom.account_sync_url from amplify_outputs JSON")
    func readsSyncURL() {
        let json = """
        {
          "version": "1.4",
          "auth": { "aws_region": "us-east-1" },
          "custom": {
            "apple_start_url": "https://example.lambda-url.us-east-1.on.aws/",
            "account_sync_url": "https://abc123.appsync-api.us-east-1.amazonaws.com/graphql"
          }
        }
        """
        let url = AccountSyncConfig.syncURL(fromAmplifyOutputsData: Data(json.utf8))
        #expect(url?.absoluteString == "https://abc123.appsync-api.us-east-1.amazonaws.com/graphql")
    }

    @Test("returns nil when custom.account_sync_url is missing or invalid")
    func returnsNilWhenMissing() {
        let missing = Data(#"{"version":"1.4","custom":{}}"#.utf8)
        let bad = Data(#"{"version":"1.4","custom":{"account_sync_url":"not a url ://"}}"#.utf8)
        #expect(AccountSyncConfig.syncURL(fromAmplifyOutputsData: missing) == nil)
        #expect(AccountSyncConfig.syncURL(fromAmplifyOutputsData: bad) == nil)
    }
}

@Suite("SyncTimestamp")
struct SyncTimestampTests {
    @Test("formats UTC ISO 8601 with millisecond precision and parses round trip")
    func formatsAndParses() throws {
        let date = Date(timeIntervalSince1970: 1_795_168_800.123)
        let formatted = SyncTimestamp.format(date)
        #expect(formatted.hasSuffix("Z"))
        #expect(formatted.range(of: #"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$"#, options: .regularExpression) != nil)
        let parsed = try #require(SyncTimestamp.parse(formatted))
        #expect(parsed == date)
        #expect(SyncTimestamp.parse("2026-11-21T10:00:00Z") != nil)
    }
}

// MARK: - AppSyncTransport

private final class MockAppSyncHTTP: @unchecked Sendable {
    struct CapturedRequest: Sendable {
        let url: URL?
        let authorization: String?
        let bodyData: Data

        var body: [String: Any] {
            (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
        }
        var variables: [String: Any]? { body["variables"] as? [String: Any] }
        var query: String? { body["query"] as? String }
    }

    var requests: [CapturedRequest] = []
    var responses: [(statusCode: Int, body: String)] = []
    var tokenRefreshCalls: [Bool] = []
    var tokens: [String?] = ["token-initial"]
    var online = true

    func nextToken(forceRefresh: Bool) -> String? {
        tokenRefreshCalls.append(forceRefresh)
        if tokens.count > 1 { return tokens.removeFirst() }
        return tokens.first ?? nil
    }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(CapturedRequest(
            url: request.url,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            bodyData: request.httpBody ?? Data()
        ))
        let next: (statusCode: Int, body: String) = responses.isEmpty
            ? (statusCode: 200, body: #"{"data":{}}"#)
            : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com/graphql")!,
            statusCode: next.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(next.body.utf8), response)
    }
}

@Suite("AppSyncTransport")
struct AppSyncTransportTests {
    private let endpoint = URL(string: "https://sync.example.com/graphql")!

    @Test("push chunks at max 20 per call, sends lowercase UUIDs, drops ACCEPTED/REJECTED and keeps RETRY")
    func pushHandlesMax20AndStatuses() async throws {
        let http = MockAppSyncHTTP()
        let childId = UUID()
        let changes: [SyncChange] = (0..<22).map { i in
            SyncChange(
                id: UUID(),
                table: SyncTable.catechismPacing,
                rowId: UUID().uuidString,
                childId: childId.uuidString,
                payload: Data(#"{"catechism_slug":"catechizing-shorter-catechism","current_question":\#(i + 1)}"#.utf8),
                updatedAt: stamp(Double(i)),
                deletedAt: nil
            )
        }
        // First 20: 19 ACCEPTED, 1 REJECTED (UNAUTHORIZED) -> all 20 acknowledged so outbox drops them.
        let batch1Results = changes[0..<20].enumerated().map { idx, change in
            if idx == 5 {
                return #"{"id":"\#(change.id.uuidString.lowercased())","status":"REJECTED","reason":"UNAUTHORIZED"}"#
            }
            return #"{"id":"\#(change.id.uuidString.lowercased())","status":"ACCEPTED","reason":null}"#
        }.joined(separator: ",")
        // Remaining 2: first RETRY (CONTENTION), second RETRY (CONTENTION) -> kept in outbox.
        let batch2Results = changes[20..<22].map { change in
            #"{"id":"\#(change.id.uuidString.lowercased())","status":"RETRY","reason":"CONTENTION"}"#
        }.joined(separator: ",")

        http.responses = [
            (200, #"{"data":{"pushSync":[\#(batch1Results)]}}"#),
            (200, #"{"data":{"pushSync":[\#(batch2Results)]}}"#),
        ]

        let transport = AppSyncTransport(
            endpoint: endpoint,
            tokenProvider: { force in http.nextToken(forceRefresh: force) },
            isOnline: { http.online },
            fetch: { try await http.fetch($0) }
        )

        let acknowledged = try await transport.push(changes)
        #expect(http.requests.count == 2)
        let firstBatch = try #require(http.requests[0].variables?["changes"] as? [[String: Any]])
        let secondBatch = try #require(http.requests[1].variables?["changes"] as? [[String: Any]])
        #expect(firstBatch.count == 20)
        #expect(secondBatch.count == 2)
        #expect(firstBatch[0]["row_id"] as? String == changes[0].rowId.lowercased())
        #expect(firstBatch[0]["child_id"] as? String == childId.uuidString.lowercased())
        #expect(http.requests[0].authorization == "token-initial")

        // First 20 (19 ACCEPTED + 1 REJECTED) acknowledged; last 2 (RETRY) not acknowledged.
        #expect(acknowledged == Set(changes[0..<20].map(\.id)))
    }

    @Test("push omits payload for tombstones and sends deleted_at")
    func pushTombstoneOmitsPayload() async throws {
        let http = MockAppSyncHTTP()
        let childId = UUID()
        let opId = UUID()
        let change = SyncChange(
            id: opId,
            table: SyncTable.children,
            rowId: childId.uuidString,
            childId: childId.uuidString,
            payload: nil,
            updatedAt: stamp(10),
            deletedAt: stamp(10)
        )
        http.responses = [
            (200, #"{"data":{"pushSync":[{"id":"\#(opId.uuidString.lowercased())","status":"ACCEPTED","reason":null}]}}"#),
        ]
        let transport = AppSyncTransport(
            endpoint: endpoint,
            tokenProvider: { force in http.nextToken(forceRefresh: force) },
            fetch: { try await http.fetch($0) }
        )
        let acked = try await transport.push([change])
        #expect(acked == [opId])
        let sent = try #require((http.requests[0].variables?["changes"] as? [[String: Any]])?.first)
        #expect(sent["deleted_at"] as? String != nil)
        #expect(sent["payload"] == nil || sent["payload"] is NSNull)
    }

    @Test("pull decodes ascending records, tombstones, child_id and Int64 change_id, and clamps limit to 100")
    func pullDecodesRecordsAndTombstones() async throws {
        let http = MockAppSyncHTTP()
        let childA = UUID().uuidString.lowercased()
        let childB = UUID().uuidString.lowercased()
        http.responses = [
            (200, """
            {
              "data": {
                "pullSync": [
                  {
                    "table": "children",
                    "id": "\(childA)",
                    "child_id": "\(childA)",
                    "updated_at": "2026-11-21T10:00:00.000Z",
                    "deleted_at": null,
                    "payload": "{\\"name\\":\\"Samuel\\",\\"created_at\\":\\"2026-11-21T10:00:00.000Z\\"}",
                    "change_id": "41"
                  },
                  {
                    "table": "children",
                    "id": "\(childB)",
                    "child_id": "\(childB)",
                    "updated_at": "2026-11-21T10:05:00.000Z",
                    "deleted_at": "2026-11-21T10:05:00.000Z",
                    "payload": null,
                    "change_id": "42"
                  }
                ]
              }
            }
            """),
        ]
        let transport = AppSyncTransport(
            endpoint: endpoint,
            tokenProvider: { force in http.nextToken(forceRefresh: force) },
            fetch: { try await http.fetch($0) }
        )
        let records = try await transport.pull(table: "children", after: SyncCursor(changeId: 40), limit: 500)
        #expect(http.requests[0].variables?["after"] as? String == "40")
        #expect(http.requests[0].variables?["limit"] as? Int == 100)
        #expect(records.count == 2)
        #expect(records[0].id == childA)
        #expect(records[0].childId == childA)
        #expect(records[0].changeId == 41)
        #expect(!records[0].isDeleted)
        #expect(records[1].id == childB)
        #expect(records[1].isDeleted)
        #expect(records[1].payload == nil)
        #expect(records[1].changeId == 42)
    }

    @Test("HTTP 401 refreshes the Cognito token once and retries")
    func refreshesTokenOn401() async throws {
        let http = MockAppSyncHTTP()
        http.tokens = ["expired-token", "fresh-token"]
        http.responses = [
            (401, #"{"errors":[{"errorType":"UnauthorizedException","message":"Token expired"}]}"#),
            (200, #"{"data":{"pullSync":[]}}"#),
        ]
        let transport = AppSyncTransport(
            endpoint: endpoint,
            tokenProvider: { force in http.nextToken(forceRefresh: force) },
            fetch: { try await http.fetch($0) }
        )
        let records = try await transport.pull(table: "children", after: nil, limit: 50)
        #expect(records.isEmpty)
        #expect(http.tokenRefreshCalls == [false, true])
        #expect(http.requests.map(\.authorization) == ["expired-token", "fresh-token"])
    }

    @Test("does not make network calls when signed out or offline")
    func neverCallsWhenSignedOutOrOffline() async {
        let http = MockAppSyncHTTP()
        http.tokens = [nil]
        let transport = AppSyncTransport(
            endpoint: endpoint,
            tokenProvider: { force in http.nextToken(forceRefresh: force) },
            isOnline: { http.online },
            fetch: { try await http.fetch($0) }
        )
        await #expect(throws: AppSyncTransportError.unauthenticated) {
            _ = try await transport.pull(table: "children", after: nil, limit: 50)
        }
        #expect(http.requests.isEmpty)

        http.tokens = ["valid-token"]
        http.online = false
        await #expect(throws: AppSyncTransportError.offline) {
            _ = try await transport.pull(table: "children", after: nil, limit: 50)
        }
        #expect(http.requests.isEmpty)
    }
}

// MARK: - Per-subject isolation & sign-out invalidation

private final class HeldPullTransport: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[SyncRecord], any Error>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false

    func waitUntilPullEntered() async {
        await withCheckedContinuation { cont in
            let alreadyEntered: Bool = lock.withLock {
                if hasEntered { return true }
                enteredContinuation = cont
                return false
            }
            if alreadyEntered { cont.resume() }
        }
    }

    func finishPull(with records: [SyncRecord]) {
        let cont = lock.withLock { () -> CheckedContinuation<[SyncRecord], any Error>? in
            let c = continuation
            continuation = nil
            return c
        }
        cont?.resume(returning: records)
    }

    func push(_ changes: [SyncChange]) async throws -> Set<UUID> {
        Set(changes.map(\.id))
    }

    func pull(table: String, after cursor: SyncCursor?, limit: Int) async throws -> [SyncRecord] {
        try await withCheckedThrowingContinuation { cont in
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                continuation = cont
                hasEntered = true
                let w = enteredContinuation
                enteredContinuation = nil
                return w
            }
            waiter?.resume()
        }
    }
}

@MainActor
@Suite("Subject isolation & sign-out invalidation")
struct SubjectIsolationTests {
    @Test("cursors and outbox are isolated per Cognito subject and cleared on sign-out")
    func isolatesAndClearsPerSubject() async throws {
        let context = try makeProgressContext()
        let server = FakeAppSyncServer()

        let engineA = SyncEngine(
            context: context,
            transport: server.transport(for: "sub-a"),
            tables: ChildProgressSyncAdapters.all(),
            subject: "sub-a",
            pushBatchSize: 20,
            pullPageSize: 50
        )
        let storeA = LocalProgressStore(context: context, syncSubject: "sub-a")
        _ = try storeA.addChild(name: "Samuel")
        #expect(try engineA.pendingChanges().count == 1)

        // Subject B sees neither Subject A's outbox nor cursors.
        let engineB = SyncEngine(
            context: context,
            transport: server.transport(for: "sub-b"),
            tables: ChildProgressSyncAdapters.all(),
            subject: "sub-b",
            pushBatchSize: 20,
            pullPageSize: 50
        )
        #expect(try engineB.pendingChanges().isEmpty)
        #expect(try engineB.cursor(for: SyncTable.children) == nil)

        try await engineA.sync()
        #expect(try engineA.cursor(for: SyncTable.children) != nil)
        #expect(try engineB.cursor(for: SyncTable.children) == nil)

        // Clearing Subject A's state on sign-out removes its cursors and outbox even if A signs back in.
        _ = try storeA.addChild(name: "Thomas")
        #expect(try engineA.pendingChanges().count == 1)
        try SyncEngine.clearAccountState(for: "sub-a", in: context)
        #expect(try engineA.pendingChanges().isEmpty)
        #expect(try engineA.cursor(for: SyncTable.children) == nil)
    }

    @Test("signing out stops and invalidates an in-flight pull so late responses never apply or advance cursors")
    func signOutInvalidatesInFlightSync() async throws {
        let context = try makeProgressContext()
        let held = HeldPullTransport()
        let engine = SyncEngine(
            context: context,
            transport: held,
            tables: ChildProgressSyncAdapters.all(),
            subject: "sub-a",
            pushBatchSize: 20,
            pullPageSize: 50
        )
        let scheduler = SyncScheduler(syncer: engine, debounce: .seconds(60))
        scheduler.appDidBecomeActive()
        await held.waitUntilPullEntered()

        // Sign out while pull is in flight.
        scheduler.stop()
        engine.invalidate()
        try SyncEngine.clearAccountState(for: "sub-a", in: context)

        // Late network response arrives after sign-out.
        let childId = UUID().uuidString.lowercased()
        let payload = Data(#"{"name":"Ghost","created_at":"2026-11-21T10:00:00.000Z"}"#.utf8)
        held.finishPull(with: [
            SyncRecord(
                table: SyncTable.children,
                id: childId,
                childId: childId,
                payload: payload,
                updatedAt: stamp(10),
                deletedAt: nil,
                changeId: 99
            ),
        ])
        // Let any cancelled tasks settle.
        try await Task.sleep(for: .milliseconds(50))

        #expect(try context.fetch(FetchDescriptor<LocalChild>()).isEmpty)
        #expect(try engine.cursor(for: SyncTable.children) == nil)
        #expect(scheduler.lastSuccessAt == nil)
    }
}

// MARK: - Bidirectional children & progress sync (round trip, shared child, LWW)

/// Multi-subject in-memory server that mimics infra/lambda/sync/service.mjs
/// (ownership, co-guardian access, LWW on updated_at, per-subject monotonic change_id).
private final class FakeAppSyncServer: @unchecked Sendable {
    struct StoredRow {
        var record: SyncRecord
    }

    private let lock = NSLock()
    private var rows: [String: [String: StoredRow]] = [:] // table -> rowId -> row
    private var ownerByChild: [String: String] = [:]
    private var guardiansByChild: [String: Set<String>] = [:]
    private var streamBySubject: [String: [SyncRecord]] = [:]
    private var seqBySubject: [String: Int64] = [:]

    func grantCoGuardian(childId: UUID, guardianSubject: String) {
        lock.withLock {
            let cid = childId.uuidString.lowercased()
            guardiansByChild[cid, default: []].insert(guardianSubject)
            // Backfill existing rows for this child into guardian's stream.
            for tableRows in rows.values {
                for stored in tableRows.values where stored.record.childId == cid {
                    publish(stored.record, to: guardianSubject)
                }
            }
        }
    }

    func transport(for subject: String) -> any SyncTransport {
        SubjectTransport(server: self, subject: subject)
    }

    private func canAccess(childId: String, subject: String) -> Bool {
        ownerByChild[childId] == subject || (guardiansByChild[childId]?.contains(subject) ?? false)
    }

    private func publish(_ record: SyncRecord, to subject: String) {
        let next = (seqBySubject[subject] ?? 0) + 1
        seqBySubject[subject] = next
        var rec = record
        rec.changeId = next
        streamBySubject[subject, default: []].append(rec)
    }

    func push(subject: String, changes: [SyncChange]) -> Set<UUID> {
        lock.withLock {
            var acked = Set<UUID>()
            for change in changes {
                let rowId = change.rowId.lowercased()
                let cid = (change.childId ?? (change.table == SyncTable.children ? rowId : "")).lowercased()
                guard !cid.isEmpty else { acked.insert(change.id); continue }

                let creating = ownerByChild[cid] == nil && change.table == SyncTable.children && change.deletedAt == nil
                if creating {
                    ownerByChild[cid] = subject
                } else if !canAccess(childId: cid, subject: subject) {
                    acked.insert(change.id) // REJECTED (UNAUTHORIZED) -> dropped
                    continue
                } else if change.table == SyncTable.children && change.deletedAt != nil && ownerByChild[cid] != subject {
                    acked.insert(change.id) // co-guardian cannot tombstone child profile
                    continue
                }

                let existing = rows[change.table]?[rowId]?.record
                if let existing, existing.updatedAt >= change.updatedAt {
                    acked.insert(change.id) // ACCEPTED no-op
                    continue
                }

                let record = SyncRecord(
                    table: change.table,
                    id: rowId,
                    childId: cid,
                    payload: change.payload,
                    updatedAt: change.updatedAt,
                    deletedAt: change.deletedAt,
                    changeId: 0
                )
                rows[change.table, default: [:]][rowId] = StoredRow(record: record)

                var recipients = guardiansByChild[cid] ?? []
                if let owner = ownerByChild[cid] { recipients.insert(owner) }
                for recipient in recipients {
                    publish(record, to: recipient)
                }
                acked.insert(change.id)
            }
            return acked
        }
    }

    func pull(subject: String, table: String, after cursor: SyncCursor?, limit: Int) -> [SyncRecord] {
        lock.withLock {
            let afterId = cursor?.changeId ?? 0
            // Return latest revision for each row appearing after cursor.
            let entries = (streamBySubject[subject] ?? [])
                .filter { $0.table == table && $0.changeId > afterId }
                .sorted { $0.changeId < $1.changeId }
            var result: [SyncRecord] = []
            for entry in entries {
                guard let current = rows[table]?[entry.id]?.record,
                      current.updatedAt == entry.updatedAt,
                      canAccess(childId: entry.childId ?? "", subject: subject) else { continue }
                result.append(entry)
                if result.count >= limit { break }
            }
            return result
        }
    }

    private struct SubjectTransport: SyncTransport {
        let server: FakeAppSyncServer
        let subject: String

        func push(_ changes: [SyncChange]) async throws -> Set<UUID> {
            server.push(subject: subject, changes: changes)
        }

        func pull(table: String, after cursor: SyncCursor?, limit: Int) async throws -> [SyncRecord] {
            server.pull(subject: subject, table: table, after: cursor, limit: limit)
        }
    }
}

@MainActor
@Suite("Children & catechism progress sync")
struct ChildProgressSyncTests {
    @Test("round-trips LocalChild, assignment, pacing and milestones between two devices and handles deletes")
    func roundTripsChildrenAndProgress() async throws {
        let server = FakeAppSyncServer()
        let subject = "11111111-1111-4111-8111-111111111111"

        let ctx1 = try makeProgressContext()
        let store1 = LocalProgressStore(context: ctx1, syncSubject: subject)
        let engine1 = SyncEngine(
            context: ctx1,
            transport: server.transport(for: subject),
            tables: ChildProgressSyncAdapters.all(),
            subject: subject,
            pushBatchSize: 20,
            pullPageSize: 50
        )

        let ctx2 = try makeProgressContext()
        let store2 = LocalProgressStore(context: ctx2, syncSubject: subject)
        let engine2 = SyncEngine(
            context: ctx2,
            transport: server.transport(for: subject),
            tables: ChildProgressSyncAdapters.all(),
            subject: subject,
            pushBatchSize: 20,
            pullPageSize: 50
        )

        // Device 1 adds Samuel (age 9), starts Shorter Catechism at Q. 1, and advances twice (Q. 1 -> Q. 3).
        let samuel = try store1.addChild(name: "Samuel", age: 9)
        _ = store1.resumeOrStartTrack(childId: samuel.id, catechismId: "WSC")
        _ = store1.advanceQuestion(childId: samuel.id, catechismId: "WSC", totalQuestions: 107)
        _ = store1.advanceQuestion(childId: samuel.id, catechismId: "WSC", totalQuestions: 107)

        try await engine1.sync()
        try await engine2.sync()

        let pulledChildren = try ctx2.fetch(FetchDescriptor<LocalChild>())
        #expect(pulledChildren.count == 1)
        let pulledChild = try #require(pulledChildren.first)
        #expect(pulledChild.id == samuel.id)
        #expect(pulledChild.name == "Samuel")
        #expect(pulledChild.age == 9)
        #expect(store2.activeChildId == samuel.id)

        let pulledTrack = try #require(store2.activeTrack(childId: samuel.id))
        #expect(pulledTrack.catechismId == "WSC")
        #expect(pulledTrack.startedAtQuestion == 1)
        #expect(pulledTrack.currentQuestion == 3)
        #expect(Set(pulledTrack.milestones.keys) == ["1", "2"])
        #expect(pulledTrack.milestones["1"]?.state == "introduced")
        #expect(pulledTrack.milestones["2"]?.reviewCount == 0)

        // Device 2 deletes Samuel -> tombstones for child + progress rows remove Samuel on Device 1.
        try store2.deleteChild(childId: samuel.id)
        try await engine2.sync()
        try await engine1.sync()

        #expect(try ctx1.fetch(FetchDescriptor<LocalChild>()).isEmpty)
        #expect(try ctx1.fetch(FetchDescriptor<ChildCatechismTrack>()).isEmpty)
    }

    @Test("a child shared by a co-guardian appears and edits sync both ways using the server's row IDs")
    func coGuardianSharedChildSyncsBothWays() async throws {
        let server = FakeAppSyncServer()
        let ownerSub = "11111111-1111-4111-8111-111111111111"
        let guardianSub = "22222222-2222-4222-8222-222222222222"

        let ownerCtx = try makeProgressContext()
        let ownerStore = LocalProgressStore(context: ownerCtx, syncSubject: ownerSub)
        let ownerEngine = SyncEngine(
            context: ownerCtx,
            transport: server.transport(for: ownerSub),
            tables: ChildProgressSyncAdapters.all(),
            subject: ownerSub,
            pushBatchSize: 20,
            pullPageSize: 50
        )

        // Owner creates a child and advances to Q. 2.
        let ruth = try ownerStore.addChild(name: "Ruth", age: 7)
        _ = ownerStore.resumeOrStartTrack(childId: ruth.id, catechismId: "WSC")
        _ = ownerStore.advanceQuestion(childId: ruth.id, catechismId: "WSC", totalQuestions: 107)
        try await ownerEngine.sync()

        // Backend provisions co-guardian membership (app never creates invites).
        server.grantCoGuardian(childId: ruth.id, guardianSubject: guardianSub)

        let guardianCtx = try makeProgressContext()
        let guardianStore = LocalProgressStore(context: guardianCtx, syncSubject: guardianSub)
        let guardianEngine = SyncEngine(
            context: guardianCtx,
            transport: server.transport(for: guardianSub),
            tables: ChildProgressSyncAdapters.all(),
            subject: guardianSub,
            pushBatchSize: 20,
            pullPageSize: 50
        )

        try await guardianEngine.sync()
        let guardianChildren = try guardianCtx.fetch(FetchDescriptor<LocalChild>())
        #expect(guardianChildren.map(\.name) == ["Ruth"])
        #expect(guardianStore.activeTrack(childId: ruth.id)?.currentQuestion == 2)

        // Co-guardian advances Ruth to Q. 3; owner pulls the update.
        _ = guardianStore.advanceQuestion(childId: ruth.id, catechismId: "WSC", totalQuestions: 107)
        try await guardianEngine.sync()
        try await ownerEngine.sync()

        let ownerTrack = try #require(ownerStore.activeTrack(childId: ruth.id))
        #expect(ownerTrack.currentQuestion == 3)
        #expect(Set(ownerTrack.milestones.keys) == ["1", "2"])
    }

    @Test("reuses a server-assigned non-deterministic row_id when editing a pulled row")
    func reusesServerAssignedRowId() async throws {
        let server = FakeAppSyncServer()
        let ownerSub = "11111111-1111-4111-8111-111111111111"
        let guardianSub = "22222222-2222-4222-8222-222222222222"
        let childId = UUID()
        let customPacingRowId = UUID().uuidString.lowercased()

        // Owner pushes child + a pacing row with an arbitrary (non-UUIDv5) row_id.
        _ = server.push(subject: ownerSub, changes: [
            SyncChange(
                id: UUID(), table: SyncTable.children, rowId: childId.uuidString.lowercased(),
                childId: childId.uuidString.lowercased(),
                payload: Data(#"{"name":"Hannah","created_at":"2026-11-21T10:00:00.000Z"}"#.utf8),
                updatedAt: stamp(1)
            ),
            SyncChange(
                id: UUID(), table: SyncTable.catechismPacing, rowId: customPacingRowId,
                childId: childId.uuidString.lowercased(),
                payload: Data(#"{"catechism_slug":"catechizing-shorter-catechism","current_question":4}"#.utf8),
                updatedAt: stamp(2)
            ),
        ])
        server.grantCoGuardian(childId: childId, guardianSubject: guardianSub)

        let ctx = try makeProgressContext()
        let store = LocalProgressStore(context: ctx, syncSubject: guardianSub)
        let engine = SyncEngine(
            context: ctx, transport: server.transport(for: guardianSub),
            tables: ChildProgressSyncAdapters.all(), subject: guardianSub,
            pushBatchSize: 20, pullPageSize: 50
        )
        try await engine.sync()
        #expect(store.activeTrack(childId: childId)?.currentQuestion == 4)

        // Co-guardian jumps to Q. 6 -> outbox entry must reuse `customPacingRowId`.
        _ = store.jumpToQuestion(childId: childId, catechismId: "WSC", questionNumber: 6, totalQuestions: 107, now: stamp(5))
        let pacingChange = try #require(try engine.pendingChanges().first(where: { $0.table == SyncTable.catechismPacing }))
        #expect(pacingChange.rowId == customPacingRowId)
    }

    @Test("LWW on a milestone edited on two devices keeps the newer write even when pacing also changed")
    func lwwMilestoneAcrossTwoDevices() async throws {
        let server = FakeAppSyncServer()
        let subject = "11111111-1111-4111-8111-111111111111"

        let ctx1 = try makeProgressContext()
        let store1 = LocalProgressStore(context: ctx1, syncSubject: subject)
        let engine1 = SyncEngine(
            context: ctx1,
            transport: server.transport(for: subject),
            tables: ChildProgressSyncAdapters.all(),
            subject: subject,
            pushBatchSize: 20,
            pullPageSize: 50
        )

        let ctx2 = try makeProgressContext()
        let store2 = LocalProgressStore(context: ctx2, syncSubject: subject)
        let engine2 = SyncEngine(
            context: ctx2,
            transport: server.transport(for: subject),
            tables: ChildProgressSyncAdapters.all(),
            subject: subject,
            pushBatchSize: 20,
            pullPageSize: 50
        )

        let child = try store1.addChild(name: "Thomas", now: stamp(1))
        _ = store1.resumeOrStartTrack(childId: child.id, catechismId: "WSC", now: stamp(2))
        _ = store1.advanceQuestion(childId: child.id, catechismId: "WSC", totalQuestions: 107, now: stamp(3))
        try await engine1.sync()
        try await engine2.sync()

        // Device 1 edits Q. 1 milestone at t=10 ("reviewing", count 2) AND jumps pacing at t=50.
        _ = store1.updateMilestone(
            childId: child.id, catechismId: "WSC", question: 1,
            state: "reviewing", reviewCount: 2, now: stamp(10)
        )
        _ = store1.jumpToQuestion(childId: child.id, catechismId: "WSC", questionNumber: 5, totalQuestions: 107, now: stamp(50))

        // Device 2 edits Q. 1 milestone later at t=20 ("mastered", count 5).
        _ = store2.updateMilestone(
            childId: child.id, catechismId: "WSC", question: 1,
            state: "mastered", reviewCount: 5, now: stamp(20)
        )

        // Device 1 syncs first, then Device 2 syncs, then Device 1 pulls.
        try await engine1.sync()
        try await engine2.sync()
        try await engine1.sync()

        // Both devices converge: Q. 1 milestone is "mastered"/5 (t=20 > t=10) AND pacing is Q. 5 (t=50).
        let t1 = try #require(store1.activeTrack(childId: child.id))
        let t2 = try #require(store2.activeTrack(childId: child.id))
        #expect(t1.milestones["1"]?.state == "mastered")
        #expect(t1.milestones["1"]?.reviewCount == 5)
        #expect(t2.milestones["1"]?.state == "mastered")
        #expect(t2.milestones["1"]?.reviewCount == 5)
        #expect(t1.currentQuestion == 5)
        #expect(t2.currentQuestion == 5)
    }

    @Test("guest mode writes locally without queueing outbox entries")
    func guestWritesDoNotQueueOutbox() throws {
        let context = try makeProgressContext()
        let guestStore = LocalProgressStore(context: context)
        let child = try guestStore.addChild(name: "GuestChild")
        _ = guestStore.resumeOrStartTrack(childId: child.id, catechismId: "WSC")
        _ = guestStore.advanceQuestion(childId: child.id, catechismId: "WSC", totalQuestions: 107)
        #expect(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }
}
