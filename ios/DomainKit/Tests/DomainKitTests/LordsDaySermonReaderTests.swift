import Foundation
import SwiftData
import XCTest
@testable import DomainKit

/// TKL-879: the week feed opens the verse-by-verse reader on the sermon text.
@MainActor final class LordsDaySermonReaderTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    /// 15 Nov 2026 is a Sunday. Cards: (kind, body or verse reference).
    private func feed(passage: String? = "Romans 8:28–30", cards: [(CardKind, String)], today: Date) throws -> LordsDayFeed {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let note = LordsDayNote(serviceDate: day(2026, 11, 15), passageRef: passage, preacher: "Rev. Smith")
        try store.save(note)
        for (kind, text) in cards {
            if kind == .verse {
                try store.appendCard(to: note, kind: .verse, body: "", verseRef: text)
            } else {
                try store.appendCard(to: note, kind: kind, body: text)
            }
        }
        return LordsDayFeed(note: note, cards: try store.cards(for: note), today: today, calendar: calendar)
    }

    func testVerseCardOpensTheReaderForItsReferenceOnWednesday() throws {
        let week = try feed(cards: [(.quote, "q"), (.keyPoint, "Every link in the chain is God’s."), (.verse, "Romans 8:28")], today: day(2026, 11, 18))
        let verse = try XCTUnwrap(week.cards.first { $0.kind == .verse })
        XCTAssertEqual(week.readerSource(for: verse), .sermonText(
            passageOsis: "Rom.8.28", weekday: "Wednesday", dayIndex: 3, daysInWeek: 6,
            notesKeyPoint: "Every link in the chain is God’s."
        ))
    }

    func testSermonTextSourceUsesTheWeeksPassage() throws {
        let week = try feed(cards: [(.keyPoint, "  First point  "), (.keyPoint, "Second point")], today: day(2026, 11, 20))
        XCTAssertEqual(week.sermonTextSource, .sermonText(
            passageOsis: "Rom.8.28-Rom.8.30", weekday: "Friday", dayIndex: 5, daysInWeek: 6,
            notesKeyPoint: "First point"
        ))
    }

    func testNoKeyPointMeansNoNotesCard() throws {
        let week = try feed(cards: [(.quote, "q"), (.verse, "John 3:16")], today: day(2026, 11, 16))
        let source = try XCTUnwrap(week.sermonTextSource)
        XCTAssertEqual(source, .sermonText(passageOsis: "Rom.8.28-Rom.8.30", weekday: "Monday", dayIndex: 1, daysInWeek: 6, notesKeyPoint: nil))
        let verses = [ReaderVerse(osis: "Rom.8.28", verse: 28, text: "a")]
        XCTAssertEqual(readerCards(for: source, verses: verses), [.intro, .verse(verses[0]), .end])
    }

    func testDayIndexIgnoresHowManyCardsTheWeekHas() throws {
        // Saturday with two cards is still day 6 of 6, not day 2.
        let week = try feed(cards: [(.verse, "John 3:16"), (.quote, "q")], today: day(2026, 11, 21))
        guard case let .sermonText(_, weekday, dayIndex, daysInWeek, _)? = week.sermonTextSource else { return XCTFail() }
        XCTAssertEqual([weekday], ["Saturday"])
        XCTAssertEqual([dayIndex, daysInWeek], [6, 6])
    }

    func testSundayIsTheFirstDay() throws {
        let week = try feed(cards: [(.verse, "John 3:16")], today: day(2026, 11, 15, hour: 20))
        guard case let .sermonText(_, weekday, dayIndex, _, _)? = week.sermonTextSource else { return XCTFail() }
        XCTAssertEqual(weekday, "Sunday")
        XCTAssertEqual(dayIndex, 1)
    }

    func testNothingToOpenWithoutAReadableReference() throws {
        let week = try feed(passage: "the sermon on the mount", cards: [(.verse, "not a verse"), (.quote, "q")], today: day(2026, 11, 18))
        XCTAssertNil(week.sermonTextSource)
        XCTAssertNil(week.readerSource(for: week.cards[0]))
        XCTAssertNil(week.readerSource(for: week.cards[1]), "only verse cards open the reader")
        XCTAssertNil(try feed(passage: nil, cards: [(.quote, "q")], today: day(2026, 11, 18)).sermonTextSource)
    }
}

/// The notes card wraps a key point in quotes once, even when the note already has them.
final class ReaderNoteQuotingTests: XCTestCase {
    func testPlainNoteIsWrapped() {
        XCTAssertEqual(readerQuoted("God forged every link."), "“God forged every link.”")
    }

    func testNoteThatAlreadyStartsWithAQuoteIsNotDoubled() {
        XCTAssertEqual(readerQuoted("“Glorified” is in the past tense."), "“Glorified” is in the past tense.")
        XCTAssertEqual(readerQuoted("\"Glorified\" is past tense."), "\"Glorified\" is past tense.")
    }
}
