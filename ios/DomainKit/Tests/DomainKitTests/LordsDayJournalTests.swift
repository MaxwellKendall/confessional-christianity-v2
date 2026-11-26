import Foundation
import SwiftData
import Testing
@testable import DomainKit

// The sermon journal (TKL-944): every kept Lord's Day by time and Scripture,
// searchable, from local storage only.

@MainActor struct LordsDayJournalTests {
    private static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private var calendar: Calendar { Self.calendar }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func entry(_ date: Date, passage: String?, title: String? = nil, transcript: String? = nil,
                       cards: [JournalCard] = [JournalCard(kind: .keyPoint, body: "A point")]) -> JournalEntry {
        JournalEntry(id: UUID(), serviceDate: date, passage: passage, title: title, preacher: nil,
                     transcript: transcript, cards: cards, calendar: calendar)
    }

    /// Three seeded Lord's Days: Romans in 2025, Revelation twice in 2026.
    private var seeded: LordsDayJournal {
        LordsDayJournal(entries: [
            entry(day(2025, 3, 2), passage: "Romans 8:28–30", title: "The Golden Chain",
                  transcript: "Called, justified, glorified. Nothing in the chain is weak.",
                  cards: [JournalCard(kind: .keyPoint, body: "God's purpose decides what is good."),
                          JournalCard(kind: .verse, body: "", reference: "Psalm 118:24")]),
            entry(day(2026, 11, 22), passage: "Revelation 2:8-11", title: "To the Church at Smyrna",
                  transcript: "Be faithful unto death. The crown of life is promised to the tested.",
                  cards: [JournalCard(kind: .quote, body: "I see Christ wrestling there."),
                          JournalCard(kind: .keyPoint, body: "Do not fear: Christ walks among his lampstands.")]),
            entry(day(2026, 1, 4), passage: "Revelation 1:9-20", title: nil, transcript: nil,
                  cards: [JournalCard(kind: .keyPoint, body: "The Son of Man among the lampstands.")]),
        ])
    }

    // MARK: entries

    @Test func entriesAreNewestFirstWithTheirPassageLocated() throws {
        let journal = seeded
        #expect(journal.entries.map(\.year) == [2026, 2026, 2025])
        let rev = journal.entries[0]
        #expect(rev.bookIndex == BIBLE_BOOKS.firstIndex { $0.osis == "Rev" })
        #expect(rev.chapter == 2)
        #expect(rev.month == 11)
        let rom = journal.entries[2]
        #expect(rom.bookIndex == BIBLE_BOOKS.firstIndex { $0.osis == "Rom" })
        #expect(rom.chapter == 8)
        #expect(rom.citedChapters == [ChapterKey(book: BIBLE_BOOKS.firstIndex { $0.osis == "Ps" }!, chapter: 118)])
    }

    @Test func aPassageThatDoesNotParseLeavesTheEntryOutOfTheCanonOnly() {
        let e = entry(day(2026, 2, 1), passage: "Advent sermon")
        #expect(e.bookIndex == nil && e.chapter == nil)
        #expect(LordsDayJournal(entries: [e]).search("advent").count == 1)
    }

    @Test func keyLinesAreThePointsThenTheQuotes() {
        let e = seeded.entries[0]
        #expect(e.keyLines == ["Do not fear: Christ walks among his lampstands.", "I see Christ wrestling there."])
    }

    // MARK: search

    @Test func searchMatchesEveryStoredField() {
        let j = seeded
        #expect(j.search("smyrna").map(\.entry.passage) == ["Revelation 2:8-11"])          // title
        #expect(j.search("revelation").count == 2)                                          // passage
        #expect(j.search("wrestling").count == 1)                                           // a kept card
        #expect(j.search("glorified").map(\.entry.title) == ["The Golden Chain"])           // transcript
        #expect(j.search("psalm 118").count == 1)                                           // a verse card's reference
        #expect(j.search("romans 8").count == 1)                                            // the passage as written
        #expect(j.search("lampstand").count == 2)                                           // part of a word
    }

    @Test func searchNeedsEveryWordIgnoringCaseAndAccents() {
        let j = seeded
        #expect(j.search("CROWN faithful").count == 1)
        #expect(j.search("crown chain").isEmpty)
        #expect(j.search("god’s purpose").count == 1)   // curly apostrophe matches the stored straight one
        #expect(j.search("  ").count == 3)              // blank query matches everything
    }

    @Test func aHitCarriesASnippetAroundTheFirstWord() throws {
        let hit = try #require(seeded.search("crown").first)
        let snippet = try #require(hit.snippet)
        #expect(snippet.match == "crown")
        #expect(snippet.before.hasSuffix("The "))
        #expect(snippet.after.hasPrefix(" of life"))
        #expect(snippet.leadingEllipsis)
    }

    @Test func aTitleOrPassageMatchHasNoSnippetBecauseTheCoverShowsIt() throws {
        #expect(try #require(seeded.search("smyrna").first).snippet == nil)
    }

    // MARK: filters

    @Test func filtersNarrowAndEachLensIgnoresItsOwn() {
        let j = seeded
        let rev = BIBLE_BOOKS.firstIndex { $0.osis == "Rev" }!
        let filter = JournalFilter(year: 2026, book: rev)
        #expect(j.search("", filter: filter).count == 2)
        // The time lens lights every year that has Revelation; Scripture every book in 2026.
        #expect(j.search("", filter: JournalFilter(year: 2025, book: rev), ignoring: .time).count == 2)
        #expect(j.search("", filter: JournalFilter(year: 2025, book: rev), ignoring: .scripture).count == 1)
        #expect(j.search("", filter: JournalFilter(year: 2026, month: 1)).count == 1)
        #expect(j.search("", filter: JournalFilter(book: rev, chapter: 2)).count == 1)
        #expect(JournalFilter().isEmpty)
        #expect(!JournalFilter(year: 2026).isEmpty)
    }

    @Test func filterLabelsReadAsChips() {
        let rev = BIBLE_BOOKS.firstIndex { $0.osis == "Rev" }!
        #expect(JournalFilter().timeLabel == "All years")
        #expect(JournalFilter(year: 2026, month: 3).timeLabel == "Mar 2026")
        #expect(JournalFilter().scriptureLabel == "All of Scripture")
        #expect(JournalFilter(book: rev).scriptureLabel == "Revelation")
        #expect(JournalFilter(book: rev, chapter: 2).scriptureLabel == "Revelation 2")
    }

    // MARK: time lens

    @Test func theYearGridHasACellPerWeekFilledWhereKeptAndMarkedWhereMatching() throws {
        let j = seeded
        let hits = Set(j.search("revelation").map(\.id))
        let rows = j.yearRows(hits: hits)
        #expect(rows.map(\.year) == [2026, 2025])
        #expect(rows.allSatisfy { $0.cells.count == 53 })
        let y2026 = rows[0]
        #expect(y2026.cells.filter { $0 == .hit }.count == 2)
        #expect(y2026.hitCount == 2)
        #expect(y2026.cells[0] == .hit)                       // 4 Jan is week 0
        #expect(y2026.cells[46] == .hit)                      // 22 Nov is week 46
        let y2025 = rows[1]
        #expect(y2025.cells.filter { $0 == .kept }.count == 1) // Romans: kept, not matching
        #expect(y2025.hitCount == 0)
    }

    @Test func monthCountsCountMatchingSundaysPerMonth() {
        let j = seeded
        let counts = j.monthCounts(year: 2026, hits: Set(j.entries.map(\.id)))
        #expect(counts.count == 12)
        #expect(counts[0] == 1 && counts[10] == 1 && counts.reduce(0, +) == 2)
    }

    // MARK: scripture lens

    @Test func chapterCountsSeparatePreachedFromCited() {
        let j = seeded
        let counts = j.chapterCounts(j.search(""))
        let rev = BIBLE_BOOKS.firstIndex { $0.osis == "Rev" }!
        let ps = BIBLE_BOOKS.firstIndex { $0.osis == "Ps" }!
        #expect(counts.preached[ChapterKey(book: rev, chapter: 2)] == 1)
        #expect(counts.preached[ChapterKey(book: rev, chapter: 1)] == 1)
        #expect(counts.cited[ChapterKey(book: ps, chapter: 118)] == 1)
        #expect(counts.preachedBooks == [BIBLE_BOOKS.firstIndex { $0.osis == "Rom" }!, rev])
    }

    // MARK: one sermon

    @Test func previousAndNextWalkTheFilteredList() {
        let list = seeded.search("revelation").map(\.entry)
        let newest = list[0], older = list[1]
        #expect(LordsDayJournal.neighbors(of: newest.id, in: list) == JournalNeighbors(earlier: older.id, later: nil))
        #expect(LordsDayJournal.neighbors(of: older.id, in: list) == JournalNeighbors(earlier: nil, later: newest.id))
    }

    // MARK: store

    @Test func theJournalHoldsOnlyLordsDaysWithKeptCards() throws {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let kept = LordsDayNote(serviceDate: day(2026, 11, 15), passageRef: "Romans 8:28–30", sermonTitle: "Chain", extractedText: "notes words")
        let draft = LordsDayNote(serviceDate: day(2026, 11, 8), passageRef: "John 3")
        let gone = LordsDayNote(serviceDate: day(2026, 11, 1), passageRef: "Acts 2", deletedAt: Date())
        for n in [kept, draft, gone] { try store.save(n) }
        try store.keepCards([KeptCard(kind: .keyPoint, body: "Kept point", verseRef: nil, attribution: nil, editedByUser: false), KeptCard(kind: .verse, body: "", verseRef: "John 3:16", attribution: nil, editedByUser: false)], for: kept)
        try store.appendCard(to: gone, kind: .keyPoint, body: "deleted")

        let journal = try LordsDayJournal(store: store, calendar: calendar)
        #expect(journal.entries.map(\.id) == [kept.id])
        let e = journal.entries[0]
        #expect(e.cards.map(\.body) == ["Kept point", ""])
        #expect(e.cards[1].reference == "John 3:16")
        #expect(e.transcript == "notes words")
        #expect(e.title == "Chain")
    }

    // MARK: fixtures and scale

    @Test func theSyntheticCorpusIsOneLordsDayPerSundayAndDeterministic() {
        let end = day(2026, 11, 22)
        let a = JournalFixture.synthetic(count: 500, endingOn: end, calendar: calendar)
        let b = JournalFixture.synthetic(count: 500, endingOn: end, calendar: calendar)
        #expect(a.count == 500)
        #expect(a.map(\.passage) == b.map(\.passage))
        #expect(a.allSatisfy { calendar.component(.weekday, from: $0.serviceDate) == 1 })
        #expect(Set(a.map { calendar.startOfDay(for: $0.serviceDate) }).count == 500)
        #expect(a.allSatisfy { $0.bookIndex != nil && !$0.cards.isEmpty })
        #expect(JournalFixture.synthetic(count: 1, endingOn: end, calendar: calendar).count == 1)
    }

    @Test func fiveHundredLordsDaysSearchAndGridQuickly() {
        let journal = LordsDayJournal(entries: JournalFixture.synthetic(count: 500, endingOn: day(2026, 11, 22), calendar: calendar))
        let start = Date()
        let hits = journal.search("grace")
        _ = journal.yearRows(hits: Set(hits.map(\.id)))
        _ = journal.chapterCounts(hits)
        _ = journal.search("", filter: JournalFilter(year: 2024))
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(!hits.isEmpty)
    }
}
