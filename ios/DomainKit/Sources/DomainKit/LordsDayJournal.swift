import Foundation

// The sermon journal (TKL-944, design TKL-951 revision 2): every kept Lord's
// Day, traversed by time and Scripture, searchable, down to one sermon. Pure
// values built from the local store, so the journal works offline and needs
// no model call. The Topic lens, fair copy and Insights are TKL-1058.

/// A chapter of the canon: `book` indexes `BIBLE_BOOKS`.
public struct ChapterKey: Hashable, Sendable {
    public let book: Int
    public let chapter: Int
    public init(book: Int, chapter: Int) { self.book = book; self.chapter = chapter }
}

public struct JournalCard: Equatable, Sendable {
    public let kind: CardKind
    /// The words for key points and quotes; empty for verses.
    public let body: String
    /// A verse card's reference as stored.
    public let reference: String?
    public let attribution: String?
    /// The stored palette name, or nil for the feed's rotation.
    public let paletteName: String?

    public init(kind: CardKind, body: String, reference: String? = nil, attribution: String? = nil, paletteName: String? = nil) {
        self.kind = kind; self.body = body; self.reference = reference
        self.attribution = attribution; self.paletteName = paletteName
    }

    /// The light-mode palette the feed gave this card at `index`.
    public func palette(at index: Int) -> QuoteCardPalette {
        paletteName.flatMap(QuoteCardPalette.named) ?? LordsDayFeed.rotation[index % LordsDayFeed.rotation.count]
    }

    /// What a card shows: its words, or a verse's reference.
    public var text: String { kind == .verse ? (reference ?? "") : body }

    /// A verse card's OSIS id, when its reference parses.
    public var verseOsis: String? { kind == .verse ? reference.flatMap(LordsDayFeed.osis(for:)) : nil }

    /// A verse card's bundled ESV text, readable offline; nil when it isn't bundled.
    public var bundledVerseText: String? { verseOsis.flatMap(bundledEsvText(for:)) }
}

public struct JournalEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let serviceDate: Date
    public let passage: String?
    public let title: String?
    public let preacher: String?
    public let transcript: String?
    public let cards: [JournalCard]
    public let year: Int
    /// 1 to 12.
    public let month: Int
    /// The Sunday's column in the year grid, 0 to 52.
    public let weekOfYear: Int
    /// Where the sermon's passage falls in `BIBLE_BOOKS`, when it parses.
    public let bookIndex: Int?
    public let chapter: Int?
    /// Chapters the week's verse cards cite.
    public let citedChapters: [ChapterKey]
    /// Every stored word, folded for matching.
    let searchText: String

    public init(id: UUID, serviceDate: Date, passage: String?, title: String?, preacher: String?, transcript: String?,
                cards: [JournalCard], calendar: Calendar = .current) {
        self.id = id
        self.serviceDate = serviceDate
        self.passage = normalizedNoteField(passage)
        self.title = normalizedNoteField(title)
        self.preacher = normalizedNoteField(preacher)
        self.transcript = normalizedNoteField(transcript)
        self.cards = cards
        let parts = calendar.dateComponents([.year, .month], from: serviceDate)
        year = parts.year ?? 0
        month = parts.month ?? 1
        let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? serviceDate
        let days = calendar.dateComponents([.day], from: jan1, to: calendar.startOfDay(for: serviceDate)).day ?? 0
        weekOfYear = min(max(days / 7, 0), 52)
        let located = self.passage.flatMap(Self.locate)
        bookIndex = located?.book
        chapter = located?.chapter
        var cited: [ChapterKey] = []
        for card in cards where card.kind == .verse {
            if let key = card.reference.flatMap(Self.locate), !cited.contains(key) { cited.append(key) }
        }
        citedChapters = cited
        let readablePassage = self.passage.flatMap(LordsDayFeed.osis(for:)).map(parseOsisBibleReference)
        let words: [String?] = [self.passage, readablePassage, self.title, self.preacher, self.transcript]
            + cards.flatMap { [$0.body, $0.reference, $0.attribution] }
        searchText = words.compactMap { $0 }.map(journalFold).joined(separator: "\n")
    }

    /// The summary face's lines: the kept key points, then the quotes.
    public var keyLines: [String] {
        let points = cards.filter { $0.kind == .keyPoint }.compactMap { normalizedNoteField($0.body) }
        let quotes = cards.filter { $0.kind == .quote }.compactMap { normalizedNoteField($0.body) }
        return points + quotes
    }

    /// The first verse card, for the summary's quoted line.
    public var keyVerse: JournalCard? { cards.first { $0.kind == .verse && normalizedNoteField($0.reference) != nil } }

    /// Every reference the week touched: the passage, then the verse cards'.
    public var references: [String] {
        var refs: [String] = passage.map { [$0] } ?? []
        for card in cards where card.kind == .verse {
            if let ref = normalizedNoteField(card.reference), !refs.contains(ref) { refs.append(ref) }
        }
        return refs
    }

    /// Book and chapter of a reference, OSIS or as written.
    static func locate(_ reference: String) -> ChapterKey? {
        guard let osis = LordsDayFeed.osis(for: reference) else { return nil }
        let bits = osis.split(separator: "-").first?.split(separator: ".") ?? []
        guard bits.count >= 2, let book = BIBLE_BOOKS.firstIndex(where: { $0.osis == bits[0] }),
              let chapter = Int(bits[1]) else { return nil }
        return ChapterKey(book: book, chapter: chapter)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.serviceDate == b.serviceDate && a.passage == b.passage && a.title == b.title
            && a.transcript == b.transcript && a.cards == b.cards
    }
}

public struct JournalFilter: Equatable, Hashable, Sendable {
    public var year: Int?
    /// 1 to 12; only with a year.
    public var month: Int?
    /// An index into `BIBLE_BOOKS`.
    public var book: Int?
    /// Only with a book.
    public var chapter: Int?

    public init(year: Int? = nil, month: Int? = nil, book: Int? = nil, chapter: Int? = nil) {
        self.year = year; self.month = month; self.book = book; self.chapter = chapter
    }

    public static let monthNames = journalMonths

    public var isEmpty: Bool { year == nil && month == nil && book == nil && chapter == nil }
    public var hasTime: Bool { year != nil }
    public var hasScripture: Bool { book != nil }

    public var timeLabel: String {
        guard let year else { return "All years" }
        return month.map { "\(journalMonths[$0 - 1].prefix(3)) \(year)" } ?? "\(year)"
    }

    public var scriptureLabel: String {
        guard let book, BIBLE_BOOKS.indices.contains(book) else { return "All of Scripture" }
        return BIBLE_BOOKS[book].name + (chapter.map { " \($0)" } ?? "")
    }

    func admits(_ entry: JournalEntry, ignoring lens: JournalLens?) -> Bool {
        if lens != .time {
            if let year, entry.year != year { return false }
            if let month, entry.month != month { return false }
        }
        if lens != .scripture {
            if let book, entry.bookIndex != book { return false }
            if let chapter, entry.chapter != chapter { return false }
        }
        return true
    }
}

public enum JournalLens: String, CaseIterable, Sendable {
    case time, scripture
    public var label: String { self == .time ? "Time" : "Scripture" }
}

/// The words around a search hit in a kept card or the notes transcript.
public struct JournalSnippet: Equatable, Sendable {
    public let before: String
    public let match: String
    public let after: String
    public let leadingEllipsis: Bool
    public let trailingEllipsis: Bool
}

public struct JournalHit: Identifiable, Equatable, Sendable {
    public let entry: JournalEntry
    public let snippet: JournalSnippet?
    public var id: UUID { entry.id }
}

public enum JournalCell: Equatable, Sendable {
    /// No Lord's Day kept that week.
    case none
    /// Kept, but not matching the search or filter.
    case kept
    /// Kept and matching.
    case hit
}

public struct JournalYearRow: Identifiable, Equatable, Sendable {
    public let year: Int
    public let cells: [JournalCell]
    public let hitCount: Int
    public var id: Int { year }
}

public struct JournalChapterCounts: Equatable, Sendable {
    /// Sermons preached on each chapter.
    public let preached: [ChapterKey: Int]
    /// Verse cards citing each chapter.
    public let cited: [ChapterKey: Int]
    public init(preached: [ChapterKey: Int], cited: [ChapterKey: Int]) { self.preached = preached; self.cited = cited }
    /// Books with a sermon preached from them, in canonical order.
    public var preachedBooks: [Int] { Set(preached.keys.map(\.book)).sorted() }
}

public struct JournalNeighbors: Equatable, Sendable {
    public let earlier: UUID?
    public let later: UUID?
}

public struct LordsDayJournal: Equatable, Sendable {
    /// Newest first.
    public let entries: [JournalEntry]

    public init(entries: [JournalEntry]) {
        self.entries = entries.sorted { $0.serviceDate > $1.serviceDate }
    }

    /// Every Lord's Day with kept cards, read in two fetches.
    @MainActor public init(store: LordsDayStore, calendar: Calendar = .current) throws {
        let cardsByNote = try store.allKeptCards()
        let entries = try store.allNotes().compactMap { note -> JournalEntry? in
            guard let cards = cardsByNote[note.id], !cards.isEmpty else { return nil }
            return JournalEntry(
                id: note.id, serviceDate: note.serviceDate, passage: note.passageRef, title: note.sermonTitle,
                preacher: note.preacher, transcript: note.extractedText,
                cards: cards.map { JournalCard(kind: $0.kind, body: $0.body, reference: $0.verseRef, attribution: $0.attribution, paletteName: $0.palette) },
                calendar: calendar
            )
        }
        self.init(entries: entries)
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var cardCount: Int { entries.reduce(0) { $0 + $1.cards.count } }

    /// Lord's Days matching every word of `query` and the filter, newest first.
    /// A lens passed as `ignoring` keeps its own filter out, so it can show what
    /// the other filters and the search leave across all of it.
    public func search(_ query: String, filter: JournalFilter = JournalFilter(), ignoring lens: JournalLens? = nil) -> [JournalHit] {
        let words = Self.words(query)
        return entries.compactMap { entry in
            guard filter.admits(entry, ignoring: lens), words.allSatisfy(entry.searchText.contains) else { return nil }
            return JournalHit(entry: entry, snippet: words.isEmpty ? nil : Self.snippet(in: entry, words: words))
        }
    }

    public var years: [Int] { Array(Set(entries.map(\.year))).sorted(by: >) }

    /// One row per year with kept Lord's Days, newest first, a cell per week.
    public func yearRows(hits: Set<UUID>) -> [JournalYearRow] {
        var byYear: [Int: [JournalCell]] = [:]
        var counts: [Int: Int] = [:]
        for entry in entries {
            var cells = byYear[entry.year] ?? Array(repeating: .none, count: 53)
            let hit = hits.contains(entry.id)
            if hit || cells[entry.weekOfYear] == .none { cells[entry.weekOfYear] = hit ? .hit : .kept }
            if hit { counts[entry.year, default: 0] += 1 }
            byYear[entry.year] = cells
        }
        return byYear.keys.sorted(by: >).map { JournalYearRow(year: $0, cells: byYear[$0]!, hitCount: counts[$0] ?? 0) }
    }

    /// Matching Lord's Days in each month of `year`, January first.
    public func monthCounts(year: Int, hits: Set<UUID>) -> [Int] {
        var counts = Array(repeating: 0, count: 12)
        for entry in entries where entry.year == year && hits.contains(entry.id) { counts[entry.month - 1] += 1 }
        return counts
    }

    public func chapterCounts(_ hits: [JournalHit]) -> JournalChapterCounts {
        var preached: [ChapterKey: Int] = [:]
        var cited: [ChapterKey: Int] = [:]
        for hit in hits {
            if let book = hit.entry.bookIndex, let chapter = hit.entry.chapter {
                preached[ChapterKey(book: book, chapter: chapter), default: 0] += 1
            }
            for key in hit.entry.citedChapters { cited[key, default: 0] += 1 }
        }
        return JournalChapterCounts(preached: preached, cited: cited)
    }

    public func entry(id: UUID) -> JournalEntry? { entries.first { $0.id == id } }

    /// The Lord's Days either side of `id` in a newest-first list.
    public static func neighbors(of id: UUID, in list: [JournalEntry]) -> JournalNeighbors {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return JournalNeighbors(earlier: nil, later: nil) }
        return JournalNeighbors(earlier: i + 1 < list.count ? list[i + 1].id : nil, later: i > 0 ? list[i - 1].id : nil)
    }

    static func words(_ query: String) -> [String] {
        journalFold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// From the kept cards first, then the notes transcript; the cover already
    /// shows the title and passage, so a match there needs no snippet.
    static func snippet(in entry: JournalEntry, words: [String]) -> JournalSnippet? {
        let sources = entry.cards.filter { $0.kind != .verse }.map(\.body) + [entry.transcript].compactMap { $0 }
        for word in words {
            for source in sources {
                let text = source.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
                guard let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                var start = text.index(range.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
                if start > text.startIndex, let space = text[start..<range.lowerBound].firstIndex(where: \.isWhitespace) {
                    start = text.index(after: space)
                }
                var end = text.index(range.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
                if end < text.endIndex, let space = text[range.upperBound..<end].lastIndex(where: \.isWhitespace) {
                    end = space
                }
                return JournalSnippet(before: String(text[start..<range.lowerBound]), match: String(text[range]),
                                      after: String(text[range.upperBound..<end]),
                                      leadingEllipsis: start > text.startIndex, trailingEllipsis: end < text.endIndex)
            }
        }
        return nil
    }
}

let journalMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

/// Case, accents and curly quotes don't matter when matching.
func journalFold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .replacingOccurrences(of: "\u{2019}", with: "'")
        .replacingOccurrences(of: "\u{2018}", with: "'")
}

extension LordsDayStore {
    /// Kept cards of every live note, by note, in order.
    func allKeptCards() throws -> [UUID: [NoteCard]] {
        try Dictionary(grouping: allCards().filter { $0.deletedAt == nil }, by: \.noteId)
            .mapValues { $0.sorted { $0.position < $1.position } }
    }
}
