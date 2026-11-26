import Foundation

// Reviewing the drafted cards before the week is kept (TKL-863, repaired in
// TKL-940). A model read someone's handwriting; nothing becomes a NoteCard
// until the user has explicitly kept it. Drafts arrive one event at a time from
// `POST /api/lords-day/cards` (an NDJSON stream, src/lib/lordsDay/handler.ts),
// are saved to a file beside the note's photos after every change, and survive
// leaving the screen or the app. A page counts as read only after all its cards
// have arrived. A Verse card only ever holds a reference: the generator never
// supplies Scripture text, and the user can't type it either.

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
    /// Server-assigned immutable card identity, preserved across retries of the same page.
    public var sourceKey: String?

    public init(kind: String, page: Int, order: Int, text: String? = nil, reference: String? = nil, osis: String? = nil, attribution: String? = nil, sourceKey: String? = nil) {
        self.kind = kind; self.page = page; self.order = order; self.text = text
        self.reference = reference; self.osis = osis; self.attribution = attribution; self.sourceKey = sourceKey
    }
}

/// The events of the generator's NDJSON stream that the review uses.
public enum LordsDayCardsEvent: Equatable, Sendable {
    case started(pages: Int)
    /// That page was read; `cardCount` (when supplied by the server) tells how many card events follow,
    /// and `extractedText` is the model's transcription of it, shown while the rest is still drafting.
    case page(Int, cardCount: Int? = nil, extractedText: String? = nil, generationId: String? = nil)
    case card(DraftCardPayload)
    /// That page failed; the others continue.
    case pageFailed(Int)
    /// The original generated page is no longer available to replay; existing partial cards stay untouched.
    case pageReplayUnavailable(Int)
    case done(failedPages: [Int])

    private struct Line: Decodable {
        let type: String
        let pages: Int?
        let page: Int?
        let code: String?
        let generationId: String?
        let cardCount: Int?
        let extractedText: String?
        let card: DraftCardPayload?
        let failedPages: [Int]?
    }

    /// Nil for a blank line or an event type this app doesn't know (the server may add some).
    public static func parse(line: String) throws -> LordsDayCardsEvent? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let event = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
        switch event.type {
        case "started": return .started(pages: event.pages ?? 0)
        case "page": return event.page.map { .page($0, cardCount: event.cardCount, extractedText: event.extractedText, generationId: event.generationId) }
        case "card": return event.card.map(LordsDayCardsEvent.card)
        case "error":
            guard let page = event.page else { return nil }
            return event.code == "replay_unavailable" ? .pageReplayUnavailable(page) : .pageFailed(page)
        case "done": return .done(failedPages: event.failedPages ?? [])
        default: return nil
        }
    }
}

// MARK: The review

public enum LordsDayReviewError: Error, Equatable {
    case noSuchCard, verseNeedsReference, versesHaveNoWords, onlyQuotesAreAttributed, unreviewedCards, unreadPagesRemaining, nothingToKeep
}

/// One drafted card as the user is reviewing it.
public struct ReviewCard: Codable, Equatable, Identifiable, Sendable {
    public enum Decision: String, Codable, Equatable, Sendable {
        /// Legacy: only in reviews saved before cards arrived kept. Reads as kept.
        case undecided
        case keep
        case remove
    }

    /// Stable card id on this review (`p<page>-<index>`).
    public let id: String
    public let page: Int
    public fileprivate(set) var order: Int
    public fileprivate(set) var kind: CardKind
    /// The words of a key point or quote. Kept while the card is a verse, so switching back restores them.
    public fileprivate(set) var words: String
    /// A verse's reference (OSIS when known); nil for other kinds.
    public fileprivate(set) var verseRef: String?
    /// A quote's attribution. Nil uses the note's preacher; empty means the user cleared it.
    public fileprivate(set) var attribution: String?
    public fileprivate(set) var decision: Decision
    public fileprivate(set) var editedByUser: Bool
    /// Immutable identity of the drafted source payload, separate from user edits,
    /// so a retry reconciles against the card it originally drafted.
    /// Nil for cards loaded from a review saved by an earlier build before `sourceKey` existed.
    public fileprivate(set) var sourceKey: String?

    /// Kept unless explicitly removed. `undecided` only ever comes from a review
    /// saved before cards began arriving kept (TKL-1053); it reads as kept.
    public var kept: Bool { decision != .remove }
    public var isRemoved: Bool { decision == .remove }
    public var isUndecided: Bool { decision == .undecided }

    /// What the card shows: a verse has no words of its own.
    public var text: String { kind == .verse ? "" : words }
    /// A kept key point or quote needs words.
    public var isComplete: Bool { kind == .verse ? normalizedNoteField(verseRef) != nil : normalizedNoteField(words) != nil }

    private enum CodingKeys: String, CodingKey {
        case id, page, order, kind, words, verseRef, attribution, decision, editedByUser, sourceKey
    }

    init(id: String, page: Int, order: Int, kind: CardKind, words: String, verseRef: String?, attribution: String?, decision: Decision, editedByUser: Bool, sourceKey: String? = nil) {
        self.id = id; self.page = page; self.order = order; self.kind = kind
        self.words = words; self.verseRef = verseRef; self.attribution = attribution
        self.decision = decision; self.editedByUser = editedByUser
        self.sourceKey = sourceKey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        page = try c.decode(Int.self, forKey: .page)
        order = try c.decode(Int.self, forKey: .order)
        kind = try c.decode(CardKind.self, forKey: .kind)
        words = try c.decode(String.self, forKey: .words)
        verseRef = try c.decodeIfPresent(String.self, forKey: .verseRef)
        attribution = try c.decodeIfPresent(String.self, forKey: .attribution)
        // Legacy review.json files without a decision default to undecided so nothing unseen is kept.
        decision = try c.decodeIfPresent(Decision.self, forKey: .decision) ?? .keep
        editedByUser = try c.decode(Bool.self, forKey: .editedByUser)
        // Preserve nil when absent on reviews saved by earlier builds: deriving from possibly-edited
        // fields would fail to reconcile against the replayed original page.
        sourceKey = try c.decodeIfPresent(String.self, forKey: .sourceKey)
    }

    static func makeSourceKey(kind: CardKind, words: String, verseRef: String?) -> String {
        if kind == .verse {
            let ref = (verseRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "verse:\(ref)"
        }
        let normalized = words
            .precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: "['’‘`]", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(kind.rawValue):\(normalized)"
    }

    /// Extracts the server generation identifier from a server-assigned `sourceKey` (`"<generationId>:<order>"`),
    /// returning nil for legacy nil keys or prior-build content-derived keys (`"key_point:..."`, `"quote:..."`, `"verse:..."`).
    static func serverGenerationId(from sourceKey: String?) -> String? {
        guard let key = normalizedNoteField(sourceKey),
              let colon = key.lastIndex(of: ":") else { return nil }
        let prefix = String(key[..<colon])
        let suffix = String(key[key.index(after: colon)...])
        guard !prefix.isEmpty, CardKind(rawValue: prefix) == nil, Int(suffix) != nil else { return nil }
        return prefix
    }
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
    /// Unread pages whose original generated draft is no longer available to replay.
    /// Existing partial cards stay untouched; the user chooses to keep what arrived rather than append a fresh generation.
    public private(set) var replayUnavailablePages: Set<Int> = []
    /// Unread pages the user explicitly chose to skip so the already-read cards can be finished.
    public private(set) var skippedPages: Set<Int> = []
    /// The note page each page of the request in flight stands for (a retry sends only some).
    private var requestPages: [Int] = []
    /// In-flight page completion state (cleared on begin / done / interrupt; not persisted).
    private var expectedCardCounts: [Int: Int] = [:]
    private var receivedCardCounts: [Int: Int] = [:]
    private var seenPagesWithoutCount: Set<Int> = []
    private var pageGenerationIds: [Int: String] = [:]
    private var rejectedGenerationPages: Set<Int> = []
    /// Each read page's transcription, in the order the pages came back. Shown while
    /// drafting instead of a placeholder (TKL-1053); not persisted.
    private struct PageTranscription: Equatable, Sendable {
        let page: Int
        let text: String
    }
    private var pageText: [PageTranscription] = []

    private enum CodingKeys: String, CodingKey {
        case noteId, pageCount, phase, cards, readPages, failedPages, replayUnavailablePages, skippedPages, requestPages, pageGenerationIds
    }

    public init(noteId: UUID, pageCount: Int) {
        self.noteId = noteId
        self.pageCount = max(pageCount, 1)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noteId = try c.decode(UUID.self, forKey: .noteId)
        pageCount = try c.decode(Int.self, forKey: .pageCount)
        phase = try c.decode(Phase.self, forKey: .phase)
        cards = try c.decode([ReviewCard].self, forKey: .cards)
        readPages = try c.decode(Set<Int>.self, forKey: .readPages)
        failedPages = try c.decode(Set<Int>.self, forKey: .failedPages)
        replayUnavailablePages = try c.decodeIfPresent(Set<Int>.self, forKey: .replayUnavailablePages) ?? []
        skippedPages = try c.decodeIfPresent(Set<Int>.self, forKey: .skippedPages) ?? []
        requestPages = try c.decode([Int].self, forKey: .requestPages)
        pageGenerationIds = try c.decodeIfPresent([Int: String].self, forKey: .pageGenerationIds) ?? [:]
    }

    public var isDrafting: Bool { phase == .drafting }
    public var progress: Double { Double(readPages.count + failedPages.count) / Double(pageCount) }
    public var unreadPages: [Int] { (0..<pageCount).filter { !readPages.contains($0) } }
    /// Unread pages that can still be retried (excludes pages whose original draft is permanently unavailable).
    public var retryablePages: [Int] { unreadPages.filter { !replayUnavailablePages.contains($0) } }
    /// Unread pages that have neither completed nor been explicitly skipped by the user.
    public var unhandledUnreadPages: [Int] { unreadPages.filter { !skippedPages.contains($0) } }
    public var canRetry: Bool { !isDrafting && phase != .notStarted && !retryablePages.isEmpty }
    /// Whether this note page already has partial cards from an earlier interrupted stream.
    public func hasPartialCards(on page: Int) -> Bool { cards.contains { $0.page == page } }
    /// The server generation id already associated with partial cards on `page`, if known.
    public func generationId(forPage page: Int) -> String? {
        pageGenerationIds[page] ?? cards.lazy.filter { $0.page == page }.compactMap { ReviewCard.serverGenerationId(from: $0.sourceKey) }.first
    }
    /// Request page indices (within `sentPages`) that already have partial cards and must only replay.
    public func replayOnlyRequestIndices(for sentPages: [Int]) -> [Int] {
        sentPages.enumerated().compactMap { index, notePage in (hasPartialCards(on: notePage) || pageGenerationIds[notePage] != nil) ? index : nil }
    }
    /// Expected server generation IDs (keyed by request page index) for partial pages in `sentPages`.
    public func expectedGenerationIds(for sentPages: [Int]) -> [Int: String] {
        var result: [Int: String] = [:]
        for (index, notePage) in sentPages.enumerated() {
            if let genId = generationId(forPage: notePage) { result[index] = genId }
        }
        return result
    }
    /// The first kept card that can't be kept as it is (a key point or quote with no words).
    public var blockingCardIndex: Int? { cards.firstIndex { $0.kept && !$0.isComplete } }
    /// What the model read on that page, once it has been read.
    public func transcription(forPage page: Int) -> String? { pageText.first { $0.page == page }?.text }
    /// The most recently read page's transcription.
    public var newestTranscription: String? { pageText.last?.text }
    /// How many pages have come back with their words.
    public var transcribedPageCount: Int { pageText.count }
    public var undecidedCount: Int { cards.filter(\.isUndecided).count }
    public var firstUndecidedIndex: Int? { cards.firstIndex(where: \.isUndecided) }
    public var keptCount: Int { cards.filter(\.kept).count }
    public var canFinish: Bool {
        !isDrafting && !cards.isEmpty && keptCount > 0 && blockingCardIndex == nil && unhandledUnreadPages.isEmpty
    }

    public func card(_ id: String) -> ReviewCard? { cards.first { $0.id == id } }

    /// Explicitly skip remaining unread pages so the cards already reviewed can be finished.
    public mutating func skipUnreadPages() {
        guard !isDrafting else { return }
        skippedPages.formUnion(unreadPages)
    }

    /// Starts a run for every retryable unread page and returns those note pages, in order.
    public mutating func begin() -> [Int] {
        requestPages = retryablePages
        failedPages.subtract(requestPages)
        skippedPages.subtract(requestPages)
        clearInFlightPageTracking()
        phase = .drafting
        return requestPages
    }

    public mutating func apply(_ event: LordsDayCardsEvent) {
        guard phase == .drafting else { return }
        switch event {
        case .started:
            break
        case .page(let requestPage, let cardCount, let extractedText, let generationId):
            guard let page = notePage(requestPage), !rejectedGenerationPages.contains(page) else { return }
            if let generationId {
                if let original = self.generationId(forPage: page), original != generationId {
                    rejectedGenerationPages.insert(page)
                    failedPages.insert(page)
                    replayUnavailablePages.insert(page)
                    return
                }
                pageGenerationIds[page] = generationId
            }
            if let extractedText, !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pageText.removeAll { $0.page == page }
                pageText.append(PageTranscription(page: page, text: extractedText))
            }
            failedPages.remove(page)
            if let cardCount {
                let expected = max(0, cardCount)
                if expected == 0 && hasPartialCards(on: page) {
                    // A genuine replay of a page that already produced cards cannot declare 0 cards.
                    rejectedGenerationPages.insert(page)
                    failedPages.insert(page)
                    replayUnavailablePages.insert(page)
                    return
                }
                expectedCardCounts[page] = expected
                if (receivedCardCounts[page] ?? 0) >= expected {
                    readPages.insert(page)
                    skippedPages.remove(page)
                }
            } else {
                // Without a declared card count, wait for `done` so a drop mid-page replays it.
                seenPagesWithoutCount.insert(page)
            }
        case .pageFailed(let page):
            if let page = notePage(page), !readPages.contains(page) { failedPages.insert(page) }
        case .pageReplayUnavailable(let page):
            if let page = notePage(page), !readPages.contains(page) {
                rejectedGenerationPages.insert(page)
                failedPages.insert(page)
                replayUnavailablePages.insert(page)
            }
        case .card(let draft):
            guard let page = notePage(draft.page), !rejectedGenerationPages.contains(page) else { return }
            // Defense in depth: if this page already has cards from a known server generation,
            // never accept cards from a different generation (prevents duplicate edited cards).
            if let existingGen = generationId(forPage: page) {
                let incomingGen = ReviewCard.serverGenerationId(from: draft.sourceKey)
                if incomingGen != existingGen {
                    rejectedGenerationPages.insert(page)
                    readPages.remove(page)
                    failedPages.insert(page)
                    replayUnavailablePages.insert(page)
                    return
                }
            }
            receivedCardCounts[page, default: 0] += 1
            if let expected = expectedCardCounts[page], receivedCardCounts[page, default: 0] >= expected {
                readPages.insert(page)
                failedPages.remove(page)
                skippedPages.remove(page)
            }
            guard let kind = CardKind(rawValue: draft.kind) else { return }
            let reference = normalizedNoteField(draft.osis) ?? normalizedNoteField(draft.reference)
            if kind == .verse && reference == nil { return }
            let words = kind == .verse ? "" : (draft.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let serverSourceKey = normalizedNoteField(draft.sourceKey)
            let fallbackSourceKey = ReviewCard.makeSourceKey(kind: kind, words: words, verseRef: kind == .verse ? reference : nil)
            let incomingSourceKey = serverSourceKey ?? fallbackSourceKey
            // Reconcile by server-assigned source identity first, then content-derived identity,
            // then legacy (sourceKey == nil) reconciliation so retries never lose edits or duplicate cards.
            if let existingIndex = existingCardIndex(
                on: page,
                order: draft.order,
                serverSourceKey: serverSourceKey,
                fallbackSourceKey: fallbackSourceKey
            ) {
                cards[existingIndex].order = draft.order
                if cards[existingIndex].sourceKey == nil || (serverSourceKey != nil && cards[existingIndex].sourceKey != serverSourceKey) {
                    cards[existingIndex].sourceKey = incomingSourceKey
                }
                cards.sort { ($0.page, $0.order, $0.id) < ($1.page, $1.order, $1.id) }
                return
            }
            let id = allocateCardId(page: page, preferredOrder: draft.order)
            cards.append(ReviewCard(
                id: id, page: page, order: draft.order, kind: kind,
                words: words,
                verseRef: kind == .verse ? reference : nil,
                attribution: kind == .quote ? normalizedNoteField(draft.attribution) : nil,
                decision: .keep, editedByUser: false, sourceKey: incomingSourceKey
            ))
            cards.sort { ($0.page, $0.order, $0.id) < ($1.page, $1.order, $1.id) }
        case .done(let failed):
            let failedSet = Set(failed.compactMap(notePage))
            for page in failedSet where !readPages.contains(page) { failedPages.insert(page) }
            for page in seenPagesWithoutCount where !failedSet.contains(page) && !rejectedGenerationPages.contains(page) {
                readPages.insert(page)
                failedPages.remove(page)
                skippedPages.remove(page)
            }
            for (page, expected) in expectedCardCounts where (receivedCardCounts[page] ?? 0) < expected && !readPages.contains(page) {
                failedPages.insert(page)
            }
            clearInFlightPageTracking()
            phase = .ready
        }
    }

    private func existingCardIndex(on page: Int, order: Int, serverSourceKey: String?, fallbackSourceKey: String) -> Int? {
        if let serverSourceKey,
           let index = cards.firstIndex(where: { $0.page == page && $0.sourceKey == serverSourceKey }) {
            return index
        }
        if let index = cards.firstIndex(where: { $0.page == page && $0.sourceKey == fallbackSourceKey }) {
            return index
        }
        // Legacy cards saved by earlier builds have sourceKey == nil.
        // 1) Unedited legacy cards match by content (handles reordered replays).
        if let index = cards.firstIndex(where: {
            $0.page == page && $0.sourceKey == nil && !$0.editedByUser &&
            ReviewCard.makeSourceKey(kind: $0.kind, words: $0.words, verseRef: $0.verseRef) == fallbackSourceKey
        }) {
            return index
        }
        // 2) Edited legacy cards (original wording was never stored) match their original slot on the replayed page.
        let legacyId = "p\(page)-\(order)"
        if let index = cards.firstIndex(where: {
            $0.page == page && $0.sourceKey == nil && $0.editedByUser && ($0.order == order || $0.id == legacyId)
        }) {
            return index
        }
        // 3) Fallback for attribution-only edited legacy cards if reordered.
        return cards.firstIndex(where: {
            $0.page == page && $0.sourceKey == nil && $0.editedByUser &&
            ReviewCard.makeSourceKey(kind: $0.kind, words: $0.words, verseRef: $0.verseRef) == fallbackSourceKey
        })
    }

    private func allocateCardId(page: Int, preferredOrder: Int) -> String {
        let preferred = "p\(page)-\(preferredOrder)"
        if card(preferred) == nil { return preferred }
        var index = 0
        while card("p\(page)-\(index)") != nil { index += 1 }
        return "p\(page)-\(index)"
    }

    /// The stream ended without `done`.
    public mutating func interrupt() {
        if phase == .drafting { phase = .interrupted }
        clearInFlightPageTracking()
    }

    private mutating func clearInFlightPageTracking() {
        expectedCardCounts = [:]
        receivedCardCounts = [:]
        seenPagesWithoutCount = []
        rejectedGenerationPages = []
    }

    private func notePage(_ requestPage: Int) -> Int? {
        requestPages.indices.contains(requestPage) ? requestPages[requestPage] : nil
    }

    // MARK: Changes the user makes

    public mutating func keep(_ id: String) { update(id) { $0.decision = .keep } }
    public mutating func remove(_ id: String) { update(id) { $0.decision = .remove } }

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

    /// Swaps one card's words for a freshly drafted replacement, keeping its id,
    /// page, order and keep/remove decision (TKL-1053). A redraft is the model's
    /// work, not the reader's, so `editedByUser` is cleared.
    public mutating func replace(_ id: String, with draft: DraftCardPayload) throws {
        guard let kind = CardKind(rawValue: draft.kind) else { throw LordsDayReviewError.noSuchCard }
        let reference = normalizedNoteField(draft.osis) ?? normalizedNoteField(draft.reference)
        if kind == .verse && reference == nil { throw LordsDayReviewError.verseNeedsReference }
        let words = kind == .verse ? "" : (draft.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if kind != .verse && words.isEmpty { throw LordsDayReviewError.versesHaveNoWords }
        try change(id) { card in
            card.kind = kind
            card.words = words
            card.verseRef = kind == .verse ? reference : nil
            card.attribution = kind == .quote ? draft.attribution : nil
            card.editedByUser = false
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

    public static func exists(noteId: UUID, root: URL = CaptureDraft.defaultRoot) -> Bool {
        FileManager.default.fileExists(atPath: url(noteId: noteId, root: root).path)
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
