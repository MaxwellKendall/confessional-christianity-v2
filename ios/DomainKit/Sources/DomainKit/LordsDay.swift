import Foundation
import SwiftData

public enum CardKind: String, Codable, CaseIterable, Sendable {
    case keyPoint = "key_point", quote, verse
}

@Model public final class LordsDayNote {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID?
    public var serviceDate: Date
    public var passageRef: String?
    public var sermonTitle: String?
    public var preacher: String?
    public var church: String?
    public var extractedText: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), userId: UUID? = nil, serviceDate: Date, passageRef: String? = nil, sermonTitle: String? = nil, preacher: String? = nil, church: String? = nil, extractedText: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id; self.userId = userId; self.serviceDate = SyncTimestamp.truncate(serviceDate)
        self.passageRef = passageRef; self.sermonTitle = sermonTitle; self.preacher = preacher
        self.church = church; self.extractedText = extractedText
        self.createdAt = SyncTimestamp.truncate(createdAt)
        self.updatedAt = SyncTimestamp.truncate(updatedAt)
        self.deletedAt = deletedAt.map(SyncTimestamp.truncate)
    }

    func applySynced(
        serviceDate: Date,
        passageRef: String?,
        sermonTitle: String?,
        preacher: String?,
        church: String?,
        extractedText: String?,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.serviceDate = serviceDate
        self.passageRef = passageRef
        self.sermonTitle = sermonTitle
        self.preacher = preacher
        self.church = church
        self.extractedText = extractedText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model public final class NoteCard {
    @Attribute(.unique) public var id: UUID
    public var noteId: UUID
    public var userId: UUID?
    public private(set) var kind: CardKind
    public private(set) var body: String
    public private(set) var verseRef: String?
    public var attribution: String?
    public var palette: String?
    public var position: Int
    public var editedByUser: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    fileprivate init(noteId: UUID, userId: UUID?, kind: CardKind, body: String, verseRef: String?, position: Int, attribution: String? = nil, palette: String? = nil, editedByUser: Bool = false, now: Date = Date()) {
        let stamped = SyncTimestamp.truncate(now)
        self.id = UUID(); self.noteId = noteId; self.userId = userId; self.kind = kind
        self.body = body; self.verseRef = verseRef; self.position = position; self.attribution = attribution
        self.palette = palette; self.editedByUser = editedByUser; self.createdAt = stamped; self.updatedAt = stamped
    }

    init(
        id: UUID,
        noteId: UUID,
        userId: UUID? = nil,
        kind: CardKind,
        body: String,
        verseRef: String?,
        attribution: String?,
        palette: String?,
        position: Int,
        editedByUser: Bool,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.id = id; self.noteId = noteId; self.userId = userId; self.kind = kind
        self.body = body; self.verseRef = verseRef; self.attribution = attribution
        self.palette = palette; self.position = position; self.editedByUser = editedByUser
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    func applySynced(
        noteId: UUID,
        kind: CardKind,
        body: String,
        verseRef: String?,
        attribution: String?,
        palette: String?,
        position: Int,
        editedByUser: Bool,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.noteId = noteId; self.kind = kind; self.body = body; self.verseRef = verseRef
        self.attribution = attribution; self.palette = palette; self.position = position
        self.editedByUser = editedByUser; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    fileprivate func update(kind: CardKind, body: String, verseRef: String?, updatedAt: Date) {
        self.kind = kind; self.body = body; self.verseRef = verseRef
        editedByUser = true; self.updatedAt = updatedAt
    }

    /// Deterministic ordering across devices even when two devices append at the same position offline.
    public static func ordered(_ lhs: NoteCard, before rhs: NoteCard) -> Bool {
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }
}

public enum LordsDayError: Error, Equatable { case invalidVerse, invalidOrder, invalidPassage }

/// Sunday selects the first card; Monday through Saturday advance and clamp.
/// A new Sunday belongs to a new week. Calendar days, rather than seconds, handle DST.
public func todayCardIndex(serviceDate: Date, today: Date, cardCount: Int, calendar: Calendar = .current) -> Int? {
    guard cardCount > 0 else { return nil }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: serviceDate), to: calendar.startOfDay(for: today)).day ?? -1
    guard (0..<7).contains(days) else { return nil }
    return min(max(days - 1, 0), cardCount - 1)
}

@MainActor public final class LordsDayStore {
    private let context: ModelContext
    private let syncSubject: String?
    private let onLocalWrite: (@MainActor () -> Void)?
    private let now: () -> Date

    public init(
        context: ModelContext,
        syncSubject: String? = nil,
        onLocalWrite: (@MainActor () -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.syncSubject = syncSubject
        self.onLocalWrite = onLocalWrite
        self.now = now
    }

    private func stampedNow(after previous: Date? = nil) -> Date {
        let current = now()
        guard let previous else { return SyncTimestamp.truncate(current) }
        return SyncTimestamp.monotonic(current, after: previous)
    }

    public func save(_ note: LordsDayNote) throws {
        note.serviceDate = SyncTimestamp.truncate(note.serviceDate)
        note.createdAt = SyncTimestamp.truncate(note.createdAt)
        note.updatedAt = SyncTimestamp.truncate(note.updatedAt)
        context.insert(note)
        try enqueueNoteUpsert(note)
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
    }

    public func update(_ note: LordsDayNote, _ mutate: (LordsDayNote) -> Void) throws {
        mutate(note)
        note.updatedAt = stampedNow(after: note.updatedAt)
        try save(note)
    }

    /// Saves edited sermon details from the focused sheet (TKL-1085 pass 1),
    /// validating the passage on the server's OSIS path and syncing the note.
    public func updateDetails(_ edit: SermonDetailsEdit, for note: LordsDayNote) throws {
        let canonicalPassage: String?
        if let raw = normalizedNoteField(edit.passage) {
            guard case .valid(let canonical, _) = validateSermonPassage(raw) else {
                throw LordsDayError.invalidPassage
            }
            canonicalPassage = canonical
        } else {
            canonicalPassage = nil
        }
        try update(note) { note in
            note.sermonTitle = normalizedNoteField(edit.title)
            note.preacher = normalizedNoteField(edit.preacher)
            note.passageRef = canonicalPassage
            note.church = normalizedNoteField(edit.church)
            note.serviceDate = SyncTimestamp.truncate(edit.serviceDate)
        }
    }

    public func removeNote(_ note: LordsDayNote) throws {
        let ts = stampedNow(after: note.updatedAt)
        for card in try cards(for: note) {
            let cardTs = stampedNow(after: max(card.updatedAt, ts))
            card.deletedAt = cardTs
            card.updatedAt = cardTs
            try enqueueCardTombstone(card, deletedAt: cardTs)
        }
        note.deletedAt = ts
        note.updatedAt = ts
        try enqueueNoteTombstone(note, deletedAt: ts)
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
    }

    /// Drops a review there is nothing to keep from (TKL-1103): its saved review and the
    /// note's photos go. A guest's note with no kept cards goes too. A signed-in device only
    /// forgets the review locally: its copy having no cards doesn't mean the account has none
    /// (another phone may have kept and synced cards for this note), so nothing is tombstoned.
    public func discardPendingReview(_ note: LordsDayNote, root: URL = CaptureDraft.defaultRoot) throws {
        try LordsDayReview.delete(noteId: note.id, root: root)
        let folder = root.appendingPathComponent(note.id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        if (try? CaptureDraft.activeNoteId(root: root)) == note.id { try CaptureDraft.setActive(nil, root: root) }
        guard try cards(for: note).isEmpty else { return }
        if syncSubject == nil {
            try removeNote(note)
        } else {
            try Self.markDiscarded(note.id, root: root)
        }
    }

    private static func discardedMarker(_ noteId: UUID, root: URL) -> URL {
        root.appendingPathComponent("discarded-reviews", isDirectory: true).appendingPathComponent(noteId.uuidString)
    }

    private static func markDiscarded(_ noteId: UUID, root: URL) throws {
        let marker = discardedMarker(noteId, root: root)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: marker, options: .atomic)
    }

    static func wasDiscarded(_ noteId: UUID, root: URL) -> Bool {
        FileManager.default.fileExists(atPath: discardedMarker(noteId, root: root).path)
    }

    public func cards(for note: LordsDayNote) throws -> [NoteCard] {
        try context.fetch(FetchDescriptor<NoteCard>())
            .filter { $0.noteId == note.id && $0.deletedAt == nil }
            .sorted(by: NoteCard.ordered)
    }

    @discardableResult public func appendCard(
        to note: LordsDayNote,
        kind: CardKind,
        body: String,
        verseRef: String? = nil,
        attribution: String? = nil,
        palette: String? = nil,
        editedByUser: Bool = false
    ) throws -> NoteCard {
        try validate(kind: kind, body: body, verseRef: verseRef)
        let ts = SyncTimestamp.truncate(now())
        let card = NoteCard(
            noteId: note.id, userId: note.userId, kind: kind, body: body, verseRef: verseRef,
            position: (try cards(for: note).map(\.position).max() ?? -1) + 1,
            attribution: attribution, palette: palette, editedByUser: editedByUser, now: ts
        )
        context.insert(card)
        try enqueueCardUpsert(card)
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
        return card
    }

    public func saveCard(_ card: NoteCard) throws {
        try validate(kind: card.kind, body: card.body, verseRef: card.verseRef)
        card.updatedAt = stampedNow(after: card.updatedAt)
        try enqueueCardUpsert(card)
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
    }

    public func reorderCards(for note: LordsDayNote, cards ordered: [NoteCard]) throws {
        let existing = try cards(for: note)
        guard ordered.count == existing.count, Set(ordered.map(\.id)) == Set(existing.map(\.id)) else { throw LordsDayError.invalidOrder }
        for (index, card) in ordered.enumerated() {
            let ts = stampedNow(after: card.updatedAt)
            card.position = index
            card.updatedAt = ts
            card.editedByUser = true
            try enqueueCardUpsert(card)
        }
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
    }

    public func editBody(of card: NoteCard, body: String) throws {
        try validate(kind: card.kind, body: body, verseRef: card.verseRef)
        let ts = stampedNow(after: card.updatedAt)
        card.update(kind: card.kind, body: body, verseRef: card.verseRef, updatedAt: ts)
        try enqueueCardUpsert(card)
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
    }

    public func switchKind(of card: NoteCard, to kind: CardKind, verseRef: String? = nil) throws {
        let body = kind == .verse ? "" : card.body
        try validate(kind: kind, body: body, verseRef: verseRef)
        let ts = stampedNow(after: card.updatedAt)
        card.update(kind: kind, body: body, verseRef: kind == .verse ? verseRef : nil, updatedAt: ts)
        try enqueueCardUpsert(card)
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
    }

    /// Finishing a review (TKL-863): the note's cards become exactly `kept`, in order.
    /// Every card is validated first, so a rejected keep changes nothing.
    public func keepCards(_ kept: [KeptCard], for note: LordsDayNote) throws {
        for card in kept { try validate(kind: card.kind, body: card.body, verseRef: card.verseRef) }
        let ts = stampedNow(after: note.updatedAt)
        note.updatedAt = ts
        context.insert(note)
        // Always enqueue the parent note first so card writes on the server find an owned parent note.
        try enqueueNoteUpsert(note)
        for old in try cards(for: note) {
            let oldTs = stampedNow(after: max(old.updatedAt, ts))
            old.deletedAt = oldTs
            old.updatedAt = oldTs
            try enqueueCardTombstone(old, deletedAt: oldTs)
        }
        for (position, card) in kept.enumerated() {
            let created = NoteCard(
                noteId: note.id, userId: note.userId, kind: card.kind, body: card.body, verseRef: card.verseRef,
                position: position, attribution: card.kind == .quote ? card.attribution : nil,
                editedByUser: card.editedByUser, now: ts
            )
            context.insert(created)
            try enqueueCardUpsert(created)
        }
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
    }

    /// Every live note, for the journal (TKL-944).
    func allNotes() throws -> [LordsDayNote] {
        try context.fetch(FetchDescriptor<LordsDayNote>(predicate: #Predicate { $0.deletedAt == nil }))
    }
    func allCards() throws -> [NoteCard] { try context.fetch(FetchDescriptor<NoteCard>()) }

    public func removeCard(_ card: NoteCard) throws {
        let ts = stampedNow(after: card.updatedAt)
        card.deletedAt = ts
        card.updatedAt = ts
        try enqueueCardTombstone(card, deletedAt: ts)
        try context.save()
        if syncSubject != nil { onLocalWrite?() }
    }

    // MARK: Sync outbox helpers

    private func enqueueNoteUpsert(_ note: LordsDayNote) throws {
        guard let subject = syncSubject else { return }
        let nid = note.id.uuidString.lowercased()
        let payload = try LordsDayNoteSyncPayload.encode(note)
        try SyncMetaStore.upsert(
            table: SyncTable.lordsDayNotes, rowId: nid, childId: "", naturalKey: nid,
            updatedAt: note.updatedAt, in: context
        )
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.lordsDayNotes, rowId: nid, childId: nil, noteId: nid,
            payload: payload, updatedAt: note.updatedAt, in: context
        )
    }

    private func enqueueNoteTombstone(_ note: LordsDayNote, deletedAt: Date) throws {
        guard let subject = syncSubject else { return }
        let nid = note.id.uuidString.lowercased()
        try SyncMetaStore.upsert(
            table: SyncTable.lordsDayNotes, rowId: nid, childId: "", naturalKey: nid,
            updatedAt: deletedAt, in: context
        )
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.lordsDayNotes, rowId: nid, childId: nil, noteId: nid,
            payload: nil, updatedAt: deletedAt, deletedAt: deletedAt, in: context
        )
    }

    private func enqueueCardUpsert(_ card: NoteCard) throws {
        guard let subject = syncSubject else { return }
        let cid = card.id.uuidString.lowercased()
        let nid = card.noteId.uuidString.lowercased()
        let payload = try JSONEncoder().encode(NoteCardSyncPayload(
            kind: card.kind.rawValue,
            body: card.body,
            verse_ref: card.verseRef,
            attribution: card.attribution,
            palette: card.palette,
            position: card.position,
            edited_by_user: card.editedByUser,
            created_at: SyncTimestamp.format(card.createdAt)
        ))
        try SyncMetaStore.upsert(
            table: SyncTable.noteCards, rowId: cid, childId: "", naturalKey: nid,
            updatedAt: card.updatedAt, in: context
        )
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.noteCards, rowId: cid, childId: nil, noteId: nid,
            payload: payload, updatedAt: card.updatedAt, in: context
        )
    }

    private func enqueueCardTombstone(_ card: NoteCard, deletedAt: Date) throws {
        guard let subject = syncSubject else { return }
        let cid = card.id.uuidString.lowercased()
        let nid = card.noteId.uuidString.lowercased()
        try SyncMetaStore.upsert(
            table: SyncTable.noteCards, rowId: cid, childId: "", naturalKey: nid,
            updatedAt: deletedAt, in: context
        )
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.noteCards, rowId: cid, childId: nil, noteId: nid,
            payload: nil, updatedAt: deletedAt, deletedAt: deletedAt, in: context
        )
    }
    public func note(id: UUID) throws -> LordsDayNote? {
        try context.fetch(FetchDescriptor<LordsDayNote>()).first { $0.id == id && $0.deletedAt == nil }
    }
    /// Notes with a saved review, an active in-memory review session, or saved capture
    /// input not yet turned into cards — independent of service date or current week (TKL-940).
    public func pendingReviewNotes(root: URL = CaptureDraft.defaultRoot, activeSessionIds: Set<UUID> = []) throws -> [LordsDayNote] {
        let activeCaptureId = try? CaptureDraft.activeNoteId(root: root)
        let notes = try context.fetch(FetchDescriptor<LordsDayNote>())
            .filter { $0.deletedAt == nil && $0.id != activeCaptureId }
            .sorted { $0.updatedAt > $1.updatedAt }
        return try notes.filter { note in
            if activeSessionIds.contains(note.id) { return true }
            if LordsDayReview.exists(noteId: note.id, root: root) { return true }
            guard try cards(for: note).isEmpty, !Self.wasDiscarded(note.id, root: root) else { return false }
            return CaptureDraft.savedPageCount(noteId: note.id, root: root) > 0 || normalizedNoteField(note.extractedText) != nil
        }
    }
    public func currentWeek(on date: Date = Date(), calendar: Calendar = .current) throws -> LordsDayNote? {
        try context.fetch(FetchDescriptor<LordsDayNote>())
            .filter { $0.deletedAt == nil && todayCardIndex(serviceDate: $0.serviceDate, today: date, cardCount: 1, calendar: calendar) != nil }
            .max { ($0.serviceDate, $0.updatedAt) < ($1.serviceDate, $1.updatedAt) }
    }
    /// Newest note in the current week that already has kept cards.
    public func currentWeekWithCards(on date: Date = Date(), calendar: Calendar = .current) throws -> (note: LordsDayNote, cards: [NoteCard])? {
        let candidates = try context.fetch(FetchDescriptor<LordsDayNote>())
            .filter { $0.deletedAt == nil && todayCardIndex(serviceDate: $0.serviceDate, today: date, cardCount: 1, calendar: calendar) != nil }
            .sorted { ($0.serviceDate, $0.updatedAt) > ($1.serviceDate, $1.updatedAt) }
        for note in candidates {
            let noteCards = try cards(for: note)
            if !noteCards.isEmpty { return (note, noteCards) }
        }
        return nil
    }
    public func archive(before date: Date = Date(), calendar: Calendar = .current) throws -> [LordsDayNote] {
        let today = calendar.startOfDay(for: date)
        return try context.fetch(FetchDescriptor<LordsDayNote>()).filter { note in
            guard note.deletedAt == nil, let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: note.serviceDate)) else { return false }
            return end <= today
        }.sorted { $0.serviceDate > $1.serviceDate }
    }
    private func validate(kind: CardKind, body: String, verseRef: String?) throws {
        if kind == .verse && (!body.isEmpty || (verseRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)) { throw LordsDayError.invalidVerse }
    }
}
