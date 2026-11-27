import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import DomainKit

/// Sharing a Lord's Day feed card as an image (TKL-1060): every card kind maps
/// onto the quote-card renderer, and each gets a checked-in square snapshot.
@MainActor @Suite(.serialized) struct LordsDayShareCardTests {
    static let verse = "And we know that for those who love God all things work together for good, for those who are called according to his purpose."

    /// Key point, quote with its own speaker, quote falling back to the preacher, verse.
    static func feed() throws -> LordsDayFeed {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 9))!
        let note = LordsDayNote(serviceDate: sunday, passageRef: "Romans 8:28–30", preacher: "Rev. Smith")
        try store.save(note)
        try store.appendCard(to: note, kind: .keyPoint, body: "God's purpose, not our comfort, decides what is good.")
        let quote = try store.appendCard(to: note, kind: .quote, body: "The golden chain has no weak link.")
        quote.attribution = "Rev. Jones"
        try store.appendCard(to: note, kind: .quote, body: "Nothing in your hand is wasted by the Father.")
        try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Romans 8:28")
        let monday = calendar.date(byAdding: .day, value: 1, to: sunday)!
        return LordsDayFeed(note: note, cards: try store.cards(for: note), today: monday, calendar: calendar)
    }

    @Test func keyPointIsPlainTextFromThePassage() throws {
        let c = try Self.feed().cards[0].quoteCardContent()
        #expect(c.kind == .plain)
        #expect(c.text == "God's purpose, not our comfort, decides what is good.")
        #expect(c.attribution.lines == ["Sermon notes", "Romans 8:28–30"])
        #expect(c.link == QuoteCard.bareDomain)
    }

    @Test func quoteCarriesItsSpeakerAndThePassage() throws {
        let cards = try Self.feed().cards
        let own = cards[1].quoteCardContent()
        #expect(own.kind == .quote)
        #expect(own.text == "The golden chain has no weak link.")
        #expect(own.attribution.lines == ["Rev. Jones", "Romans 8:28–30"])
        #expect(cards[2].quoteCardContent().attribution.lines == ["Rev. Smith", "Romans 8:28–30"])
    }

    @Test func verseOpensWithItsLeadAndCitesTheReference() throws {
        let c = try Self.feed().cards[3].quoteCardContent(verseText: Self.verse)
        #expect(c.kind == .verse(lead: "And we know"))
        #expect(c.text.hasPrefix("that for those who love God"))
        #expect(c.attribution.lines == ["Romans 8:28", "ESV"])
    }

    @Test func verseWithoutItsTextShowsTheReference() throws {
        let c = try Self.feed().cards[3].quoteCardContent()
        #expect(c.kind == .plain)
        #expect(c.text == "Romans 8:28")
        #expect(c.attribution.lines.isEmpty)
    }

    @Test func plainCardsHaveNoDropCap() {
        let layout = QuoteCardLayout(QuoteCardContent(text: "God's purpose decides what is good.", kind: .plain), format: .square)
        #expect(!layout.textItems.contains { $0.role == .dropCap })
        #expect(layout.fits)
        let quote = QuoteCardLayout(QuoteCardContent(text: "God's purpose decides what is good."), format: .square)
        #expect(quote.textItems.contains { $0.role == .dropCap })
    }

    @Test func shareImageIsASquarePNGInThePaletteOnScreen() throws {
        let card = try Self.feed().cards[1]
        let light = try #require(card.sharePNG(dark: false))
        let dark = try #require(card.sharePNG(dark: true))
        #expect(light.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(light != dark)
        let image = try #require(QuoteCardRenderer.render(card.quoteCardContent(), palette: card.palette, format: .square))
        #expect(image.width == 1080 && image.height == 1080)
    }

    /// One snapshot per feed card kind, light and dark (`QUOTE_CARD_RECORD=1 swift test` re-records).
    @Test func snapshotsMatchTheCheckedInImages() throws {
        let record = ProcessInfo.processInfo.environment["QUOTE_CARD_RECORD"] == "1"
        let cards = try Self.feed().cards
        let cases: [(String, LordsDayFeedCard, String?)] = [
            ("keyPoint", cards[0], nil), ("quote", cards[1], nil), ("verse", cards[3], Self.verse), ("verseOffline", cards[3], nil),
        ]
        var recorded: [String] = []
        for (name, card, verseText) in cases {
            for dark in [false, true] {
                let palette = LordsDayFeed.palette(card.palette, dark: dark)
                let image = try #require(QuoteCardRenderer.render(card.quoteCardContent(verseText: verseText), palette: palette, format: .square))
                let url = QuoteCardSnapshotTests.fixtures.appendingPathComponent("lordsDay/\(name)-\(dark ? "dark" : "light").png")
                if record || !FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try #require(QuoteCardRenderer.pngData(image)).write(to: url)
                    recorded.append(url.lastPathComponent)
                    continue
                }
                let expected = try #require(Pixels(url: url))
                let diff = Pixels(image).fractionDiffering(from: expected, threshold: 24)
                #expect(diff < 0.002, "\(url.lastPathComponent): \(diff * 100)% of pixels differ")
            }
        }
        #expect(recorded.isEmpty, "recorded \(recorded.count) snapshots; run again to compare")
    }
}
