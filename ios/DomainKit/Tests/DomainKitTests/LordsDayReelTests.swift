import Foundation
import SwiftData
import XCTest
@testable import DomainKit

/// The Lord's Day landing page and its reel (TKL-1063, design TKL-1062).
@MainActor final class LordsDayReelTests: XCTestCase {
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

    @discardableResult
    private func sermon(_ store: LordsDayStore, _ date: Date, title: String?, passage: String? = "Revelation 2:8-11",
                        preacher: String? = "Rev. Smith", cards: Int) throws -> LordsDayNote {
        let note = LordsDayNote(serviceDate: date, passageRef: passage, sermonTitle: title, preacher: preacher)
        try store.save(note)
        for i in 0..<cards { try store.appendCard(to: note, kind: .keyPoint, body: "\(title ?? "untitled") \(i)") }
        return note
    }

    // MARK: building

    func testSermonsAreNewestFirstAndSkipNotesWithoutKeptCards() throws {
        let store = try makeStore()
        try sermon(store, day(2026, 11, 8), title: "The Golden Chain", cards: 4)
        try sermon(store, day(2026, 11, 22), title: "To the Church at Smyrna", cards: 6)
        try sermon(store, day(2026, 11, 15), title: "Not kept yet", cards: 0)
        try sermon(store, day(2026, 11, 1), title: "Kept by His Power", cards: 3)
        let reel = try LordsDayReel(store: store, calendar: calendar)
        XCTAssertEqual(reel.sermons.map(\.title), ["To the Church at Smyrna", "The Golden Chain", "Kept by His Power"])
        // A cover, then its cards.
        XCTAssertEqual(reel.sermons.map(\.pageCount), [7, 5, 4])
        XCTAssertEqual(reel.pageCount, 16)
        // The cover has its own colour and each card keeps its own.
        let smyrna = reel.sermons[0]
        XCTAssertEqual(smyrna.palette(atPage: 0), smyrna.coverPalette)
        XCTAssertEqual(smyrna.palette(atPage: 3), smyrna.cards[2].palette)
        XCTAssertNotEqual(smyrna.palette(atPage: 1), smyrna.coverPalette)
    }

    func testBindingNamesTheSermonAndFallsBackToPassageThenDate() throws {
        let store = try makeStore()
        try sermon(store, day(2026, 11, 22), title: "To the Church at Smyrna", cards: 1)
        try sermon(store, day(2026, 11, 15), title: nil, passage: "John 1:14-18", preacher: nil, cards: 1)
        try sermon(store, day(2026, 11, 8), title: nil, passage: nil, preacher: nil, cards: 1)
        let reel = try LordsDayReel(store: store, calendar: calendar)
        XCTAssertEqual(reel.sermons[0].title, "To the Church at Smyrna")
        XCTAssertEqual(reel.sermons[0].meta, "Revelation 2:8-11 · Rev. Smith")
        XCTAssertEqual(reel.sermons[1].title, "John 1:14-18")
        XCTAssertNil(reel.sermons[1].meta)
        XCTAssertEqual(reel.sermons[2].title, "Sunday, November 8")
        XCTAssertEqual(reel.sermons[0].shortDate, "Nov 22")
        XCTAssertEqual(reel.sermons[0].dateCaps, "NOV 22")
    }

    func testAnOlderYearCarriesItsYearInTheShortDate() throws {
        let store = try makeStore()
        try sermon(store, day(2025, 11, 23), title: "The Means of Grace", cards: 1)
        let reel = try LordsDayReel(store: store, today: day(2026, 11, 26), calendar: calendar)
        XCTAssertEqual(reel.sermons[0].shortDate, "Nov 23, 2025")
    }

    // MARK: positions

    func testFlatIndexAndPositionRoundTrip() throws {
        let reel = LordsDayReel(testSermonPageCounts: [7, 5, 4])
        XCTAssertEqual(reel.flatIndex(of: ReelPosition(sermon: 0, page: 0)), 0)
        XCTAssertEqual(reel.flatIndex(of: ReelPosition(sermon: 1, page: 0)), 7)
        XCTAssertEqual(reel.flatIndex(of: ReelPosition(sermon: 2, page: 3)), 15)
        for flat in 0..<reel.pageCount {
            XCTAssertEqual(reel.flatIndex(of: reel.position(at: flat)), flat)
        }
        XCTAssertEqual(reel.position(at: 6), ReelPosition(sermon: 0, page: 6))
        XCTAssertEqual(reel.position(at: 7), ReelPosition(sermon: 1, page: 0))
        // Out of range clamps.
        XCTAssertEqual(reel.position(at: 99), ReelPosition(sermon: 2, page: 3))
        XCTAssertEqual(reel.position(at: -3), ReelPosition(sermon: 0, page: 0))
        XCTAssertEqual(reel.flatIndex(of: ReelPosition(sermon: 1, page: 40)), 11)
    }

    func testCountLabelsAndTopBar() throws {
        let store = try makeStore()
        try sermon(store, day(2026, 11, 22), title: "To the Church at Smyrna", cards: 6)
        let reel = try LordsDayReel(store: store, calendar: calendar)
        XCTAssertEqual(reel.countLabel(ReelPosition(sermon: 0, page: 0)), "7 cards")
        XCTAssertEqual(reel.countLabel(ReelPosition(sermon: 0, page: 4)), "5 of 7")
        XCTAssertEqual(reel.topBarSubtitle(ReelPosition(sermon: 0, page: 4)), "NOV 22 · 5 OF 7")
    }

    // MARK: the dot rail

    func testRailShowsTheCurrentSermonsDotsWithNeighbourMarks() {
        let reel = LordsDayReel(testSermonPageCounts: [7, 5, 4])
        let first = reel.rail(at: ReelPosition(sermon: 0, page: 2))
        XCTAssertEqual(first, ReelRail(dots: 7, current: 2, hasPrevious: false, hasNext: true))
        let middle = reel.rail(at: ReelPosition(sermon: 1, page: 0))
        XCTAssertEqual(middle, ReelRail(dots: 5, current: 0, hasPrevious: true, hasNext: true))
        let last = reel.rail(at: ReelPosition(sermon: 2, page: 3))
        XCTAssertEqual(last, ReelRail(dots: 4, current: 3, hasPrevious: true, hasNext: false))
        // More sermons still to load count as a next one.
        let more = LordsDayReel(testSermonPageCounts: [7, 5, 4], hasMore: true)
        XCTAssertTrue(more.rail(at: ReelPosition(sermon: 2, page: 0)).hasNext)
    }

    func testScrubMovesOneCardPerDotSpacingAcrossSermonsAndClamps() {
        XCTAssertEqual(ReelScrub.target(from: 4, dragOffset: 0, pageCount: 16), 4)
        XCTAssertEqual(ReelScrub.target(from: 4, dragOffset: ReelScrub.spacing * 3, pageCount: 16), 7)
        XCTAssertEqual(ReelScrub.target(from: 4, dragOffset: ReelScrub.spacing * 0.4, pageCount: 16), 4)
        XCTAssertEqual(ReelScrub.target(from: 4, dragOffset: ReelScrub.spacing * 0.6, pageCount: 16), 5)
        XCTAssertEqual(ReelScrub.target(from: 4, dragOffset: -ReelScrub.spacing * 10, pageCount: 16), 0)
        XCTAssertEqual(ReelScrub.target(from: 4, dragOffset: ReelScrub.spacing * 40, pageCount: 16), 15)
        XCTAssertEqual(ReelScrub.spacing, 14)
    }

    // MARK: loading earlier sermons as you near the end

    func testWindowLoadsEarlierSermonsAsYouNearTheEnd() throws {
        let store = try makeStore()
        for k in 0..<10 { try sermon(store, day(2026, 11, 22).addingTimeInterval(Double(-7 * k) * 86_400), title: "S\(k)", cards: 3) }
        let all = try LordsDayReel(store: store, calendar: calendar)
        let window = all.window(sermons: LordsDayReel.initialSermons)
        XCTAssertEqual(window.sermons.count, 3)
        XCTAssertTrue(window.hasMore)
        // Far from the end: nothing more.
        XCTAssertEqual(all.sermonsToLoad(loaded: 3, atFlat: 0), 3)
        // Within the lookahead of the loaded end: two more.
        XCTAssertEqual(all.sermonsToLoad(loaded: 3, atFlat: 9), 5)
        // Opening an earlier sermon loads through it and one past.
        XCTAssertEqual(all.sermonsToLoad(loaded: 3, through: 6), 8)
        // Never past what there is.
        XCTAssertEqual(all.sermonsToLoad(loaded: 9, atFlat: 35), 10)
        XCTAssertFalse(all.window(sermons: 10).hasMore)
    }

    // MARK: where the stack reopens

    func testStackReopensWhereYouLeftOffClamped() throws {
        let store = try makeStore()
        let note = try sermon(store, day(2026, 11, 22), title: "Smyrna", cards: 6)
        let reel = try LordsDayReel(store: store, calendar: calendar)
        var memory = LordsDayStackMemory()
        XCTAssertEqual(memory.page(for: reel.sermons[0]), 0)
        memory.remember(page: 4, for: note.id)
        XCTAssertEqual(memory.page(for: reel.sermons[0]), 4)
        memory.remember(page: 40, for: note.id)
        XCTAssertEqual(memory.page(for: reel.sermons[0]), 6)
        // It survives a round trip through its stored form.
        let restored = LordsDayStackMemory(stored: memory.stored)
        XCTAssertEqual(restored.page(for: reel.sermons[0]), 6)
        XCTAssertEqual(LordsDayStackMemory(stored: ["junk": 3, note.id.uuidString: -2]).page(for: reel.sermons[0]), 0)
    }

    // MARK: opening the reel from the journal (TKL-1085 pass 2)

    func testTheJournalOpensTheReelAtThatSermonNotTheTop() throws {
        let store = try makeStore()
        try sermon(store, day(2026, 11, 22), title: "Smyrna", cards: 6)
        let chain = try sermon(store, day(2026, 11, 8), title: "The Golden Chain", cards: 4)
        let unkept = try sermon(store, day(2026, 11, 15), title: "Not kept yet", cards: 0)
        let reel = try LordsDayReel(store: store, calendar: calendar)
        var memory = LordsDayStackMemory()
        // Never read: its cover.
        XCTAssertEqual(reel.opening(sermon: chain.id, memory: memory), ReelPosition(sermon: 1, page: 0))
        // Read before, from either place: the card last read, which the landing page shares.
        memory.remember(page: 3, for: chain.id)
        XCTAssertEqual(reel.opening(sermon: chain.id, memory: memory), ReelPosition(sermon: 1, page: 3))
        XCTAssertEqual(reel.flatIndex(of: reel.opening(sermon: chain.id, memory: memory)!), 7 + 3)
        // A sermon with no kept cards isn't in the reel.
        XCTAssertNil(reel.opening(sermon: unkept.id, memory: memory))
        XCTAssertNil(reel.opening(sermon: UUID(), memory: memory))
    }

    func testTheStackPeeksTheTwoCardsAfterTheTopOne() {
        XCTAssertEqual(LordsDayStackMemory.peeking(after: 4, pageCount: 7), [5, 6])
        XCTAssertEqual(LordsDayStackMemory.peeking(after: 6, pageCount: 7), [0, 1])
        XCTAssertEqual(LordsDayStackMemory.peeking(after: 0, pageCount: 2), [1, 0])
    }

    // MARK: the landing page's state

    func testLandingStates() {
        func state(sunday: Bool = false, thisWeek: Bool = false, kept: Bool = false, reading: Bool = false,
                   failed: Bool = false, review: Bool = false, empty: Bool = false) -> LordsDayLanding.Kind {
            LordsDayLanding.kind(isSunday: sunday, hasThisWeeksSermon: thisWeek, hasAnyKeptSermon: kept,
                                 isReadingNotes: reading, readFailed: failed, hasPendingReview: review,
                                 pendingReviewIsEmpty: empty)
        }
        XCTAssertEqual(state(), .firstSunday)
        XCTAssertEqual(state(kept: true), .noSermon)
        XCTAssertEqual(state(sunday: true, kept: true), .sundayBeforeNotes)
        XCTAssertEqual(state(sunday: true), .firstSunday)
        XCTAssertEqual(state(thisWeek: true, kept: true), .week)
        XCTAssertEqual(state(sunday: true, thisWeek: true, kept: true), .week)
        XCTAssertEqual(state(kept: true, review: true), .reviewPending)
        XCTAssertEqual(state(review: true), .reviewPending)
        XCTAssertEqual(state(kept: true, reading: true), .readingNotes)
        XCTAssertEqual(state(kept: true, reading: true, failed: true), .readFailed)
        // A draft waiting takes the stack's place even when the week already has kept cards.
        XCTAssertEqual(state(thisWeek: true, kept: true, review: true), .reviewPending)
        // TKL-1103: a second capture that drafted nothing doesn't hide the sermon just kept.
        XCTAssertEqual(state(thisWeek: true, kept: true, review: true, empty: true), .week)
        XCTAssertEqual(state(sunday: true, thisWeek: true, kept: true, review: true, empty: true), .week)
        // With no sermon kept this week, the empty review still shows so it can be discarded.
        XCTAssertEqual(state(kept: true, review: true, empty: true), .reviewPending)
    }

    func testHeaderTitle() {
        XCTAssertEqual(LordsDayLanding.title(kind: .week, isSunday: false), "This week")
        XCTAssertEqual(LordsDayLanding.title(kind: .week, isSunday: true), "Today")
        XCTAssertEqual(LordsDayLanding.title(kind: .firstSunday, isSunday: true), "Your sermon journal")
    }

    func testThisWeeksSermonAndAYearAgo() throws {
        let store = try makeStore()
        try sermon(store, day(2026, 11, 22), title: "Smyrna", cards: 2)
        try sermon(store, day(2025, 11, 23), title: "The Means of Grace", cards: 6)
        try sermon(store, day(2026, 11, 15), title: "Grace upon Grace", cards: 2)
        let reel = try LordsDayReel(store: store, calendar: calendar)
        // Thursday 26 Nov 2026: this week's sermon is the 22nd's.
        XCTAssertEqual(reel.thisWeek(today: day(2026, 11, 26), calendar: calendar)?.title, "Smyrna")
        XCTAssertEqual(reel.earlier(today: day(2026, 11, 26), calendar: calendar).map(\.title), ["Grace upon Grace", "The Means of Grace"])
        // Sunday 29th: no sermon kept for the new week yet.
        XCTAssertNil(reel.thisWeek(today: day(2026, 11, 29), calendar: calendar))
        XCTAssertEqual(reel.earlier(today: day(2026, 11, 29), calendar: calendar).first?.title, "Smyrna")
        // A year before the 26th falls in the week of 23 Nov 2025.
        XCTAssertEqual(reel.yearAgo(today: day(2026, 11, 26), calendar: calendar)?.title, "The Means of Grace")
        XCTAssertNil(reel.yearAgo(today: day(2026, 6, 10), calendar: calendar))
    }
}
