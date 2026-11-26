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

    func testReloadingSavedWeekUsesTheNewCalendarDay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = ModelConfiguration(schema: progressSchema, url: directory.appendingPathComponent("week.store"))
        func openStore() throws -> LordsDayStore {
            let container = try ModelContainer(for: progressSchema, configurations: [config])
            return LordsDayStore(context: ModelContext(container))
        }
        do {
            let store = try openStore()
            _ = try week(store, kinds: [.keyPoint, .quote, .verse, .keyPoint, .quote, .verse])
        }

        let store = try openStore()
        let tuesday = try XCTUnwrap(LordsDayFeed(store: store, today: day(2026, 11, 17), calendar: calendar))
        let wednesday = try XCTUnwrap(LordsDayFeed(store: store, today: day(2026, 11, 18), calendar: calendar))
        XCTAssertEqual(tuesday.todayIndex, 1)
        XCTAssertEqual(wednesday.todayIndex, 2)
        XCTAssertEqual(wednesday.cards[2].dayLabel, "Today · Wednesday")
        XCTAssertEqual(wednesday.cards[2].verseOsis, "Rom.8.30")
        XCTAssertNil(try LordsDayFeed(store: store, today: day(2026, 11, 22), calendar: calendar))
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

final class LordsDayCardLayoutTests: XCTestCase {
    func testBorderClearsStatusBarTabBarAndDotRailAcrossDevices() {
        let devices: [(name: String, width: Double, height: Double, top: Double, bottom: Double)] = [
            ("iPhone SE", 375, 667, 20, 0),
            ("iPhone 14", 390, 844, 47, 34),
            ("iPhone 17 Pro", 402, 874, 62, 34),
            ("iPhone 17 Pro Max", 440, 956, 62, 34),
        ]
        for device in devices {
            let layout = LordsDayCardLayout(safeAreaTop: device.top, safeAreaBottom: device.bottom)
            let border = layout.borderFrame(in: device.width, height: device.height)
            let inner = layout.innerFrame(in: device.width, height: device.height)

            // Clears top safe area by at least outerTopGap.
            XCTAssertGreaterThanOrEqual(border.minY, device.top + LordsDayCardLayout.outerTopGap, device.name)
            // Clears the 88pt floating tab bar (64pt tall + 24pt bottom) by at least 16pt.
            XCTAssertLessThanOrEqual(border.maxY, device.height - 104, device.name)
            // Leaves room on the right for the dot rail outside the card border.
            let dotRailMinX = device.width - LordsDayCardLayout.dotRailTrailing - LordsDayCardLayout.dotRailWidth
            XCTAssertLessThan(border.maxX, dotRailMinX, device.name)

            // Inner content rect keeps at least innerPadding from every card border edge.
            XCTAssertGreaterThanOrEqual(inner.minX - border.minX, LordsDayCardLayout.innerPadding, device.name)
            XCTAssertGreaterThanOrEqual(border.maxX - inner.maxX, LordsDayCardLayout.innerPadding, device.name)
            XCTAssertGreaterThanOrEqual(inner.minY - border.minY, LordsDayCardLayout.innerPadding, device.name)
            XCTAssertGreaterThanOrEqual(border.maxY - inner.maxY, LordsDayCardLayout.innerPadding, device.name)
            // Enough width for single-row footer actions ("Read full passage" + "Share") at Dynamic Type Large.
            XCTAssertGreaterThanOrEqual(inner.width, 300, device.name)
        }
    }

    func testBodyIsPlacedOpticallyAboveVerticalMiddleAndNeverOverflowsBand() {
        let layout = LordsDayCardLayout(safeAreaTop: 62, safeAreaBottom: 34)
        let border = layout.borderFrame(in: 402, height: 874)
        let inner = layout.innerFrame(in: 402, height: 874)
        let headerHeight: Double = 40
        let footerHeight: Double = 44
        let bandTop = inner.minY + headerHeight + LordsDayCardLayout.bandSpacing
        let bandBottom = inner.maxY - footerHeight - LordsDayCardLayout.bandSpacing
        let bandHeight = bandBottom - bandTop

        // Short quote / verse content starts well above the card's vertical middle.
        for contentHeight in [180.0, 220.0, 320.0] {
            let y = LordsDayCardLayout.bodyOriginY(bandTop: bandTop, bandHeight: bandHeight, contentHeight: contentHeight)
            let contentMidY = y + contentHeight / 2
            XCTAssertGreaterThanOrEqual(y, bandTop)
            XCTAssertLessThanOrEqual(y + contentHeight, bandBottom)
            XCTAssertLessThan(contentMidY, border.midY, "body should sit optically above card midpoint")
            XCTAssertLessThan(y, border.midY - 60, "body should start well above card midpoint")
        }

        // Tall content clamps cleanly to the top of the band instead of colliding with the header.
        let clamped = LordsDayCardLayout.bodyOriginY(bandTop: bandTop, bandHeight: bandHeight, contentHeight: bandHeight + 80)
        XCTAssertEqual(clamped, bandTop)
    }
}
