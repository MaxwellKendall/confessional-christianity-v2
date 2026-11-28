// TKL-1069 / TKL-866: Lord's Day notes and cards sync through DomainKit's
// SyncEngine + AppSyncTransport: exact UUID round-trip, soft deletes, card
// ordering across two-device merges, LWW between edit and remove, no photos in
// sync payloads, and offline capture/retry persistence across app kill.
import Foundation
import SwiftData
import Testing
@testable import DomainKit

private func ldStamp(_ seconds: TimeInterval) -> Date {
    SyncTimestamp.truncate(Date(timeIntervalSince1970: 1_795_100_000 + seconds))
}

@MainActor
private func makeLordsDayContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: progressSchema,
        configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

/// In-memory private AppSync server for `lords_day_notes` and `note_cards`,
/// mirroring `infra/lambda/sync/service.mjs` ownership, LWW, and change_id rules.
private final class FakeLordsDaySyncServer: @unchecked Sendable {
    private let lock = NSLock()
    private var ownerByNote: [String: String] = [:]
    private var rows: [String: [String: SyncRecord]] = [:]
    private var seqBySubject: [String: Int64] = [:]
    private var streamBySubject: [String: [SyncRecord]] = [:]
    var pushedChanges: [SyncChange] = []

    func transport(for subject: String) -> any SyncTransport {
        Transport(server: self, subject: subject)
    }

    func push(subject: String, changes: [SyncChange]) -> Set<UUID> {
        lock.withLock {
            var acked = Set<UUID>()
            for change in changes {
                pushedChanges.append(change)
                let rowId = change.rowId.lowercased()
                let noteId = (change.noteId ?? (change.table == SyncTable.lordsDayNotes ? rowId : "")).lowercased()
                guard !noteId.isEmpty else {
                    acked.insert(change.id)
                    continue
                }
                let existingOwner = ownerByNote[noteId]
                let previous = rows[change.table]?[rowId]
                if let previous, previous.noteId != noteId {
                    acked.insert(change.id) // REJECTED (UNAUTHORIZED)
                    continue
                }
                let creating = existingOwner == nil && previous == nil
                    && change.table == SyncTable.lordsDayNotes && change.deletedAt == nil
                if creating {
                    ownerByNote[noteId] = subject
                } else if existingOwner != subject {
                    acked.insert(change.id) // REJECTED (UNAUTHORIZED)
                    continue
                }
                if let previous, previous.updatedAt >= change.updatedAt {
                    acked.insert(change.id) // ACCEPTED no-op
                    continue
                }
                let nextSeq = (seqBySubject[subject] ?? 0) + 1
                seqBySubject[subject] = nextSeq
                let record = SyncRecord(
                    table: change.table,
                    id: rowId,
                    childId: nil,
                    noteId: noteId,
                    payload: change.payload,
                    updatedAt: change.updatedAt,
                    deletedAt: change.deletedAt,
                    changeId: nextSeq
                )
                rows[change.table, default: [:]][rowId] = record
                streamBySubject[subject, default: []].append(record)
                acked.insert(change.id)
            }
            return acked
        }
    }

    func pull(subject: String, table: String, after cursor: SyncCursor?, limit: Int) -> [SyncRecord] {
        lock.withLock {
            let afterId = cursor?.changeId ?? 0
            let entries = (streamBySubject[subject] ?? [])
                .filter { $0.table == table && $0.changeId > afterId }
                .sorted { $0.changeId < $1.changeId }
            var out: [SyncRecord] = []
            for entry in entries {
                guard let current = rows[table]?[entry.id],
                      current.changeId == entry.changeId,
                      let noteId = entry.noteId,
                      ownerByNote[noteId] == subject else { continue }
                out.append(entry)
                if out.count >= limit { break }
            }
            return out
        }
    }

    private struct Transport: SyncTransport {
        let server: FakeLordsDaySyncServer
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
@Suite("Lord's Day notes and cards sync")
struct LordsDaySyncTests {
    private let subject = "11111111-1111-4111-8111-111111111111"

    @Test("oversized extracted text fits in sync payloads without changing the local note")
    func boundsExtractedTextInBothEnqueuePaths() throws {
        let ctx = try makeLordsDayContext()
        let store = LordsDayStore(context: ctx, syncSubject: subject)
        let text = String(repeating: "é👩🏽‍💻" + String(UnicodeScalar(1)), count: 8_000)
        let note = LordsDayNote(serviceDate: ldStamp(0), sermonTitle: "Sermon", extractedText: text)
        try store.save(note)
        _ = try GuestDataMerge.enqueueGuestData(for: "merge-subject", in: ctx)

        let rows = try ctx.fetch(FetchDescriptor<SyncOutboxEntry>())
            .filter { $0.table == SyncTable.lordsDayNotes }
        #expect(rows.count == 2)
        for row in rows {
            let payload = try #require(row.payload)
            let decoded = try JSONDecoder().decode(LordsDayNoteSyncPayload.self, from: payload)
            let synced = try #require(decoded.extracted_text)
            #expect(payload.count <= 65_536)
            #expect(payload.count > 65_500)
            #expect(synced.utf8.count < text.utf8.count)
            #expect(text.hasPrefix(synced))
            #expect(decoded.sermon_title == "Sermon")
        }
        #expect(note.extractedText == text)
    }

    @Test("successive note updates from the same clock millisecond advance on the wire")
    func sameMillisecondNoteUpdatesAdvance() throws {
        let ctx = try makeLordsDayContext()
        let now = Date(timeIntervalSince1970: 1_795_100_000.0004)
        let store = LordsDayStore(context: ctx, syncSubject: subject, now: { now })
        let note = LordsDayNote(serviceDate: now, createdAt: now, updatedAt: now)
        try store.save(note)
        let original = SyncTimestamp.format(note.updatedAt)
        try store.update(note) { $0.sermonTitle = "First" }
        let first = SyncTimestamp.format(note.updatedAt)
        try store.update(note) { $0.sermonTitle = "Second" }
        let second = SyncTimestamp.format(note.updatedAt)
        #expect(original < first)
        #expect(first < second)
    }

    @Test("round-trips LordsDayNote and all NoteCard kinds with identical UUIDs, preserved fields, and soft deletes")
    func roundTripsNotesCardsAndSoftDeletes() async throws {
        let server = FakeLordsDaySyncServer()
        var clock = ldStamp(0)
        let tick: () -> Date = {
            clock = clock.addingTimeInterval(1)
            return clock
        }

        let ctx1 = try makeLordsDayContext()
        let store1 = LordsDayStore(context: ctx1, syncSubject: subject, now: tick)
        let engine1 = SyncEngine(
            context: ctx1, transport: server.transport(for: subject),
            tables: LordsDaySyncAdapters.all(), subject: subject,
            pushBatchSize: 20, pullPageSize: 50
        )

        let ctx2 = try makeLordsDayContext()
        let store2 = LordsDayStore(context: ctx2, syncSubject: subject, now: tick)
        let engine2 = SyncEngine(
            context: ctx2, transport: server.transport(for: subject),
            tables: LordsDaySyncAdapters.all(), subject: subject,
            pushBatchSize: 20, pullPageSize: 50
        )

        let serviceDate = ldStamp(-3600)
        let note = LordsDayNote(
            serviceDate: serviceDate,
            passageRef: "Revelation 2:8-11",
            sermonTitle: "To the Church at Smyrna",
            preacher: "Rev. Andrew",
            church: "Grace Presbyterian",
            extractedText: "Do not fear what you are about to suffer.",
            createdAt: ldStamp(0),
            updatedAt: ldStamp(1)
        )
        try store1.save(note)

        let c1 = try store1.appendCard(to: note, kind: .keyPoint, body: "Christ walks among his lampstands.")
        c1.palette = "chapel"
        try store1.saveCard(c1)
        let c2 = try store1.appendCard(
            to: note, kind: .quote, body: "I see Christ wrestling there.",
            attribution: "Margaret Wilson", palette: "gilt", editedByUser: true
        )
        let c3 = try store1.appendCard(
            to: note, kind: .verse, body: "", verseRef: "Rev.2.10", palette: "moss"
        )

        try await engine1.sync()
        try await engine2.sync()

        let pulledNote = try #require(try store2.note(id: note.id))
        #expect(pulledNote.id == note.id)
        #expect(pulledNote.serviceDate == serviceDate)
        #expect(pulledNote.passageRef == "Revelation 2:8-11")
        #expect(pulledNote.sermonTitle == "To the Church at Smyrna")
        #expect(pulledNote.preacher == "Rev. Andrew")
        #expect(pulledNote.church == "Grace Presbyterian")
        #expect(pulledNote.extractedText == "Do not fear what you are about to suffer.")
        #expect(pulledNote.deletedAt == nil)

        let pulledCards = try store2.cards(for: pulledNote)
        #expect(pulledCards.map(\.id) == [c1.id, c2.id, c3.id])
        #expect(pulledCards.map(\.kind) == [.keyPoint, .quote, .verse])
        #expect(pulledCards[0].body == "Christ walks among his lampstands.")
        #expect(pulledCards[0].palette == "chapel")
        #expect(pulledCards[1].attribution == "Margaret Wilson")
        #expect(pulledCards[1].palette == "gilt")
        #expect(pulledCards[1].editedByUser == true)
        #expect(pulledCards[2].body == "")
        #expect(pulledCards[2].verseRef == "Rev.2.10")
        #expect(pulledCards[2].palette == "moss")

        // Soft-delete card c2 on Device 2 -> disappears on Device 1 (soft-deleted, row kept with deletedAt).
        try store2.removeCard(pulledCards[1])
        try await engine2.sync()
        try await engine1.sync()

        #expect(try store1.cards(for: note).map(\.id) == [c1.id, c3.id])
        let deletedCardOn1 = try #require(try ctx1.fetch(FetchDescriptor<NoteCard>()).first { $0.id == c2.id })
        #expect(deletedCardOn1.deletedAt != nil)

        // Soft-delete note on Device 2 -> soft-deleted on Device 1.
        try store2.removeNote(pulledNote)
        try await engine2.sync()
        try await engine1.sync()

        #expect(try store1.note(id: note.id) == nil)
        let deletedNoteOn1 = try #require(try ctx1.fetch(FetchDescriptor<LordsDayNote>()).first { $0.id == note.id })
        #expect(deletedNoteOn1.deletedAt != nil)
    }

    @Test("card order survives a merge from two devices, including reorder + concurrent edit and concurrent appends")
    func cardOrderSurvivesTwoDeviceMerge() async throws {
        let server = FakeLordsDaySyncServer()
        let ctx1 = try makeLordsDayContext()
        let ctx2 = try makeLordsDayContext()

        var now1 = ldStamp(1)
        var now2 = ldStamp(1)
        let store1 = LordsDayStore(context: ctx1, syncSubject: subject, now: { now1 })
        let store2 = LordsDayStore(context: ctx2, syncSubject: subject, now: { now2 })
        let engine1 = SyncEngine(context: ctx1, transport: server.transport(for: subject), tables: LordsDaySyncAdapters.all(), subject: subject)
        let engine2 = SyncEngine(context: ctx2, transport: server.transport(for: subject), tables: LordsDaySyncAdapters.all(), subject: subject)

        let note = LordsDayNote(serviceDate: ldStamp(0), sermonTitle: "Romans 8", createdAt: ldStamp(1), updatedAt: ldStamp(1))
        try store1.save(note)
        now1 = ldStamp(2); let a = try store1.appendCard(to: note, kind: .keyPoint, body: "First")
        now1 = ldStamp(3); let b = try store1.appendCard(to: note, kind: .keyPoint, body: "Second")
        now1 = ldStamp(4); let c = try store1.appendCard(to: note, kind: .keyPoint, body: "Third")

        try await engine1.sync()
        try await engine2.sync()

        let noteOn2 = try #require(try store2.note(id: note.id))
        let cardsOn2 = try store2.cards(for: noteOn2)
        #expect(cardsOn2.map(\.id) == [a.id, b.id, c.id])

        // Device 1 reorders to [c, b, a] at t=10.
        now1 = ldStamp(10)
        try store1.reorderCards(for: note, cards: [c, b, a])

        // Device 2 concurrently edits b's body at t=15 (keeping b at position 1).
        now2 = ldStamp(15)
        try store2.editBody(of: cardsOn2[1], body: "Second (edited on Device 2)")

        // Both sync and converge: order is [c, b, a] AND b keeps Device 2's newer edit.
        try await engine1.sync()
        try await engine2.sync()
        try await engine1.sync()

        let merged1 = try store1.cards(for: note)
        let merged2 = try store2.cards(for: noteOn2)
        #expect(merged1.map(\.id) == [c.id, b.id, a.id])
        #expect(merged2.map(\.id) == [c.id, b.id, a.id])
        #expect(merged1[1].body == "Second (edited on Device 2)")
        #expect(merged2[1].body == "Second (edited on Device 2)")

        // Concurrent offline appends at the same position converge to the exact same deterministic order.
        now1 = ldStamp(20); let d1 = try store1.appendCard(to: note, kind: .keyPoint, body: "Appended on 1")
        now2 = ldStamp(21); let d2 = try store2.appendCard(to: noteOn2, kind: .keyPoint, body: "Appended on 2")
        #expect(d1.position == d2.position)

        try await engine1.sync()
        try await engine2.sync()
        try await engine1.sync()

        let final1 = try store1.cards(for: note).map(\.id)
        let final2 = try store2.cards(for: noteOn2).map(\.id)
        #expect(final1 == final2)
        #expect(final1 == [c.id, b.id, a.id, d1.id, d2.id])
    }

    @Test("a card edited on one device and removed on the other resolves by last-write-wins in both directions")
    func editVsRemoveResolvesByLWW() async throws {
        let server = FakeLordsDaySyncServer()
        let ctx1 = try makeLordsDayContext()
        let ctx2 = try makeLordsDayContext()

        var now1 = ldStamp(1)
        var now2 = ldStamp(1)
        let store1 = LordsDayStore(context: ctx1, syncSubject: subject, now: { now1 })
        let store2 = LordsDayStore(context: ctx2, syncSubject: subject, now: { now2 })
        let engine1 = SyncEngine(context: ctx1, transport: server.transport(for: subject), tables: LordsDaySyncAdapters.all(), subject: subject)
        let engine2 = SyncEngine(context: ctx2, transport: server.transport(for: subject), tables: LordsDaySyncAdapters.all(), subject: subject)

        let note = LordsDayNote(serviceDate: ldStamp(0), createdAt: ldStamp(1), updatedAt: ldStamp(1))
        try store1.save(note)
        now1 = ldStamp(2); let cardDeleteWins = try store1.appendCard(to: note, kind: .keyPoint, body: "Delete wins")
        now1 = ldStamp(3); let cardEditWins = try store1.appendCard(to: note, kind: .keyPoint, body: "Edit wins")

        try await engine1.sync()
        try await engine2.sync()
        let noteOn2 = try #require(try store2.note(id: note.id))
        let cardsOn2 = try store2.cards(for: noteOn2)

        // Card 1: Device 1 edits at t=10, Device 2 removes at t=20 -> remove wins on both.
        now1 = ldStamp(10); try store1.editBody(of: cardDeleteWins, body: "Stale edit")
        now2 = ldStamp(20); try store2.removeCard(cardsOn2[0])

        // Card 2: Device 1 removes at t=10, Device 2 edits at t=20 -> edit wins on both.
        now1 = ldStamp(10); try store1.removeCard(cardEditWins)
        now2 = ldStamp(20); try store2.editBody(of: cardsOn2[1], body: "Newer edit wins")

        try await engine1.sync()
        try await engine2.sync()
        try await engine1.sync()

        let live1 = try store1.cards(for: note)
        let live2 = try store2.cards(for: noteOn2)
        #expect(live1.map(\.id) == [cardEditWins.id])
        #expect(live2.map(\.id) == [cardEditWins.id])
        #expect(live1[0].body == "Newer edit wins")
        #expect(live2[0].body == "Newer edit wins")
    }

    @Test("photos never appear in sync outbox or payloads; only metadata, extractedText and cards sync")
    func photosNeverEnterSyncPayloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sync-nophoto-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let server = FakeLordsDaySyncServer()
        let ctx = try makeLordsDayContext()
        let store = LordsDayStore(context: ctx, syncSubject: subject)
        let engine = SyncEngine(context: ctx, transport: server.transport(for: subject), tables: LordsDaySyncAdapters.all(), subject: subject)

        let note = LordsDayNote(
            serviceDate: ldStamp(0),
            passageRef: "Psalm 23",
            sermonTitle: "The Lord is My Shepherd",
            extractedText: "I shall not want."
        )
        try store.save(note)

        // Store JPEG photos locally on disk via CaptureDraft.
        let fakeJpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x42, 0x42, 0xFF, 0xD9])
        let draft = try CaptureDraft(noteId: note.id, root: root)
        try draft.addPage(fakeJpeg)

        try store.keepCards([
            KeptCard(kind: .keyPoint, body: "The Shepherd leads beside still waters.", verseRef: nil, attribution: nil, editedByUser: false),
            KeptCard(kind: .verse, body: "", verseRef: "Ps.23.1", attribution: nil, editedByUser: false),
        ], for: note)

        try await engine.sync()

        let allowedNoteKeys: Set<String> = ["service_date", "passage_ref", "sermon_title", "preacher", "church", "extracted_text", "created_at"]
        let allowedCardKeys: Set<String> = ["kind", "body", "verse_ref", "attribution", "palette", "position", "edited_by_user", "created_at"]
        #expect(!server.pushedChanges.isEmpty)
        for change in server.pushedChanges {
            guard let payload = change.payload else { continue }
            let raw = try #require(String(data: payload, encoding: .utf8))
            #expect(!raw.contains(fakeJpeg.base64EncodedString()))
            let obj = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
            let keys = Set(obj.keys)
            if change.table == SyncTable.lordsDayNotes {
                #expect(keys.isSubset(of: allowedNoteKeys))
            } else if change.table == SyncTable.noteCards {
                #expect(keys.isSubset(of: allowedCardKeys))
            }
        }
    }

    @Test("AppSyncTransport sends note_id, acknowledges permanent rejects, and pulls note_id",
          arguments: ["ACCEPTED", "REJECTED"])
    func appSyncTransportWireFormatForNotesAndCards(noteStatus: String) async throws {
        final class CaptureHTTP: @unchecked Sendable {
            var bodies: [[String: Any]] = []
            var responses: [String] = []
            func fetch(_ req: URLRequest) async throws -> (Data, URLResponse) {
                let json = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
                bodies.append(json)
                let body = responses.removeFirst()
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), resp)
            }
        }

        let http = CaptureHTTP()
        let noteId = UUID().uuidString.lowercased()
        let cardId = UUID().uuidString.lowercased()
        let op1 = UUID()
        let op2 = UUID()
        let reason = noteStatus == "REJECTED" ? #""CLOCK_SKEW""# : "null"
        http.responses = [
            #"{"data":{"pushSync":[{"id":"\#(op1.uuidString.lowercased())","status":"\#(noteStatus)","reason":\#(reason)},{"id":"\#(op2.uuidString.lowercased())","status":"ACCEPTED","reason":null}]}}"#,
            #"{"data":{"pullSync":[{"table":"note_cards","id":"\#(cardId)","child_id":null,"note_id":"\#(noteId)","updated_at":"2026-11-22T10:00:00.000Z","deleted_at":null,"payload":"{\"kind\":\"key_point\",\"body\":\"Hello\",\"position\":0,\"edited_by_user\":false,\"created_at\":\"2026-11-22T10:00:00.000Z\"}","change_id":"7"}]}}"#,
        ]

        let transport = AppSyncTransport(
            endpoint: URL(string: "https://sync.example.com/graphql")!,
            tokenProvider: { _ in "tok" },
            fetch: { try await http.fetch($0) }
        )

        let acked = try await transport.push([
            SyncChange(
                id: op1, table: SyncTable.lordsDayNotes, rowId: noteId, noteId: noteId,
                payload: Data(#"{"service_date":"2026-11-22T05:00:00.000Z","created_at":"2026-11-22T10:00:00.000Z"}"#.utf8),
                updatedAt: ldStamp(1)
            ),
            SyncChange(
                id: op2, table: SyncTable.noteCards, rowId: cardId, noteId: noteId,
                payload: Data(#"{"kind":"key_point","body":"Hello","position":0,"edited_by_user":false,"created_at":"2026-11-22T10:00:00.000Z"}"#.utf8),
                updatedAt: ldStamp(2)
            ),
        ])
        #expect(acked == [op1, op2])

        let sentChanges = try #require((http.bodies[0]["variables"] as? [String: Any])?["changes"] as? [[String: Any]])
        #expect(sentChanges[0]["note_id"] as? String == noteId)
        #expect(sentChanges[0]["child_id"] == nil)
        #expect(sentChanges[1]["note_id"] as? String == noteId)
        #expect(sentChanges[1]["child_id"] == nil)

        let pulled = try await transport.pull(table: SyncTable.noteCards, after: nil, limit: 50)
        #expect(pulled.count == 1)
        #expect(pulled[0].id == cardId)
        #expect(pulled[0].noteId == noteId)
        #expect(pulled[0].childId == nil)
        #expect(pulled[0].changeId == 7)
    }

    @Test("offline capture preserves note, photos, and retryWhenOnline state across an app kill")
    func offlineCaptureAndRetrySurviveAppKill() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-kill-\(UUID().uuidString)")
        let dbURL = root.appendingPathComponent("Store.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let noteId: UUID
        let jpeg = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
        do {
            let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, url: dbURL)])
            let store = LordsDayStore(context: container.mainContext, syncSubject: subject)
            let note = LordsDayNote(serviceDate: ldStamp(0), sermonTitle: "Offline Sermon")
            try store.save(note)
            noteId = note.id

            let draft = try CaptureDraft(noteId: noteId, root: root)
            try draft.addPage(jpeg)

            // Generator call fails offline -> review marks waiting for network and saves to disk.
            var review = LordsDayReview(noteId: noteId, pageCount: draft.pages.count)
            _ = review.begin()
            review.markWaitingForNetwork()
            review.interrupt()
            try review.save(root: root)
        }

        // Simulate app kill + fresh process launch: everything comes from disk.
        let reopened = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, url: dbURL)])
        let store = LordsDayStore(context: reopened.mainContext, syncSubject: subject)
        let savedNote = try #require(try store.note(id: noteId))
        #expect(savedNote.sermonTitle == "Offline Sermon")
        #expect(try store.pendingReviewNotes(root: root).map(\.id) == [noteId])

        let savedPhotos = try CaptureDraft(noteId: noteId, root: root).pageData()
        #expect(savedPhotos == [jpeg])

        var loadedReview = try #require(try LordsDayReview.load(noteId: noteId, root: root))
        #expect(loadedReview.phase == .interrupted)
        #expect(loadedReview.retryWhenOnline == true)
        #expect(loadedReview.canRetry == true)

        // Network returns -> begin() clears retryWhenOnline and retries page 0.
        let pagesToRetry = loadedReview.begin()
        #expect(pagesToRetry == [0])
        #expect(loadedReview.retryWhenOnline == false)
    }

    @Test("guest mode LordsDayStore writes locally without queueing outbox entries")
    func guestModeQueuesNothing() throws {
        let ctx = try makeLordsDayContext()
        let guestStore = LordsDayStore(context: ctx)
        let note = LordsDayNote(serviceDate: ldStamp(0), sermonTitle: "Guest Sermon")
        try guestStore.save(note)
        let card = try guestStore.appendCard(to: note, kind: .keyPoint, body: "Local only")
        try guestStore.editBody(of: card, body: "Edited locally")
        try guestStore.removeCard(card)
        #expect(try ctx.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }
}
