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
        self.id = id; self.userId = userId; self.serviceDate = serviceDate
        self.passageRef = passageRef; self.sermonTitle = sermonTitle; self.preacher = preacher
        self.church = church; self.extractedText = extractedText; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
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

    fileprivate init(noteId: UUID, userId: UUID?, kind: CardKind, body: String, verseRef: String?, position: Int, attribution: String? = nil, editedByUser: Bool = false) {
        self.id = UUID(); self.noteId = noteId; self.userId = userId; self.kind = kind
        self.body = body; self.verseRef = verseRef; self.position = position; self.attribution = attribution
        self.editedByUser = editedByUser; self.createdAt = Date(); self.updatedAt = Date()
    }
    fileprivate func update(kind: CardKind, body: String, verseRef: String?) {
        self.kind = kind; self.body = body; self.verseRef = verseRef
        editedByUser = true; updatedAt = Date()
    }
}

public enum LordsDayError: Error { case invalidVerse, invalidOrder }

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
    public init(context: ModelContext) { self.context = context }
    public func save(_ note: LordsDayNote) throws { context.insert(note); try context.save() }
    public func cards(for note: LordsDayNote) throws -> [NoteCard] {
        try context.fetch(FetchDescriptor<NoteCard>()).filter { $0.noteId == note.id && $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }
    @discardableResult public func appendCard(to note: LordsDayNote, kind: CardKind, body: String, verseRef: String? = nil) throws -> NoteCard {
        try validate(kind: kind, body: body, verseRef: verseRef)
        let card = NoteCard(noteId: note.id, userId: note.userId, kind: kind, body: body, verseRef: verseRef, position: (try cards(for: note).map(\.position).max() ?? -1) + 1)
        context.insert(card); try context.save(); return card
    }
    public func reorderCards(for note: LordsDayNote, cards ordered: [NoteCard]) throws {
        let existing = try cards(for: note)
        guard ordered.count == existing.count, Set(ordered.map(\.id)) == Set(existing.map(\.id)) else { throw LordsDayError.invalidOrder }
        for (index, card) in ordered.enumerated() { card.position = index; card.updatedAt = Date(); card.editedByUser = true }
        try context.save()
    }
    public func editBody(of card: NoteCard, body: String) throws {
        try validate(kind: card.kind, body: body, verseRef: card.verseRef)
        card.update(kind: card.kind, body: body, verseRef: card.verseRef); try context.save()
    }
    public func switchKind(of card: NoteCard, to kind: CardKind, verseRef: String? = nil) throws {
        let body = kind == .verse ? "" : card.body
        try validate(kind: kind, body: body, verseRef: verseRef)
        card.update(kind: kind, body: body, verseRef: kind == .verse ? verseRef : nil); try context.save()
    }
    /// Finishing a review (TKL-863): the note's cards become exactly `kept`, in order.
    /// Every card is validated first, so a rejected keep changes nothing.
    public func keepCards(_ kept: [KeptCard], for note: LordsDayNote) throws {
        for card in kept { try validate(kind: card.kind, body: card.body, verseRef: card.verseRef) }
        let now = Date()
        for old in try cards(for: note) { old.deletedAt = now; old.updatedAt = now }
        for (position, card) in kept.enumerated() {
            context.insert(NoteCard(noteId: note.id, userId: note.userId, kind: card.kind, body: card.body, verseRef: card.verseRef,
                                    position: position, attribution: card.kind == .quote ? card.attribution : nil, editedByUser: card.editedByUser))
        }
        note.updatedAt = now
        try context.save()
    }
    public func removeCard(_ card: NoteCard) throws { card.deletedAt = Date(); card.updatedAt = Date(); try context.save() }
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
            guard try cards(for: note).isEmpty else { return false }
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
