import Foundation
import SwiftData
import XCTest
@testable import DomainKit

@MainActor final class LordsDayFeedTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func makeStore() throws -> LordsDayStore {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        return LordsDayStore(context: ModelContext(container))
    }

    /// 15 Nov 2026 is a Sunday.
    private func week(_ store: LordsDayStore, kinds: [CardKind]) throws -> (LordsDayNote, [NoteCard]) {
        let note = LordsDayNote(serviceDate: day(2026, 11, 15), passageRef: "Romans 8:28–30", preacher: "Rev. Smith")
        try store.save(note)
        for (i, kind) in kinds.enumerated() {
            if kind == .verse {
                try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Romans 8:\(28 + i)")
            } else {
                try store.appendCard(to: note, kind: kind, body: "card \(i)")
            }
        }
        return (note, try store.cards(for: note))
    }

    func testOpensAtTodaysCardWithDayLabels() throws {
        let store = try makeStore()
        let (note, cards) = try week(store, kinds: [.verse, .keyPoint, .quote, .verse, .quote, .keyPoint])
        // Thursday 19 Nov → the fourth card (Monday is the first).
        let feed = LordsDayFeed(note: note, cards: cards, today: day(2026, 11, 19), calendar: calendar)
        XCTAssertEqual(feed.cards.count, 6)
        XCTAssertEqual(feed.todayIndex, 3)
        XCTAssertEqual(feed.cards.map(\.dayLabel), ["Monday", "Tuesday", "Wednesday", "Today · Thursday", "Friday", "Saturday"])
        XCTAssertEqual(feed.cards.map(\.isToday), [false, false, false, true, false, false])
        XCTAssertEqual(feed.cards.map(\.id), cards.map(\.id))
    }

    func testTodayClampsAndOutsideTheWeekOpensAtTheFirstCard() throws {
        let store = try makeStore()
        let (note, cards) = try week(store, kinds: [.keyPoint, .quote])
        let saturday = LordsDayFeed(note: note, cards: cards, today: day(2026, 11, 21), calendar: calendar)
        XCTAssertEqual(saturday.todayIndex, 1)
        // The card that stands in for today is labelled "Today", not with the wrong weekday.
        XCTAssertEqual(saturday.cards.map(\.dayLabel), ["Monday", "Today"])
        let later = LordsDayFeed(note: note, cards: cards, today: day(2026, 11, 30), calendar: calendar)
        XCTAssertEqual(later.todayIndex, 0)
        XCTAssertFalse(later.cards.contains(where: \.isToday))
        let empty = LordsDayFeed(note: note, cards: [], today: day(2026, 11, 19), calendar: calendar)
        XCTAssertNil(empty.todayIndex)
    }

    func testCardsBeyondSaturdayHaveNoDay() throws {
        let store = try makeStore()
        let (note, cards) = try week(store, kinds: Array(repeating: .keyPoint, count: 8))
        let feed = LordsDayFeed(note: note, cards: cards, today: day(2026, 11, 16), calendar: calendar)
        XCTAssertEqual(feed.cards.suffix(2).map(\.dayLabel), [nil, nil])
    }

    func testPalettesRotateHonourAStoredPaletteAndSwapForDark() throws {
        let store = try makeStore()
        let (note, cards) = try week(store, kinds: Array(repeating: .keyPoint, count: 7))
        cards[1].palette = "cloister"
        cards[2].palette = "not-a-palette"
        let feed = LordsDayFeed(note: note, cards: cards, today: day(2026, 11, 16), calendar: calendar)
        let names = feed.cards.map(\.palette.name)
        XCTAssertEqual(names, ["psalter", "cloister", "hymnal", "ironstone", "vespers", "cloister", "psalter"])
        XCTAssertEqual(Set(LordsDayFeed.rotation.map(\.name)), ["vellum", "psalter", "hymnal", "vespers", "ironstone", "cloister"])
        XCTAssertEqual(LordsDayFeed.palette(.vellum, dark: true), .vespers)
        XCTAssertEqual(LordsDayFeed.palette(.cloister, dark: true), .hymnal)
        XCTAssertEqual(LordsDayFeed.palette(.ironstone, dark: true), .psalter)
        XCTAssertEqual(LordsDayFeed.palette(.psalter, dark: true), .psalter)
        XCTAssertEqual(LordsDayFeed.palette(.vellum, dark: false), .vellum)
    }

    func testKindLabels() {
        XCTAssertEqual(CardKind.keyPoint.label, "Key point")
        XCTAssertEqual(CardKind.quote.label, "Quote")
        XCTAssertEqual(CardKind.verse.label, "Verse")
    }

    func testVerseCardsResolveTheirReferenceToOsis() throws {
        let store = try makeStore()
        let note = LordsDayNote(serviceDate: day(2026, 11, 15))
        try store.save(note)
        try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Romans 8:28")
        try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Rom.8.30")
        try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Psalm 118:24")
        try store.appendCard(to: note, kind: .verse, body: "", verseRef: "the bit about the chain")
        let feed = LordsDayFeed(note: note, cards: try store.cards(for: note), today: day(2026, 11, 16), calendar: calendar)
        XCTAssertEqual(feed.cards.map(\.verseOsis), ["Rom.8.28", "Rom.8.30", "Ps.118.24", nil])
        XCTAssertEqual(feed.cards.map(\.reference), ["Romans 8:28", "Romans 8:30", "Psalm 118:24", "the bit about the chain"])
    }

    func testShareTextCarriesTheTextAndReference() throws {
        let store = try makeStore()
        let note = LordsDayNote(serviceDate: day(2026, 11, 15), passageRef: "Romans 8:28–30", preacher: "Rev. Smith")
        try store.save(note)
        try store.appendCard(to: note, kind: .keyPoint, body: "God's purpose decides what is good.")
        let quote = try store.appendCard(to: note, kind: .quote, body: "The golden chain has no weak link.")
        quote.attribution = "Rev. Jones"
        try store.appendCard(to: note, kind: .quote, body: "Unattributed.")
        try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Romans 8:28")
        let feed = LordsDayFeed(note: note, cards: try store.cards(for: note), today: day(2026, 11, 16), calendar: calendar)
        XCTAssertEqual(feed.cards[0].shareText(), "God's purpose decides what is good.\n\nFrom notes on Romans 8:28–30")
        XCTAssertEqual(feed.cards[1].shareText(), "“The golden chain has no weak link.”\n\n— Rev. Jones · Romans 8:28–30")
        XCTAssertEqual(feed.cards[2].shareText(), "“Unattributed.”\n\n— Rev. Smith · Romans 8:28–30")
        XCTAssertEqual(feed.cards[3].shareText(verseText: "And we know that for those who love God…"), "And we know that for those who love God…\n\n— Romans 8:28 (ESV)")
        XCTAssertEqual(feed.cards[3].shareText(), "Romans 8:28")
    }

    func testAttributionLine() throws {
        let store = try makeStore()
        let bare = LordsDayNote(serviceDate: day(2026, 11, 15))
        try store.save(bare)
        try store.appendCard(to: bare, kind: .keyPoint, body: "p")
        try store.appendCard(to: bare, kind: .quote, body: "q")
        let feed = LordsDayFeed(note: bare, cards: try store.cards(for: bare), today: day(2026, 11, 16), calendar: calendar)
        XCTAssertEqual(feed.cards[0].attributionLine, "From your notes")
        XCTAssertNil(feed.cards[1].attributionLine)
        XCTAssertEqual(feed.cards[1].shareText(), "“q”")
    }
}

final class VerseLeadTests: XCTestCase {
    func testLeadIsTheOpeningWordsUpToAComma() {
        XCTAssertEqual(verseLead("And we know that for those who love God all things work together for good"), .init(lead: "And we know", rest: "that for those who love God all things work together for good"))
        XCTAssertEqual(verseLead("“For God so loved the world, that he gave his only Son”"), .init(lead: "“For God so", rest: "loved the world, that he gave his only Son”"))
        XCTAssertEqual(verseLead("Moreover, whom he predestined he also called"), .init(lead: "Moreover,", rest: "whom he predestined he also called"))
        XCTAssertEqual(verseLead("Jesus wept."), .init(lead: "", rest: "Jesus wept."))
        XCTAssertEqual(verseLead("  "), .init(lead: "", rest: ""))
    }
}
