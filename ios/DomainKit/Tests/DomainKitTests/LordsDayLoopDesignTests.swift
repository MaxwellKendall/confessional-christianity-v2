import Foundation
import SwiftData
import Testing
@testable import DomainKit

/// The Lord's Day loop's design pass (TKL-942): editing and hiding a kept card
/// through the store's validation, the cover's note photos, and the share
/// sheet's palette row and cover image.
@MainActor @Suite(.serialized) struct LordsDayLoopDesignTests {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    static func store() throws -> LordsDayStore {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        return LordsDayStore(context: ModelContext(container))
    }

    static func note(_ store: LordsDayStore, title: String? = "The Golden Chain", passage: String? = "Romans 8:28–30",
                     preacher: String? = "Rev. Smith", church: String? = nil) throws -> LordsDayNote {
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 9))!
        let note = LordsDayNote(serviceDate: sunday, passageRef: passage, sermonTitle: title, preacher: preacher, church: church)
        try store.save(note)
        return note
    }

    // MARK: editing a kept card

    @Test func editingAKeyPointSavesTheNewWordsAndMarksItEdited() throws {
        let store = try Self.store(), note = try Self.note(store)
        let card = try store.appendCard(to: note, kind: .keyPoint, body: "Old words")
        try store.editBody(of: card, body: "  New words  ")
        #expect(try store.cards(for: note).first?.body == "New words")
        #expect(card.editedByUser)
    }

    @Test func blankWordsAreRejectedAndChangeNothing() throws {
        let store = try Self.store(), note = try Self.note(store)
        let card = try store.appendCard(to: note, kind: .quote, body: "Kept words")
        #expect(throws: LordsDayError.emptyBody) { try store.editBody(of: card, body: "  \n ") }
        #expect(card.body == "Kept words")
        #expect(!card.editedByUser)
    }

    @Test func aVerseCardsWordsCannotBeTyped() throws {
        let store = try Self.store(), note = try Self.note(store)
        let card = try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Rom.8.28")
        #expect(throws: LordsDayError.invalidVerse) { try store.editBody(of: card, body: "Typed scripture") }
        #expect(card.verseRef == "Rom.8.28")
    }

    @Test func aVerseCardChangesOnlyToAPickedReference() throws {
        let store = try Self.store(), note = try Self.note(store)
        let verse = try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Rom.8.28")
        try store.changeVerse(of: verse, to: "Rom.8.30")
        #expect(verse.verseRef == "Rom.8.30")
        #expect(verse.kind == .verse && verse.body.isEmpty)
        #expect(throws: LordsDayError.invalidVerse) { try store.changeVerse(of: verse, to: "  ") }
        let point = try store.appendCard(to: note, kind: .keyPoint, body: "A point")
        #expect(throws: LordsDayError.invalidVerse) { try store.changeVerse(of: point, to: "Rom.8.28") }
        #expect(point.kind == .keyPoint)
    }

    @Test func switchingBetweenKeyPointAndQuoteKeepsTheWords() throws {
        let store = try Self.store(), note = try Self.note(store)
        let card = try store.appendCard(to: note, kind: .keyPoint, body: "Words")
        try store.switchKind(of: card, to: .quote)
        #expect(card.kind == .quote && card.body == "Words")
    }

    @Test func aKeptCardIsFoundByItsFeedIdAndHidingRemovesItFromTheReel() throws {
        let store = try Self.store(), note = try Self.note(store)
        try store.appendCard(to: note, kind: .keyPoint, body: "One")
        let two = try store.appendCard(to: note, kind: .keyPoint, body: "Two")
        let reel = try LordsDayReel(store: store, today: note.serviceDate, calendar: Self.calendar)
        let feedCard = try #require(reel.sermons.first?.cards.last)
        let found = try #require(try store.card(id: feedCard.id))
        #expect(found.id == two.id)
        try store.removeCard(found)
        #expect(try store.card(id: feedCard.id) == nil)
        let after = try LordsDayReel(store: store, today: note.serviceDate, calendar: Self.calendar)
        #expect(after.sermons.first?.cards.map(\.body) == ["One"])
    }

    // MARK: the cover's note photos

    @Test func savedPagesReadEveryPhotoInOrderWithoutCreatingFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tkl942-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        #expect(CaptureDraft.savedPages(noteId: id, root: root).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let draft = try CaptureDraft(noteId: id, root: root)
        try draft.addPage(Data("page one".utf8))
        try draft.addPage(Data("page two".utf8))
        #expect(CaptureDraft.savedPages(noteId: id, root: root) == [Data("page one".utf8), Data("page two".utf8)])
    }

    // MARK: sharing

    @Test func theShareSheetOffersTheHousePalettes() {
        #expect(LordsDayShare.palettes == LordsDayFeed.rotation)
    }

    @Test func theCoverSharesItsTitleWithPassagePreacherAndChurch() throws {
        let store = try Self.store(), note = try Self.note(store, church: "Grace Church")
        try store.appendCard(to: note, kind: .keyPoint, body: "One")
        let sermon = try #require(try LordsDayReel(store: store, today: note.serviceDate, calendar: Self.calendar).sermons.first)
        let c = sermon.coverQuoteCardContent
        #expect(c.kind == .plain)
        #expect(c.text == "The Golden Chain")
        #expect(c.attribution.lines == ["Rev. Smith", "Grace Church · Romans 8:28–30 · Sunday, November 22"])
    }

    @Test func aCoverNamedByItsPassageDoesNotRepeatIt() throws {
        let store = try Self.store(), note = try Self.note(store, title: nil, preacher: nil)
        try store.appendCard(to: note, kind: .keyPoint, body: "One")
        let sermon = try #require(try LordsDayReel(store: store, today: note.serviceDate, calendar: Self.calendar).sermons.first)
        let c = sermon.coverQuoteCardContent
        #expect(c.text == "Romans 8:28–30")
        #expect(c.attribution.lines == ["Sunday, November 22"])
    }

    @Test func thePaletteChosenInTheSheetIsTheImagesPalette() throws {
        let store = try Self.store(), note = try Self.note(store)
        try store.appendCard(to: note, kind: .keyPoint, body: "God's purpose decides what is good.")
        let sermon = try #require(try LordsDayReel(store: store, today: note.serviceDate, calendar: Self.calendar).sermons.first)
        let card = try #require(sermon.cards.first)
        let vellum = try #require(LordsDayShare.png(card.quoteCardContent(), palette: .vellum))
        let psalter = try #require(LordsDayShare.png(card.quoteCardContent(), palette: .psalter))
        #expect(vellum != psalter)
        #expect(vellum == QuoteCardRenderer.pngData(card.quoteCardContent(), palette: .vellum, format: .square))
        #expect(LordsDayShare.png(sermon.coverQuoteCardContent, palette: .hymnal) != nil)
    }
}
