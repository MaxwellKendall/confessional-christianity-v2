import Foundation
import SwiftData
import XCTest
@testable import DomainKit

@MainActor final class LordsDayTests: XCTestCase {
    func testStoreAndVerseValidation() throws {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let note = LordsDayNote(serviceDate: date)
        try store.save(note)
        let first = try store.appendCard(to: note, kind: .keyPoint, body: "point")
        let second = try store.appendCard(to: note, kind: .quote, body: "quote")
        XCTAssertThrowsError(try store.appendCard(to: note, kind: .verse, body: "generated", verseRef: "John 1:1"))
        let verse = try store.appendCard(to: note, kind: .verse, body: "", verseRef: "John 1:1")
        XCTAssertThrowsError(try store.editBody(of: verse, body: "generated"))
        try store.reorderCards(for: note, cards: [second, first, verse])
        try store.editBody(of: first, body: "edited")
        try store.switchKind(of: second, to: .verse, verseRef: "John 3:16")
        XCTAssertEqual(second.body, "")
        try store.removeCard(first)
        XCTAssertNotNil(first.deletedAt)
        XCTAssertEqual(try store.cards(for: note).map(\.id), [second.id, verse.id])
        XCTAssertEqual(try store.currentWeek(on: date)?.id, note.id)
        XCTAssertEqual(try store.archive(before: date.addingTimeInterval(8 * 86400)).map(\.id), [note.id])
    }

    func testTodayCardBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: sunday)! }
        XCTAssertNil(todayCardIndex(serviceDate: sunday, today: day(0), cardCount: 0, calendar: calendar))
        XCTAssertEqual(todayCardIndex(serviceDate: sunday, today: day(0), cardCount: 2, calendar: calendar), 0)
        XCTAssertEqual(todayCardIndex(serviceDate: sunday, today: day(1), cardCount: 2, calendar: calendar), 0)
        XCTAssertEqual(todayCardIndex(serviceDate: sunday, today: day(6), cardCount: 2, calendar: calendar), 1)
        XCTAssertNil(todayCardIndex(serviceDate: sunday, today: day(7), cardCount: 2, calendar: calendar))
        XCTAssertNil(todayCardIndex(serviceDate: sunday, today: day(-1), cardCount: 2, calendar: calendar))
    }
}
