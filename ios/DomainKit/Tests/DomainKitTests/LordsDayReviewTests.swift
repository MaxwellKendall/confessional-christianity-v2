import Foundation
import SwiftData
import XCTest
@testable import DomainKit

final class LordsDayCardsEventTests: XCTestCase {
    func testParsesEveryStreamEvent() throws {
        XCTAssertEqual(try LordsDayCardsEvent.parse(line: #"{"type":"started","pages":2,"model":"gemini-3.8-flash"}"#), .started(pages: 2))
        XCTAssertEqual(try LordsDayCardsEvent.parse(line: #"{"type":"page","page":1,"extractedText":"notes","rejected":2}"#), .page(1))
        XCTAssertEqual(try LordsDayCardsEvent.parse(line: #"{"type":"error","page":0,"code":"unreadable","message":"x"}"#), .pageFailed(0))
        XCTAssertEqual(try LordsDayCardsEvent.parse(line: #"{"type":"done","cards":[],"rejected":0,"failedPages":[1],"costUsd":0.01}"#), .done(failedPages: [1]))
        let card = try LordsDayCardsEvent.parse(line: #"{"type":"card","card":{"id":"p0-1","kind":"quote","page":0,"order":1,"text":"He is not finished.","attribution":"Rev. Smith"}}"#)
        XCTAssertEqual(card, .card(DraftCardPayload(kind: "quote", page: 0, order: 1, text: "He is not finished.", attribution: "Rev. Smith")))
    }

    func testIgnoresBlankAndUnknownLinesButRejectsGarbage() throws {
        XCTAssertNil(try LordsDayCardsEvent.parse(line: "   "))
        XCTAssertNil(try LordsDayCardsEvent.parse(line: #"{"type":"heartbeat"}"#))
        XCTAssertThrowsError(try LordsDayCardsEvent.parse(line: "not json"))
    }
}

final class LordsDayReviewTests: XCTestCase {
    private let noteId = UUID()

    private func card(_ kind: String, page: Int, order: Int, text: String? = nil, osis: String? = nil, reference: String? = nil, attribution: String? = nil) -> LordsDayCardsEvent {
        .card(DraftCardPayload(kind: kind, page: page, order: order, text: text, reference: reference, osis: osis, attribution: attribution))
    }

    /// A two-page review whose drafting finished with a key point, a quote and a verse.
    private func readyReview() -> LordsDayReview {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        _ = review.begin()
        review.apply(.started(pages: 2))
        review.apply(.page(1))
        review.apply(card("verse", page: 1, order: 0, osis: "Rom.8.28", reference: "Romans 8:28"))
        review.apply(.page(0))
        review.apply(card("quote", page: 0, order: 1, text: "He is not finished.", attribution: "Rev. Smith"))
        review.apply(card("key_point", page: 0, order: 0, text: "God's purpose decides what is good."))
        review.apply(.done(failedPages: []))
        return review
    }

    func testCardsFillInAsTheyArriveInPageOrder() {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        XCTAssertEqual(review.phase, .notStarted)
        XCTAssertEqual(review.begin(), [0, 1])
        XCTAssertTrue(review.isDrafting)
        XCTAssertEqual(review.progress, 0)
        review.apply(.page(1))
        review.apply(card("verse", page: 1, order: 0, osis: "Rom.8.28", reference: "Romans 8:28"))
        XCTAssertEqual(review.cards.count, 1)
        XCTAssertEqual(review.progress, 0.5)
        XCTAssertFalse(review.canFinish, "no finishing while cards are still arriving")
        review.apply(.page(0))
        review.apply(card("key_point", page: 0, order: 0, text: "Point"))
        XCTAssertEqual(review.cards.map(\.kind), [.keyPoint, .verse])
        review.apply(.done(failedPages: []))
        XCTAssertEqual(review.phase, .ready)
        XCTAssertFalse(review.isDrafting)
        XCTAssertTrue(review.canFinish)
    }

    func testDraftedVerseKeepsOnlyItsReference() {
        let review = readyReview()
        let verse = review.cards.first { $0.kind == .verse }!
        XCTAssertEqual(verse.verseRef, "Rom.8.28")
        XCTAssertEqual(verse.text, "")
        XCTAssertFalse(verse.editedByUser)
        // A verse with no OSIS keeps the human reference rather than nothing.
        var other = LordsDayReview(noteId: noteId, pageCount: 1)
        _ = other.begin()
        other.apply(card("verse", page: 0, order: 0, reference: "Psalms 86:5"))
        XCTAssertEqual(other.cards.first?.verseRef, "Psalms 86:5")
        // A verse event carrying text never puts that text on the card.
        other.apply(card("verse", page: 0, order: 1, text: "For you, O Lord, are good", osis: "Ps.86.5"))
        XCTAssertEqual(other.cards.last?.text, "")
    }

    func testUnknownKindsAndDuplicateEventsAreDropped() {
        var review = LordsDayReview(noteId: noteId, pageCount: 1)
        _ = review.begin()
        review.apply(card("prayer", page: 0, order: 0, text: "Lord, help"))
        review.apply(card("key_point", page: 0, order: 1, text: "Point"))
        review.apply(card("key_point", page: 0, order: 1, text: "Point"))
        XCTAssertEqual(review.cards.count, 1)
    }

    func testSwitchingToVerseNeedsAPickedReference() throws {
        var review = readyReview()
        let point = review.cards[0]
        XCTAssertThrowsError(try review.setKind(point.id, to: .verse))
        try review.chooseVerse(point.id, osis: "John.3.16")
        let verse = review.card(point.id)!
        XCTAssertEqual(verse.kind, .verse)
        XCTAssertEqual(verse.verseRef, "John.3.16")
        XCTAssertTrue(verse.editedByUser)
        XCTAssertEqual(review.keptCards().first { $0.verseRef == "John.3.16" }?.body, "", "a kept verse stores only its reference")
        XCTAssertThrowsError(try review.chooseVerse(point.id, osis: "  "))
        // Switching back restores the words it had before.
        try review.setKind(point.id, to: .keyPoint)
        XCTAssertEqual(review.card(point.id)?.text, "God's purpose decides what is good.")
        XCTAssertNil(review.card(point.id)?.verseRef)
    }

    func testEditingMarksTheCardEditedButKeepingDoesNot() throws {
        var review = readyReview()
        let quote = review.cards[1]
        review.remove(quote.id)
        review.keep(quote.id)
        XCTAssertFalse(review.card(quote.id)!.editedByUser)
        try review.editText(quote.id, to: "He is not finished.")
        XCTAssertFalse(review.card(quote.id)!.editedByUser, "saving unchanged words is not an edit")
        try review.editText(quote.id, to: "  He is not finished with you.  ")
        XCTAssertEqual(review.card(quote.id)?.text, "He is not finished with you.")
        XCTAssertTrue(review.card(quote.id)!.editedByUser)
        XCTAssertThrowsError(try review.editText(review.cards[2].id, to: "Scripture typed by hand"), "verse words can't be typed")
    }

    func testQuoteAttributionCanBeChangedAndCleared() throws {
        var review = readyReview()
        let quote = review.cards[1]
        XCTAssertEqual(quote.attribution, "Rev. Smith")
        try review.editAttribution(quote.id, to: "Rev. Jones")
        XCTAssertEqual(review.card(quote.id)?.attribution, "Rev. Jones")
        try review.editAttribution(quote.id, to: "   ")
        XCTAssertEqual(review.card(quote.id)?.attribution, "", "cleared is stored as empty, not as 'use the preacher'")
        XCTAssertTrue(review.card(quote.id)!.editedByUser)
        XCTAssertEqual(review.keptCards()[1].attribution, "")
        XCTAssertThrowsError(try review.editAttribution(review.cards[0].id, to: "Someone"), "only quotes are attributed")
    }

    func testKeptCardsComeOutInOrderWithoutRemovedOnes() throws {
        var review = readyReview()
        review.remove(review.cards[0].id)
        let kept = review.keptCards()
        XCTAssertEqual(kept.map(\.kind), [.quote, .verse])
        XCTAssertEqual(kept[0].attribution, "Rev. Smith")
        XCTAssertNil(kept[1].attribution)
        review.remove(review.cards[1].id)
        review.remove(review.cards[2].id)
        XCTAssertFalse(review.canFinish, "a week needs at least one card")
    }

    func testAKeptCardWithNoWordsBlocksFinishing() throws {
        var review = readyReview()
        let verse = review.cards[2]
        try review.setKind(verse.id, to: .quote)
        XCTAssertEqual(review.blockingCardIndex, 2)
        XCTAssertFalse(review.canFinish)
        try review.editText(verse.id, to: "Words")
        XCTAssertNil(review.blockingCardIndex)
        XCTAssertTrue(review.canFinish)
    }

    func testFailedPagesAreRetriedAloneAndMappedBack() {
        var review = LordsDayReview(noteId: noteId, pageCount: 3)
        _ = review.begin()
        review.apply(.page(0))
        review.apply(card("key_point", page: 0, order: 0, text: "One"))
        review.apply(.pageFailed(1))
        review.apply(.page(2))
        review.apply(card("key_point", page: 2, order: 0, text: "Three"))
        review.apply(.done(failedPages: [1]))
        XCTAssertEqual(review.phase, .ready)
        XCTAssertEqual(review.failedPages, [1])
        XCTAssertTrue(review.canRetry)
        XCTAssertTrue(review.canFinish, "the cards that did arrive can be kept")
        // The retry sends only page 1; the server numbers it 0.
        XCTAssertEqual(review.begin(), [1])
        review.apply(.page(0))
        review.apply(card("quote", page: 0, order: 0, text: "Two words here"))
        review.apply(.done(failedPages: []))
        XCTAssertEqual(review.cards.map(\.text), ["One", "Two words here", "Three"])
        XCTAssertEqual(review.failedPages, [])
        XCTAssertFalse(review.canRetry)
    }

    func testAStreamThatStopsEarlyIsInterruptedAndResumable() {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        _ = review.begin()
        review.apply(.page(0))
        review.apply(card("key_point", page: 0, order: 0, text: "One"))
        review.interrupt()
        XCTAssertEqual(review.phase, .interrupted)
        XCTAssertTrue(review.canRetry)
        XCTAssertTrue(review.canFinish)
        XCTAssertEqual(review.begin(), [1])
    }

    func testEditsSurviveARetry() throws {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        _ = review.begin()
        review.apply(.page(0))
        review.apply(card("key_point", page: 0, order: 0, text: "One"))
        review.interrupt()
        try review.editText(review.cards[0].id, to: "Mine")
        _ = review.begin()
        review.apply(.page(0))
        review.apply(card("key_point", page: 0, order: 0, text: "Two"))
        review.apply(.done(failedPages: []))
        XCTAssertEqual(review.cards.map(\.text), ["Mine", "Two"])
    }

    func testPersistsAndADraftingReviewReopensInterrupted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try LordsDayReview.load(noteId: noteId, root: root))
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        _ = review.begin()
        review.apply(.page(0))
        review.apply(card("quote", page: 0, order: 0, text: "Saved words", attribution: "Rev. Smith"))
        try review.save(root: root)
        let reopened = try XCTUnwrap(LordsDayReview.load(noteId: noteId, root: root))
        XCTAssertEqual(reopened.cards, review.cards)
        XCTAssertEqual(reopened.phase, .interrupted, "a run the app didn't finish can't still be drafting after a relaunch")
        try LordsDayReview.delete(noteId: noteId, root: root)
        XCTAssertNil(try LordsDayReview.load(noteId: noteId, root: root))
    }
}

@MainActor final class LordsDayKeepTests: XCTestCase {
    func testKeepingReplacesTheNotesCardsInOrder() throws {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let note = LordsDayNote(serviceDate: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(note)
        try store.appendCard(to: note, kind: .keyPoint, body: "old")
        try store.keepCards([
            KeptCard(kind: .quote, body: "Words", verseRef: nil, attribution: "", editedByUser: true),
            KeptCard(kind: .verse, body: "", verseRef: "Rom.8.28", attribution: nil, editedByUser: false),
        ], for: note)
        let cards = try store.cards(for: note)
        XCTAssertEqual(cards.map(\.kind), [.quote, .verse])
        XCTAssertEqual(cards.map(\.position), [0, 1])
        XCTAssertEqual(cards.map(\.editedByUser), [true, false])
        XCTAssertEqual(cards[0].attribution, "")
        XCTAssertEqual(cards[1].verseRef, "Rom.8.28")
        XCTAssertThrowsError(try store.keepCards([KeptCard(kind: .verse, body: "typed scripture", verseRef: "Rom.8.28", attribution: nil, editedByUser: true)], for: note))
        XCTAssertEqual(try store.cards(for: note).count, 2, "a rejected keep changes nothing")
    }

    func testAClearedAttributionDoesNotFallBackToThePreacher() throws {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let note = LordsDayNote(serviceDate: date, passageRef: "Romans 8:28-30", preacher: "Rev. Smith")
        try store.save(note)
        try store.keepCards([
            KeptCard(kind: .quote, body: "Cleared", verseRef: nil, attribution: "", editedByUser: true),
            KeptCard(kind: .quote, body: "Unset", verseRef: nil, attribution: nil, editedByUser: false),
            KeptCard(kind: .quote, body: "Named", verseRef: nil, attribution: "Rev. Jones", editedByUser: true),
        ], for: note)
        let feed = LordsDayFeed(note: note, cards: try store.cards(for: note), today: date)
        XCTAssertEqual(feed.cards.map(\.attributionLine), ["Romans 8:28-30", "Rev. Smith · Romans 8:28-30", "Rev. Jones · Romans 8:28-30"])
    }
}
