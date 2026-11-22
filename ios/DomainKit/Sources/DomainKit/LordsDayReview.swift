import Foundation

// Reviewing the drafted cards before the week is kept (TKL-863). A model read
// someone's handwriting; nothing becomes a NoteCard until the user has seen
// each draft and kept it. Drafts arrive one event at a time from
// `POST /api/lords-day/cards` (an NDJSON stream, src/lib/lordsDay/handler.ts),
// are saved to a file beside the note's photos after every change, and survive
// leaving the screen or the app. A Verse card only ever holds a reference: the
// generator never supplies Scripture text, and the user can't type it either.

// MARK: The stream

/// One card as the endpoint drafts it (`DraftCard` in src/lib/lordsDay/cards.ts).
public struct DraftCardPayload: Codable, Equatable, Sendable {
    public var kind: String
    public var page: Int
    public var order: Int
    public var text: String?
    public var reference: String?
    public var osis: String?
    public var attribution: String?

    public init(kind: String, page: Int, order: Int, text: String? = nil, reference: String? = nil, osis: String? = nil, attribution: String? = nil) {
        self.kind = kind; self.page = page; self.order = order; self.text = text
        self.reference = reference; self.osis = osis; self.attribution = attribution
    }
}

/// The events of the generator's NDJSON stream that the review uses.
public enum LordsDayCardsEvent: Equatable, Sendable {
    case started(pages: Int)
    /// That page was read; its cards follow.
    case page(Int)
    case card(DraftCardPayload)
    /// That page failed; the others continue.
    case pageFailed(Int)
    case done(failedPages: [Int])

    private struct Line: Decodable {
        let type: String
        let pages: Int?
        let page: Int?
        let card: DraftCardPayload?
        let failedPages: [Int]?
    }

    /// Nil for a blank line or an event type this app doesn't know (the server may add some).
    public static func parse(line: String) throws -> LordsDayCardsEvent? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let event = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
        switch event.type {
        case "started": return .started(pages: event.pages ?? 0)
        case "page": return event.page.map(LordsDayCardsEvent.page)
        case "card": return event.card.map(LordsDayCardsEvent.card)
        case "error": return event.page.map(LordsDayCardsEvent.pageFailed)
        case "done": return .done(failedPages: event.failedPages ?? [])
        default: return nil
        }
    }
}

// MARK: The review

public enum LordsDayReviewError: Error, Equatable { case noSuchCard, verseNeedsReference, versesHaveNoWords, onlyQuotesAreAttributed }

/// One drafted card as the user is reviewing it.
public struct ReviewCard: Codable, Equatable, Identifiable, Sendable {
    /// `p<page>-<order>` in the note's own page numbering.
    public let id: String
    public let page: Int
    public let order: Int
    public fileprivate(set) var kind: CardKind
    /// The words of a key point or quote. Kept while the card is a verse, so switching back restores them.
    public fileprivate(set) var words: String
    /// A verse's reference (OSIS when known); nil for other kinds.
    public fileprivate(set) var verseRef: String?
    /// A quote's attribution. Nil uses the note's preacher; empty means the user cleared it.
    public fileprivate(set) var attribution: String?
    public fileprivate(set) var kept: Bool
    public fileprivate(set) var editedByUser: Bool

    /// What the card shows: a verse has no words of its own.
    public var text: String { kind == .verse ? "" : words }
    /// A kept key point or quote needs words.
    public var isComplete: Bool { kind == .verse ? normalizedNoteField(verseRef) != nil : normalizedNoteField(words) != nil }
}

/// What finishing the review hands to `LordsDayStore.keepCards`.
public struct KeptCard: Equatable, Sendable {
    public let kind: CardKind
    public let body: String
    public let verseRef: String?
    public let attribution: String?
    public let editedByUser: Bool
    public init(kind: CardKind, body: String, verseRef: String?, attribution: String?, editedByUser: Bool) {
        self.kind = kind; self.body = body; self.verseRef = verseRef; self.attribution = attribution; self.editedByUser = editedByUser
    }
}

public struct LordsDayReview: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        /// Nothing has been sent yet.
        case notStarted
        /// A request is streaming cards in.
        case drafting
        /// The stream stopped before it said it was done (offline, closed, killed). Retry reads the rest.
        case interrupted
        /// The stream finished; some pages may have failed.
        case ready
    }

    public let noteId: UUID
    /// Photos, or 1 for typed notes.
    public let pageCount: Int
    public private(set) var phase: Phase = .notStarted
    public private(set) var cards: [ReviewCard] = []
    public private(set) var readPages: Set<Int> = []
    public private(set) var failedPages: Set<Int> = []
    /// The note page each page of the request in flight stands for (a retry sends only some).
    private var requestPages: [Int] = []

    public init(noteId: UUID, pageCount: Int) {
        self.noteId = noteId
        self.pageCount = max(pageCount, 1)
    }

    public var isDrafting: Bool { phase == .drafting }
    public var progress: Double { Double(readPages.count + failedPages.count) / Double(pageCount) }
    public var unreadPages: [Int] { (0..<pageCount).filter { !readPages.contains($0) } }
    public var canRetry: Bool { !isDrafting && phase != .notStarted && !unreadPages.isEmpty }
    /// The first kept card that can't be kept as it is (a key point or quote with no words).
    public var blockingCardIndex: Int? { cards.firstIndex { $0.kept && !$0.isComplete } }
    public var keptCount: Int { cards.filter(\.kept).count }
    public var canFinish: Bool { !isDrafting && keptCount > 0 && blockingCardIndex == nil }

    public func card(_ id: String) -> ReviewCard? { cards.first { $0.id == id } }

    /// Starts a run for every page not yet read and returns those note pages, in order.
    public mutating func begin() -> [Int] {
        requestPages = unreadPages
        failedPages.subtract(requestPages)
        phase = .drafting
        return requestPages
    }

    public mutating func apply(_ event: LordsDayCardsEvent) {
        guard phase == .drafting else { return }
        switch event {
        case .started:
            break
        case .page(let page):
            if let page = notePage(page) { readPages.insert(page); failedPages.remove(page) }
        case .pageFailed(let page):
            if let page = notePage(page), !readPages.contains(page) { failedPages.insert(page) }
        case .card(let draft):
            guard let page = notePage(draft.page), let kind = CardKind(rawValue: draft.kind) else { return }
            let id = "p\(page)-\(draft.order)"
            guard card(id) == nil else { return }
            let reference = normalizedNoteField(draft.osis) ?? normalizedNoteField(draft.reference)
            if kind == .verse && reference == nil { return }
            cards.append(ReviewCard(
                id: id, page: page, order: draft.order, kind: kind,
                words: kind == .verse ? "" : (draft.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                verseRef: kind == .verse ? reference : nil,
                attribution: kind == .quote ? normalizedNoteField(draft.attribution) : nil,
                kept: true, editedByUser: false
            ))
            cards.sort { ($0.page, $0.order) < ($1.page, $1.order) }
        case .done(let failed):
            for page in failed.compactMap(notePage) where !readPages.contains(page) { failedPages.insert(page) }
            phase = .ready
        }
    }

    /// The stream ended without `done`.
    public mutating func interrupt() {
        if phase == .drafting { phase = .interrupted }
    }

    private func notePage(_ requestPage: Int) -> Int? {
        requestPages.indices.contains(requestPage) ? requestPages[requestPage] : nil
    }

    // MARK: Changes the user makes

    public mutating func keep(_ id: String) { update(id) { $0.kept = true } }
    public mutating func remove(_ id: String) { update(id) { $0.kept = false } }

    /// Key point or quote. Verse goes through `chooseVerse`, because a verse needs a picked reference.
    public mutating func setKind(_ id: String, to kind: CardKind) throws {
        guard kind != .verse else { throw LordsDayReviewError.verseNeedsReference }
        try change(id) { card in
            guard card.kind != kind else { return false }
            card.kind = kind
            card.verseRef = nil
            return true
        }
    }

    /// Makes the card a Verse holding only `osis`, picked in the reader.
    public mutating func chooseVerse(_ id: String, osis: String) throws {
        guard let reference = normalizedNoteField(osis) else { throw LordsDayReviewError.verseNeedsReference }
        try change(id) { card in
            guard card.kind != .verse || card.verseRef != reference else { return false }
            card.kind = .verse
            card.verseRef = reference
            return true
        }
    }

    public mutating func editText(_ id: String, to text: String) throws {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try change(id) { card in
            guard card.kind != .verse else { throw LordsDayReviewError.versesHaveNoWords }
            guard card.words != words else { return false }
            card.words = words
            return true
        }
    }

    /// Blank clears it: the card then names no one, not even the preacher.
    public mutating func editAttribution(_ id: String, to text: String) throws {
        let attribution = normalizedNoteField(text) ?? ""
        try change(id) { card in
            guard card.kind == .quote else { throw LordsDayReviewError.onlyQuotesAreAttributed }
            guard card.attribution != attribution else { return false }
            card.attribution = attribution
            return true
        }
    }

    /// The kept cards, in order, as they will be stored.
    public func keptCards() -> [KeptCard] {
        cards.filter(\.kept).map { card in
            KeptCard(kind: card.kind, body: card.text, verseRef: card.kind == .verse ? card.verseRef : nil,
                     attribution: card.kind == .quote ? card.attribution : nil, editedByUser: card.editedByUser)
        }
    }

    private mutating func update(_ id: String, _ body: (inout ReviewCard) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        body(&cards[index])
    }

    /// `body` returns whether it changed the card; a real change marks it edited.
    private mutating func change(_ id: String, _ body: (inout ReviewCard) throws -> Bool) throws {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { throw LordsDayReviewError.noSuchCard }
        var card = cards[index]
        if try body(&card) {
            card.editedByUser = true
            cards[index] = card
        }
    }

    // MARK: Saved beside the note's photos

    /// `<root>/<noteId>/review.json`, in the app-private capture folder (excluded from backup).
    public static func url(noteId: UUID, root: URL = CaptureDraft.defaultRoot) -> URL {
        root.appendingPathComponent(noteId.uuidString, isDirectory: true).appendingPathComponent("review.json")
    }

    /// A review saved mid-run comes back interrupted: nothing is streaming into it any more.
    public static func load(noteId: UUID, root: URL = CaptureDraft.defaultRoot) throws -> LordsDayReview? {
        guard let data = try? Data(contentsOf: url(noteId: noteId, root: root)) else { return nil }
        var review = try JSONDecoder().decode(LordsDayReview.self, from: data)
        review.interrupt()
        return review
    }

    public func save(root: URL = CaptureDraft.defaultRoot) throws {
        let file = Self.url(noteId: noteId, root: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }

    public static func delete(noteId: UUID, root: URL = CaptureDraft.defaultRoot) throws {
        let file = url(noteId: noteId, root: root)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
