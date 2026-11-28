// TKL-1070: Guest-data union merge on first sign-in and sign-out local data clear.
// Covers every synced data type (children, catechism assignments, pacing, milestones,
// Lord's Day notes and cards), same-ID LWW, no name matching for children, milestone
// advanced-state union in both timestamp directions, note/card ID and order survival,
// photos staying local, sign-out clear back to empty guest, account-switch isolation,
// and fresh-install restore.
import Foundation
import SwiftData
import Testing
@testable import DomainKit

private func gmStamp(_ seconds: TimeInterval) -> Date {
    SyncTimestamp.truncate(Date(timeIntervalSince1970: 1_795_200_000 + seconds))
}

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: progressSchema,
        configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

/// Combined in-memory AppSync server handling all 6 synced tables (children,
/// catechism_assignments, catechism_pacing, catechism_milestones, lords_day_notes,
/// note_cards) with subject ownership, LWW on updated_at, and monotonic change_id.
private final class FakeFullAccountSyncServer: @unchecked Sendable {
    private let lock = NSLock()
    private var ownerByChild: [String: String] = [:]
    private var ownerByNote: [String: String] = [:]
    private var rows: [String: [String: SyncRecord]] = [:]
    private var seqBySubject: [String: Int64] = [:]
    private var streamBySubject: [String: [SyncRecord]] = [:]
    var pushedBySubject: [String: [SyncChange]] = [:]
    var online = true

    func transport(for subject: String) -> any SyncTransport {
        Transport(server: self, subject: subject)
    }

    func push(subject: String, changes: [SyncChange]) throws -> Set<UUID> {
        try lock.withLock {
            guard online else { throw AppSyncTransportError.offline }
            var acked = Set<UUID>()
            for change in changes {
                pushedBySubject[subject, default: []].append(change)
                let rowId = change.rowId.lowercased()
                let isNote = SyncTable.isNoteTable(change.table)
                if isNote {
                    let noteId = (change.noteId ?? (change.table == SyncTable.lordsDayNotes ? rowId : "")).lowercased()
                    guard !noteId.isEmpty else { acked.insert(change.id); continue }
                    let existingOwner = ownerByNote[noteId]
                    let previous = rows[change.table]?[rowId]
                    let creating = existingOwner == nil && previous == nil
                        && change.table == SyncTable.lordsDayNotes && change.deletedAt == nil
                    if creating {
                        ownerByNote[noteId] = subject
                    } else if existingOwner != subject {
                        acked.insert(change.id)
                        continue
                    }
                    if let previous, previous.updatedAt >= change.updatedAt {
                        acked.insert(change.id)
                        continue
                    }
                    let nextSeq = (seqBySubject[subject] ?? 0) + 1
                    seqBySubject[subject] = nextSeq
                    let record = SyncRecord(
                        table: change.table, id: rowId, childId: nil, noteId: noteId,
                        payload: change.payload, updatedAt: change.updatedAt,
                        deletedAt: change.deletedAt, changeId: nextSeq
                    )
                    rows[change.table, default: [:]][rowId] = record
                    streamBySubject[subject, default: []].append(record)
                    acked.insert(change.id)
                } else {
                    let childId = (change.childId ?? (change.table == SyncTable.children ? rowId : "")).lowercased()
                    guard !childId.isEmpty else { acked.insert(change.id); continue }
                    let existingOwner = ownerByChild[childId]
                    let previous = rows[change.table]?[rowId]
                    let creating = existingOwner == nil && previous == nil
                        && change.table == SyncTable.children && change.deletedAt == nil
                    if creating {
                        ownerByChild[childId] = subject
                    } else if existingOwner != subject {
                        acked.insert(change.id)
                        continue
                    }
                    if let previous, previous.updatedAt >= change.updatedAt {
                        acked.insert(change.id)
                        continue
                    }
                    let nextSeq = (seqBySubject[subject] ?? 0) + 1
                    seqBySubject[subject] = nextSeq
                    let record = SyncRecord(
                        table: change.table, id: rowId, childId: childId, noteId: nil,
                        payload: change.payload, updatedAt: change.updatedAt,
                        deletedAt: change.deletedAt, changeId: nextSeq
                    )
                    rows[change.table, default: [:]][rowId] = record
                    streamBySubject[subject, default: []].append(record)
                    acked.insert(change.id)
                }
            }
            return acked
        }
    }

    func pull(subject: String, table: String, after cursor: SyncCursor?, limit: Int) throws -> [SyncRecord] {
        try lock.withLock {
            guard online else { throw AppSyncTransportError.offline }
            let afterId = cursor?.changeId ?? 0
            let entries = (streamBySubject[subject] ?? [])
                .filter { $0.table == table && $0.changeId > afterId }
                .sorted { $0.changeId < $1.changeId }
            var out: [SyncRecord] = []
            for entry in entries {
                guard let current = rows[table]?[entry.id], current.changeId == entry.changeId else { continue }
                if SyncTable.isNoteTable(table) {
                    guard let nid = entry.noteId, ownerByNote[nid] == subject else { continue }
                } else {
                    guard let cid = entry.childId, ownerByChild[cid] == subject else { continue }
                }
                out.append(entry)
                if out.count >= limit { break }
            }
            return out
        }
    }

    private struct Transport: SyncTransport {
        let server: FakeFullAccountSyncServer
        let subject: String
        func push(_ changes: [SyncChange]) async throws -> Set<UUID> {
            try server.push(subject: subject, changes: changes)
        }
        func pull(table: String, after cursor: SyncCursor?, limit: Int) async throws -> [SyncRecord] {
            try server.pull(subject: subject, table: table, after: cursor, limit: limit)
        }
    }
}

@MainActor
@Suite("Guest data merge and sign-out clear (TKL-1070)")
struct GuestMergeAndSignOutTests {
    private let subjectA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let subjectB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    @Test("summary counts live guest children, tracks, milestones, notes and cards while ignoring soft-deleted rows")
    func guestDataSummaryCountsLiveRowsOnly() throws {
        let ctx = try makeContext()
        #expect(try GuestDataMerge.summary(in: ctx).hasData == false)

        let progress = LocalProgressStore(context: ctx)
        let samuel = try progress.addChild(name: "Samuel", now: gmStamp(1))
        _ = progress.startTrack(childId: samuel.id, catechismId: "WSC", startingQuestion: 9, now: gmStamp(2))
        _ = progress.advanceQuestion(childId: samuel.id, catechismId: "WSC", totalQuestions: 107, now: gmStamp(3))

        let lordsDay = LordsDayStore(context: ctx, now: { gmStamp(4) })
        let liveNote = LordsDayNote(serviceDate: gmStamp(0), sermonTitle: "Live Sermon", createdAt: gmStamp(4), updatedAt: gmStamp(4))
        try lordsDay.save(liveNote)
        let keptCard = try lordsDay.appendCard(to: liveNote, kind: .keyPoint, body: "Keep me")
        let removedCard = try lordsDay.appendCard(to: liveNote, kind: .quote, body: "Removed")
        try lordsDay.removeCard(removedCard)

        let deletedNote = LordsDayNote(serviceDate: gmStamp(-86400), sermonTitle: "Deleted", createdAt: gmStamp(4), updatedAt: gmStamp(4))
        try lordsDay.save(deletedNote)
        _ = try lordsDay.appendCard(to: deletedNote, kind: .keyPoint, body: "Orphan card")
        try lordsDay.removeNote(deletedNote)

        let summary = try GuestDataMerge.summary(in: ctx)
        #expect(summary.hasData == true)
        #expect(summary.childCount == 1)
        #expect(summary.trackCount == 1)
        #expect(summary.milestoneCount == 1)
        #expect(summary.noteCount == 1)
        #expect(summary.cardCount == 1)
        #expect(keptCard.deletedAt == nil)
        #expect(summary.rows.map(\.id) == ["children", "catechism", "lords_day"])
    }

    @Test("first sign-in merges guest children, catechism progress, and Lord's Day notes/cards as a union with no name matching, and restores on fresh install")
    func guestUnionMergeAndFreshInstallRestore() async throws {
        let server = FakeFullAccountSyncServer()
        let photoRoot = FileManager.default.temporaryDirectory.appendingPathComponent("tkl1070-photos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: photoRoot) }

        // Device A already has account data: child "Samuel" (UUID A, Q. 3) + Sermon A (2 cards).
        let ctxA = try makeContext()
        let progressA = LocalProgressStore(context: ctxA, syncSubject: subjectA)
        let lordsDayA = LordsDayStore(context: ctxA, syncSubject: subjectA, now: { gmStamp(10) })
        let engineA = SyncEngine(
            context: ctxA, transport: server.transport(for: subjectA),
            tables: AccountSyncAdapters.all(), subject: subjectA
        )

        let accountSamuel = try progressA.addChild(name: "Samuel", age: 8, now: gmStamp(1))
        _ = progressA.resumeOrStartTrack(childId: accountSamuel.id, catechismId: "WSC", now: gmStamp(2))
        _ = progressA.advanceQuestion(childId: accountSamuel.id, catechismId: "WSC", totalQuestions: 107, now: gmStamp(3))
        _ = progressA.advanceQuestion(childId: accountSamuel.id, catechismId: "WSC", totalQuestions: 107, now: gmStamp(4))

        let sermonA = LordsDayNote(serviceDate: gmStamp(-86400 * 7), passageRef: "Psalm 23", sermonTitle: "The Good Shepherd", createdAt: gmStamp(5), updatedAt: gmStamp(5))
        try lordsDayA.save(sermonA)
        let cardA1 = try lordsDayA.appendCard(to: sermonA, kind: .keyPoint, body: "The Lord is my shepherd.")
        let cardA2 = try lordsDayA.appendCard(to: sermonA, kind: .verse, body: "", verseRef: "Ps.23.1")
        try await engineA.sync()

        // Device B is a guest with local child "Samuel" (DIFFERENT UUID! Q. 9), "Thomas" (Q. 4), and Sermon B (3 cards + local photo).
        let ctxB = try makeContext()
        let guestProgressB = LocalProgressStore(context: ctxB)
        let guestLordsDayB = LordsDayStore(context: ctxB, now: { gmStamp(20) })

        let guestSamuel = try guestProgressB.addChild(name: "Samuel", now: gmStamp(11))
        _ = guestProgressB.startTrack(childId: guestSamuel.id, catechismId: "WSC", startingQuestion: 9, now: gmStamp(12))
        let guestThomas = try guestProgressB.addChild(name: "Thomas", now: gmStamp(13))
        _ = guestProgressB.startTrack(childId: guestThomas.id, catechismId: "WSC", startingQuestion: 4, now: gmStamp(14))

        let sermonB = LordsDayNote(serviceDate: gmStamp(0), passageRef: "Romans 8:28-30", sermonTitle: "The Golden Chain", createdAt: gmStamp(15), updatedAt: gmStamp(15))
        try guestLordsDayB.save(sermonB)
        let cardB1 = try guestLordsDayB.appendCard(to: sermonB, kind: .verse, body: "", verseRef: "Ps.118.24")
        let cardB2 = try guestLordsDayB.appendCard(to: sermonB, kind: .keyPoint, body: "God's purpose decides what is good.")
        let cardB3 = try guestLordsDayB.appendCard(to: sermonB, kind: .quote, body: "The golden chain has no weak link.", attribution: "Pastor")

        let fakePhoto = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x99, 0xFF, 0xD9])
        let draftB = try CaptureDraft(noteId: sermonB.id, root: photoRoot)
        try draftB.addPage(fakePhoto)

        // User confirms "Keep what's on this phone in your account" on Device B.
        let enqueued = try GuestDataMerge.enqueueGuestData(for: subjectA, in: ctxB)
        #expect(enqueued > 0)
        // Idempotency: calling enqueue again before push doesn't duplicate entries.
        let secondEnqueue = try GuestDataMerge.enqueueGuestData(for: subjectA, in: ctxB)
        #expect(secondEnqueue == 0)

        let engineB = SyncEngine(
            context: ctxB, transport: server.transport(for: subjectA),
            tables: AccountSyncAdapters.all(), subject: subjectA
        )
        try await engineB.mergeSync()

        // Device B now has ALL 3 children (both Samuels kept separately — no name matching — plus Thomas) and BOTH sermons with exact card IDs and order.
        let childrenB = try ctxB.fetch(FetchDescriptor<LocalChild>())
        #expect(Set(childrenB.map(\.id)) == [accountSamuel.id, guestSamuel.id, guestThomas.id])
        #expect(childrenB.filter { $0.name == "Samuel" }.count == 2)
        let storeB = LocalProgressStore(context: ctxB, syncSubject: subjectA)
        #expect(storeB.activeTrack(childId: accountSamuel.id)?.currentQuestion == 3)
        #expect(storeB.activeTrack(childId: guestSamuel.id)?.currentQuestion == 9)
        #expect(storeB.activeTrack(childId: guestThomas.id)?.currentQuestion == 4)

        let ldStoreB = LordsDayStore(context: ctxB, syncSubject: subjectA)
        let pulledAOnB = try #require(try ldStoreB.note(id: sermonA.id))
        let keptBOnB = try #require(try ldStoreB.note(id: sermonB.id))
        #expect(try ldStoreB.cards(for: pulledAOnB).map(\.id) == [cardA1.id, cardA2.id])
        #expect(try ldStoreB.cards(for: keptBOnB).map(\.id) == [cardB1.id, cardB2.id, cardB3.id])

        // Photos stayed strictly local and never entered any pushed payload.
        #expect(try CaptureDraft(noteId: sermonB.id, root: photoRoot).pageData() == [fakePhoto])
        for change in server.pushedBySubject[subjectA] ?? [] {
            if let payload = change.payload, let str = String(data: payload, encoding: .utf8) {
                #expect(!str.contains(fakePhoto.base64EncodedString()))
            }
        }

        // Device A foregrounds and syncs -> now has both sets too!
        try await engineA.sync()
        let childrenA = try ctxA.fetch(FetchDescriptor<LocalChild>())
        #expect(Set(childrenA.map(\.id)) == [accountSamuel.id, guestSamuel.id, guestThomas.id])
        let pulledBOnA = try #require(try lordsDayA.note(id: sermonB.id))
        #expect(try lordsDayA.cards(for: pulledBOnA).map(\.id) == [cardB1.id, cardB2.id, cardB3.id])

        // Fresh install on Device C signs into the same account -> restores everything.
        let ctxC = try makeContext()
        let engineC = SyncEngine(
            context: ctxC, transport: server.transport(for: subjectA),
            tables: AccountSyncAdapters.all(), subject: subjectA
        )
        try await engineC.sync()
        let childrenC = try ctxC.fetch(FetchDescriptor<LocalChild>())
        #expect(Set(childrenC.map(\.id)) == [accountSamuel.id, guestSamuel.id, guestThomas.id])
        let ldStoreC = LordsDayStore(context: ctxC, syncSubject: subjectA)
        #expect(try ldStoreC.cards(for: try #require(try ldStoreC.note(id: sermonA.id))).map(\.id) == [cardA1.id, cardA2.id])
        #expect(try ldStoreC.cards(for: try #require(try ldStoreC.note(id: sermonB.id))).map(\.id) == [cardB1.id, cardB2.id, cardB3.id])
    }

    @Test("milestones on the same child union with the more advanced state winning regardless of timestamp order")
    func milestonesUnionMoreAdvancedStateWins() async throws {
        let server = FakeFullAccountSyncServer()
        let sharedChildId = UUID()

        // Seed server with sharedChild: Q. 1 = mastered (count 4, t=100), Q. 2 = introduced (count 0, t=200), Q. 3 = reviewing (count 2, t=150).
        let ctxServer = try makeContext()
        let serverChild = LocalChild(id: sharedChildId, name: "Hannah", age: nil, createdAt: gmStamp(1), updatedAt: gmStamp(10), activeCatechismId: "WSC")
        ctxServer.insert(serverChild)
        let serverTrack = ChildCatechismTrack(
            childId: sharedChildId, catechismId: "WSC", currentQuestion: 4, startedAtQuestion: 1,
            startedAt: gmStamp(1), updatedAt: gmStamp(200),
            milestones: [
                "1": MilestoneRecord(state: "mastered", introducedAt: gmStamp(10), reviewCount: 4),
                "2": MilestoneRecord(state: "introduced", introducedAt: gmStamp(20), reviewCount: 0),
                "3": MilestoneRecord(state: "reviewing", introducedAt: gmStamp(30), reviewCount: 2),
            ]
        )
        ctxServer.insert(serverTrack)
        try ctxServer.save()
        // Push server seed with explicit per-milestone timestamps.
        let storeServer = LocalProgressStore(context: ctxServer, syncSubject: subjectA)
        try storeServer.renameChild(childId: sharedChildId, name: "Hannah", now: gmStamp(10))
        _ = storeServer.updateMilestone(childId: sharedChildId, catechismId: "WSC", question: 1, state: "mastered", introducedAt: gmStamp(10), reviewCount: 4, now: gmStamp(100))
        _ = storeServer.updateMilestone(childId: sharedChildId, catechismId: "WSC", question: 2, state: "introduced", introducedAt: gmStamp(20), reviewCount: 0, now: gmStamp(200))
        _ = storeServer.updateMilestone(childId: sharedChildId, catechismId: "WSC", question: 3, state: "reviewing", introducedAt: gmStamp(30), reviewCount: 2, now: gmStamp(150))
        let engineServer = SyncEngine(
            context: ctxServer, transport: server.transport(for: subjectA),
            tables: AccountSyncAdapters.all(), subject: subjectA
        )
        try await engineServer.sync()

        // Guest device has the SAME childId with:
        //   Q. 1 = introduced (count 0, newer timestamp t=250!) -> server's mastered MUST win!
        //   Q. 2 = mastered (count 5, older timestamp t=100!) -> guest's mastered MUST win and propagate to server!
        //   Q. 4 = introduced (count 0, guest-only) -> union keeps Q. 3 (server) AND Q. 4 (guest)!
        let ctxGuest = try makeContext()
        let guestChild = LocalChild(id: sharedChildId, name: "Hannah Guest", age: nil, createdAt: gmStamp(1), updatedAt: gmStamp(5), activeCatechismId: "WSC")
        ctxGuest.insert(guestChild)
        let guestTrack = ChildCatechismTrack(
            childId: sharedChildId, catechismId: "WSC", currentQuestion: 5, startedAtQuestion: 1,
            startedAt: gmStamp(1), updatedAt: gmStamp(250),
            milestones: [
                "1": MilestoneRecord(state: "introduced", introducedAt: gmStamp(250), reviewCount: 0),
                "2": MilestoneRecord(state: "mastered", introducedAt: gmStamp(15), reviewCount: 5),
                "4": MilestoneRecord(state: "introduced", introducedAt: gmStamp(40), reviewCount: 0),
            ]
        )
        ctxGuest.insert(guestTrack)
        try ctxGuest.save()

        _ = try GuestDataMerge.enqueueGuestData(for: subjectA, in: ctxGuest)
        let engineGuest = SyncEngine(
            context: ctxGuest, transport: server.transport(for: subjectA),
            tables: AccountSyncAdapters.all(), subject: subjectA
        )
        try await engineGuest.mergeSync()
        try await engineServer.sync()

        // Same-ID child resolved by LWW: server name "Hannah" (t=10) beats guest "Hannah Guest" (t=5).
        let mergedChildOnGuest = try #require(try ctxGuest.fetch(FetchDescriptor<LocalChild>()).first)
        #expect(mergedChildOnGuest.name == "Hannah")

        // Milestones unioned with more advanced state winning on BOTH devices!
        let trackGuest = try #require(LocalProgressStore(context: ctxGuest).activeTrack(childId: sharedChildId))
        let trackServer = try #require(LocalProgressStore(context: ctxServer).activeTrack(childId: sharedChildId))
        for track in [trackGuest, trackServer] {
            #expect(Set(track.milestones.keys) == ["1", "2", "3", "4"])
            #expect(track.milestones["1"]?.state == "mastered")
            #expect(track.milestones["1"]?.reviewCount == 4)
            #expect(track.milestones["2"]?.state == "mastered")
            #expect(track.milestones["2"]?.reviewCount == 5)
            #expect(track.milestones["3"]?.state == "reviewing")
            #expect(track.milestones["4"]?.state == "introduced")
        }
    }

    @Test("a more advanced local milestone is pushed back even when the adapters were built without a subject (TKL-1084)")
    func milestoneUpgradePushedWithoutAdapterSubject() async throws {
        let server = FakeFullAccountSyncServer()
        let childId = UUID()

        // Account has Q. 1 = introduced.
        let ctxServer = try makeContext()
        ctxServer.insert(LocalChild(id: childId, name: "Hannah", age: nil, createdAt: gmStamp(1), updatedAt: gmStamp(10), activeCatechismId: "WSC"))
        ctxServer.insert(ChildCatechismTrack(
            childId: childId, catechismId: "WSC", currentQuestion: 2, startedAtQuestion: 1,
            startedAt: gmStamp(1), updatedAt: gmStamp(200),
            milestones: ["1": MilestoneRecord(state: "introduced", introducedAt: gmStamp(20), reviewCount: 0)]
        ))
        try ctxServer.save()
        _ = try GuestDataMerge.enqueueGuestData(for: subjectA, in: ctxServer)
        let engineServer = SyncEngine(
            context: ctxServer, transport: server.transport(for: subjectA),
            tables: ChildProgressSyncAdapters.all(), subject: subjectA
        )
        try await engineServer.sync()

        // This phone has Q. 1 = mastered (older timestamp), queued for the account.
        let ctxGuest = try makeContext()
        ctxGuest.insert(LocalChild(id: childId, name: "Hannah", age: nil, createdAt: gmStamp(1), updatedAt: gmStamp(5), activeCatechismId: "WSC"))
        ctxGuest.insert(ChildCatechismTrack(
            childId: childId, catechismId: "WSC", currentQuestion: 2, startedAtQuestion: 1,
            startedAt: gmStamp(1), updatedAt: gmStamp(100),
            milestones: ["1": MilestoneRecord(state: "mastered", introducedAt: gmStamp(15), reviewCount: 5)]
        ))
        try ctxGuest.save()
        _ = try GuestDataMerge.enqueueGuestData(for: subjectA, in: ctxGuest)
        let engineGuest = SyncEngine(
            context: ctxGuest, transport: server.transport(for: subjectA),
            tables: ChildProgressSyncAdapters.all(), subject: subjectA
        )
        try await engineGuest.mergeSync()
        try await engineServer.sync()

        let onServer = try #require(LocalProgressStore(context: ctxServer).activeTrack(childId: childId))
        #expect(onServer.milestones["1"]?.state == "mastered")
        #expect(onServer.milestones["1"]?.reviewCount == 5)
        #expect(try engineGuest.pendingChanges().isEmpty)
    }

    @Test("same-ID Lord's Day note and card resolve by LWW on merge while preserving order")
    func sameIdNoteAndCardResolveByLWW() async throws {
        let server = FakeFullAccountSyncServer()
        let noteId = UUID()
        let cardId = UUID()

        // Server has note at t=50 ("Server Title") and card at t=20 ("Older Card Body").
        let ctx1 = try makeContext()
        let store1 = LordsDayStore(context: ctx1, syncSubject: subjectA, now: { gmStamp(50) })
        let n1 = LordsDayNote(id: noteId, serviceDate: gmStamp(0), sermonTitle: "Server Title", createdAt: gmStamp(1), updatedAt: gmStamp(50))
        try store1.save(n1)
        let c1 = NoteCard(id: cardId, noteId: noteId, kind: .keyPoint, body: "Older Card Body", verseRef: nil, attribution: nil, palette: nil, position: 0, editedByUser: false, createdAt: gmStamp(2), updatedAt: gmStamp(20), deletedAt: nil)
        ctx1.insert(c1)
        try ctx1.save()
        _ = try GuestDataMerge.enqueueGuestData(for: subjectA, in: ctx1)
        let engine1 = SyncEngine(context: ctx1, transport: server.transport(for: subjectA), tables: AccountSyncAdapters.all(), subject: subjectA)
        try await engine1.sync()

        // Guest has SAME noteId at t=10 ("Older Guest Title") and SAME cardId at t=80 ("Newer Guest Card Body").
        let ctx2 = try makeContext()
        let n2 = LordsDayNote(id: noteId, serviceDate: gmStamp(0), sermonTitle: "Older Guest Title", createdAt: gmStamp(1), updatedAt: gmStamp(10))
        let c2 = NoteCard(id: cardId, noteId: noteId, kind: .keyPoint, body: "Newer Guest Card Body", verseRef: nil, attribution: nil, palette: nil, position: 0, editedByUser: true, createdAt: gmStamp(2), updatedAt: gmStamp(80), deletedAt: nil)
        ctx2.insert(n2)
        ctx2.insert(c2)
        try ctx2.save()

        _ = try GuestDataMerge.enqueueGuestData(for: subjectA, in: ctx2)
        let engine2 = SyncEngine(context: ctx2, transport: server.transport(for: subjectA), tables: AccountSyncAdapters.all(), subject: subjectA)
        try await engine2.mergeSync()
        try await engine1.sync()

        let ld1 = LordsDayStore(context: ctx1)
        let ld2 = LordsDayStore(context: ctx2)
        #expect(try ld1.note(id: noteId)?.sermonTitle == "Server Title")
        #expect(try ld2.note(id: noteId)?.sermonTitle == "Server Title")
        #expect(try ld1.cards(for: try #require(try ld1.note(id: noteId))).first?.body == "Newer Guest Card Body")
        #expect(try ld2.cards(for: try #require(try ld2.note(id: noteId))).first?.body == "Newer Guest Card Body")
    }

    @Test("sign-out clears all synced account data back to empty guest state, and signing into a different account never uploads the first account's data")
    func signOutClearsDeviceAndIsolatesSecondAccount() async throws {
        let server = FakeFullAccountSyncServer()
        let ctx = try makeContext()

        // Account A creates children, progress, and a Lord's Day note + card, and syncs.
        let progressA = LocalProgressStore(context: ctx, syncSubject: subjectA)
        let lordsDayA = LordsDayStore(context: ctx, syncSubject: subjectA, now: { gmStamp(10) })
        let engineA = SyncEngine(
            context: ctx, transport: server.transport(for: subjectA),
            tables: AccountSyncAdapters.all(), subject: subjectA
        )

        let childA = try progressA.addChild(name: "AccountAChild", now: gmStamp(1))
        _ = progressA.resumeOrStartTrack(childId: childA.id, catechismId: "WSC", now: gmStamp(2))
        _ = progressA.advanceQuestion(childId: childA.id, catechismId: "WSC", totalQuestions: 107, now: gmStamp(3))
        let noteA = LordsDayNote(serviceDate: gmStamp(0), sermonTitle: "Account A Sermon", createdAt: gmStamp(4), updatedAt: gmStamp(4))
        try lordsDayA.save(noteA)
        _ = try lordsDayA.appendCard(to: noteA, kind: .keyPoint, body: "Secret to Account A")
        try await engineA.sync()

        // Also create an unpushed local edit right before sign-out to verify outbox is cleared too.
        _ = progressA.advanceQuestion(childId: childA.id, catechismId: "WSC", totalQuestions: 107, now: gmStamp(5))
        #expect(try !engineA.pendingChanges().isEmpty)
        #expect(try SyncEngine.hasSyncedState(for: subjectA, in: ctx) == true)

        // User confirms Sign out -> clears all synced data back to an empty guest state.
        engineA.invalidate()
        try AccountDataCleanup.clearSyncedData(for: subjectA, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<LocalChild>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ChildCatechismTrack>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<LordsDayNote>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<NoteCard>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<SyncCursorRecord>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<SyncRowMeta>()).isEmpty)
        #expect(LocalProgressStore(context: ctx).activeChildId == nil)
        #expect(try GuestDataMerge.summary(in: ctx).hasData == false)
        #expect(try SyncEngine.hasSyncedState(for: subjectA, in: ctx) == false)

        // Now Account B signs in on the SAME device.
        // Account B already has its own child on the server.
        let ctxBOther = try makeContext()
        let progressBOther = LocalProgressStore(context: ctxBOther, syncSubject: subjectB)
        let childB = try progressBOther.addChild(name: "AccountBChild", now: gmStamp(10))
        let engineBOther = SyncEngine(
            context: ctxBOther, transport: server.transport(for: subjectB),
            tables: AccountSyncAdapters.all(), subject: subjectB
        )
        try await engineBOther.sync()
        server.pushedBySubject[subjectB] = []

        // Device signs into Account B: nothing to merge, pulls only Account B's data, uploads ZERO rows from Account A!
        #expect(try GuestDataMerge.enqueueGuestData(for: subjectB, in: ctx) == 0)
        let engineB = SyncEngine(
            context: ctx, transport: server.transport(for: subjectB),
            tables: AccountSyncAdapters.all(), subject: subjectB
        )
        try await engineB.sync()

        #expect((server.pushedBySubject[subjectB] ?? []).isEmpty)
        let childrenOnDevice = try ctx.fetch(FetchDescriptor<LocalChild>())
        #expect(childrenOnDevice.map(\.id) == [childB.id])
        #expect(try ctx.fetch(FetchDescriptor<LordsDayNote>()).isEmpty)
    }
}
