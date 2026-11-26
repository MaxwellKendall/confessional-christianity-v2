import Foundation
import SwiftData
import XCTest
@testable import DomainKit

final class LordsDayCardsEventTests: XCTestCase {
    func testParsesEveryStreamEvent() throws {
        XCTAssertEqual(try LordsDayCardsEvent.parse(line: #"{"type":"started","pages":2,"model":"gemini-3.8-flash"}"#), .started(pages: 2))
        XCTAssertEqual(try LordsDayCardsEvent.parse(line: #"{"type":"page","page":1,"extractedText":"notes","rejected":2}"#), .page(1, cardCount: nil))
        XCTAssertEqual(try LordsDayCardsEvent.parse(line: #"{"type":"page","page":1,"extractedText":"notes","rejected":2,"cardCount":3}"#), .page(1, cardCount: 3))
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
    /// Cards start undecided; pass `keepAll: true` for tests exercising post-decision behavior.
    private func readyReview(keepAll: Bool = false) -> LordsDayReview {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        _ = review.begin()
        review.apply(.started(pages: 2))
        review.apply(.page(1, cardCount: 1))
        review.apply(card("verse", page: 1, order: 0, osis: "Rom.8.28", reference: "Romans 8:28"))
        review.apply(.page(0, cardCount: 2))
        review.apply(card("quote", page: 0, order: 1, text: "He is not finished.", attribution: "Rev. Smith"))
        review.apply(card("key_point", page: 0, order: 0, text: "God's purpose decides what is good."))
        review.apply(.done(failedPages: []))
        if keepAll {
            for card in review.cards { review.keep(card.id) }
        }
        return review
    }

    func testCardsFillInAsTheyArriveInPageOrder() {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        XCTAssertEqual(review.phase, .notStarted)
        XCTAssertEqual(review.begin(), [0, 1])
        XCTAssertTrue(review.isDrafting)
        XCTAssertEqual(review.progress, 0)
        review.apply(.page(1, cardCount: 1))
        XCTAssertEqual(review.progress, 0, "a page header alone does not mark the page read before its cards arrive")
        review.apply(card("verse", page: 1, order: 0, osis: "Rom.8.28", reference: "Romans 8:28"))
        XCTAssertEqual(review.cards.count, 1)
        XCTAssertEqual(review.progress, 0.5)
        XCTAssertFalse(review.canFinish, "no finishing while cards are still arriving")
        review.apply(.page(0, cardCount: 1))
        review.apply(card("key_point", page: 0, order: 0, text: "Point"))
        XCTAssertEqual(review.cards.map(\.kind), [.keyPoint, .verse])
        review.apply(.done(failedPages: []))
        XCTAssertEqual(review.phase, .ready)
        XCTAssertFalse(review.isDrafting)
        XCTAssertFalse(review.canFinish, "cards start undecided until the user keeps or removes each one")
        for card in review.cards { review.keep(card.id) }
        XCTAssertTrue(review.canFinish)
    }

    func testEachDraftStartsUndecidedAndAnUntouchedQuoteCannotBeFinished() {
        var review = readyReview(keepAll: false)
        XCTAssertEqual(review.cards.map(\.decision), [.undecided, .undecided, .undecided])
        XCTAssertEqual(review.undecidedCount, 3)
        XCTAssertEqual(review.keptCount, 0)
        XCTAssertTrue(review.keptCards().isEmpty)
        XCTAssertFalse(review.canFinish)

        // Keep the key point and verse, leaving the quote untouched.
        review.keep(review.cards[0].id)
        review.keep(review.cards[2].id)
        XCTAssertEqual(review.undecidedCount, 1)
        XCTAssertFalse(review.canFinish, "an untouched quote blocks finishing")
        XCTAssertFalse(review.keptCards().contains { $0.kind == .quote }, "an untouched quote is never in keptCards")

        // Once the quote is explicitly removed (or kept), finishing unlocks.
        review.remove(review.cards[1].id)
        XCTAssertEqual(review.undecidedCount, 0)
        XCTAssertTrue(review.canFinish)
        XCTAssertEqual(review.keptCards().map(\.kind), [.keyPoint, .verse])
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
        var review = readyReview(keepAll: true)
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
        var review = readyReview(keepAll: true)
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
        var review = readyReview(keepAll: true)
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
        var review = readyReview(keepAll: true)
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
        var review = readyReview(keepAll: true)
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
        review.apply(.page(0, cardCount: 1))
        review.apply(card("key_point", page: 0, order: 0, text: "One"))
        review.apply(.pageFailed(1))
        review.apply(.page(2, cardCount: 1))
        review.apply(card("key_point", page: 2, order: 0, text: "Three"))
        review.apply(.done(failedPages: [1]))
        XCTAssertEqual(review.phase, .ready)
        XCTAssertEqual(review.failedPages, [1])
        XCTAssertTrue(review.canRetry)
        for card in review.cards { review.keep(card.id) }
        XCTAssertFalse(review.canFinish, "an unread failed page blocks finishing until retried or explicitly skipped")
        XCTAssertEqual(review.unhandledUnreadPages, [1])
        review.skipUnreadPages()
        XCTAssertTrue(review.canFinish, "the cards that did arrive can be kept after explicitly skipping unread pages")
        // The retry sends only page 1; the server numbers it 0, and clears its skipped state.
        XCTAssertEqual(review.begin(), [1])
        review.apply(.page(0, cardCount: 1))
        review.apply(card("quote", page: 0, order: 0, text: "Two words here"))
        review.apply(.done(failedPages: []))
        XCTAssertEqual(review.cards.map(\.text), ["One", "Two words here", "Three"])
        XCTAssertEqual(review.failedPages, [])
        XCTAssertEqual(review.skippedPages, [])
        XCTAssertFalse(review.canRetry)
    }

    func testAStreamThatStopsEarlyIsInterruptedAndResumable() {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        _ = review.begin()
        review.apply(.page(0, cardCount: 1))
        review.apply(card("key_point", page: 0, order: 0, text: "One"))
        review.interrupt()
        XCTAssertEqual(review.phase, .interrupted)
        XCTAssertTrue(review.canRetry)
        review.keep(review.cards[0].id)
        XCTAssertFalse(review.canFinish, "an unread page blocks finishing until retried or explicitly skipped")
        XCTAssertEqual(review.begin(), [1])
    }

    func testFinishBlockedWhenMidPageDropLeavesUnreadPageUntilSkippedOrCompleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("unread-drop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var review = LordsDayReview(noteId: noteId, pageCount: 1)
        _ = review.begin()
        // Two-card stream drops after the first card: page 0 is still unread.
        review.apply(.page(0, cardCount: 2))
        review.apply(card("key_point", page: 0, order: 0, text: "First card"))
        review.interrupt()

        review.keep("p0-0")
        XCTAssertEqual(review.unreadPages, [0])
        XCTAssertEqual(review.unhandledUnreadPages, [0])
        XCTAssertFalse(review.canFinish, "keeping the first card of a dropped page must not unlock finish")

        // Explicit skip unlocks finish and persists across save/load.
        review.skipUnreadPages()
        XCTAssertEqual(review.unhandledUnreadPages, [])
        XCTAssertTrue(review.canFinish)
        try review.save(root: root)
        let reopened = try XCTUnwrap(LordsDayReview.load(noteId: noteId, root: root))
        XCTAssertEqual(reopened.skippedPages, [0])
        XCTAssertTrue(reopened.canFinish)
    }

    func testReorderedRetryPreservesEditsWithoutDroppingOrDuplicatingCards() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reorder-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var review = LordsDayReview(noteId: noteId, pageCount: 1)
        _ = review.begin()
        review.apply(.page(0, cardCount: 2))
        review.apply(card("key_point", page: 0, order: 0, text: "Card A"))
        review.interrupt()

        // Edit and keep Card A, then persist and reopen before retrying.
        let cardAId = try XCTUnwrap(review.cards.first?.id)
        try review.editText(cardAId, to: "Edited A")
        try review.setKind(cardAId, to: .quote)
        review.keep(cardAId)
        try review.save(root: root)
        review = try XCTUnwrap(LordsDayReview.load(noteId: noteId, root: root))

        // Retry returns [B, A] in reversed order, so B has positional order 0 and A has order 1.
        XCTAssertEqual(review.begin(), [0])
        review.apply(.page(0, cardCount: 2))
        review.apply(card("key_point", page: 0, order: 0, text: "Card B"))
        review.apply(card("key_point", page: 0, order: 1, text: "Card A"))
        review.apply(.done(failedPages: []))

        XCTAssertEqual(review.readPages, [0])
        XCTAssertEqual(review.unreadPages, [])
        XCTAssertEqual(review.cards.count, 2, "neither dropped B nor duplicated A")
        XCTAssertEqual(review.cards.map(\.text), ["Card B", "Edited A"])
        let reconciledA = try XCTUnwrap(review.card(cardAId))
        XCTAssertEqual(reconciledA.text, "Edited A")
        XCTAssertEqual(reconciledA.kind, .quote)
        XCTAssertTrue(reconciledA.editedByUser)
        XCTAssertEqual(reconciledA.decision, .keep)
        let newB = try XCTUnwrap(review.cards.first { $0.id != cardAId })
        XCTAssertEqual(newB.text, "Card B")
        XCTAssertEqual(newB.decision, .undecided)
        XCTAssertFalse(newB.editedByUser)
    }

    func testReorderedRetryPreservesEditedVerseCardWithoutDuplicating() throws {
        var review = LordsDayReview(noteId: noteId, pageCount: 1)
        _ = review.begin()
        review.apply(.page(0, cardCount: 2))
        review.apply(.card(DraftCardPayload(kind: "verse", page: 0, order: 0, reference: "Romans 8:28", osis: "Rom.8.28")))
        review.interrupt()

        let verseId = try XCTUnwrap(review.cards.first?.id)
        try review.chooseVerse(verseId, osis: "Rom.8.29")
        review.keep(verseId)

        XCTAssertEqual(review.begin(), [0])
        review.apply(.page(0, cardCount: 2))
        review.apply(card("key_point", page: 0, order: 0, text: "God works all things together"))
        review.apply(.card(DraftCardPayload(kind: "verse", page: 0, order: 1, reference: "Romans 8:28", osis: "Rom.8.28")))
        review.apply(.done(failedPages: []))

        XCTAssertEqual(review.cards.count, 2)
        let keptVerse = try XCTUnwrap(review.card(verseId))
        XCTAssertEqual(keptVerse.verseRef, "Rom.8.29")
        XCTAssertTrue(keptVerse.kept)
        XCTAssertTrue(keptVerse.editedByUser)
    }

    func testDropBetweenPageHeaderAndLastCardReplaysWithoutLosingEditsOrDuplicating() throws {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        XCTAssertEqual(review.begin(), [0, 1])
        // Page 0 completes fully.
        review.apply(.page(0, cardCount: 1))
        review.apply(card("key_point", page: 0, order: 0, text: "Page zero"))
        XCTAssertEqual(review.readPages, [0])
        // Page 1 header announces 2 cards, but the stream drops after only the first card.
        review.apply(.page(1, cardCount: 2))
        review.apply(card("quote", page: 1, order: 0, text: "Original words", attribution: "Rev. Smith"))
        review.interrupt()

        XCTAssertEqual(review.readPages, [0], "page 1 is not read until all its cards arrive")
        XCTAssertEqual(review.unreadPages, [1])
        XCTAssertTrue(review.canRetry)

        // User edits and keeps the card that already arrived on page 1.
        try review.editText("p1-0", to: "Edited words")
        review.keep("p1-0")

        // Retry sends only page 1 (numbered 0 in the retry request).
        XCTAssertEqual(review.begin(), [1])
        review.apply(.page(0, cardCount: 2))
        review.apply(card("quote", page: 0, order: 0, text: "Original words", attribution: "Rev. Smith"))
        review.apply(card("key_point", page: 0, order: 1, text: "Second card from page 1"))
        review.apply(.done(failedPages: []))

        XCTAssertEqual(review.readPages, [0, 1])
        XCTAssertEqual(review.unreadPages, [])
        XCTAssertFalse(review.canRetry)
        XCTAssertEqual(review.cards.map(\.id), ["p0-0", "p1-0", "p1-1"])
        XCTAssertEqual(review.card("p1-0")?.text, "Edited words", "edit on partial page survived retry")
        XCTAssertEqual(review.card("p1-0")?.editedByUser, true)
        XCTAssertEqual(review.card("p1-0")?.decision, .keep)
        XCTAssertEqual(review.card("p1-1")?.text, "Second card from page 1")
        XCTAssertEqual(review.card("p1-1")?.decision, .undecided)
    }

    func testDropAfterPageHeaderWithNoCardCountReplaysPage() throws {
        var review = LordsDayReview(noteId: noteId, pageCount: 1)
        _ = review.begin()
        review.apply(.page(0, cardCount: nil))
        review.apply(card("key_point", page: 0, order: 0, text: "First"))
        review.interrupt()
        XCTAssertEqual(review.unreadPages, [0], "without cardCount, a page is not read until done arrives")
        XCTAssertTrue(review.canRetry)

        try review.editText("p0-0", to: "Edited")
        XCTAssertEqual(review.begin(), [0])
        review.apply(.page(0, cardCount: nil))
        review.apply(card("key_point", page: 0, order: 0, text: "First"))
        review.apply(card("key_point", page: 0, order: 1, text: "Second"))
        review.apply(.done(failedPages: []))
        XCTAssertEqual(review.readPages, [0])
        XCTAssertEqual(review.cards.map(\.text), ["Edited", "Second"])
    }

    func testEditsSurviveARetry() throws {
        var review = LordsDayReview(noteId: noteId, pageCount: 2)
        _ = review.begin()
        review.apply(.page(0, cardCount: 1))
        review.apply(card("key_point", page: 0, order: 0, text: "One"))
        review.interrupt()
        try review.editText(review.cards[0].id, to: "Mine")
        _ = review.begin()
        review.apply(.page(0, cardCount: 1))
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
        review.apply(.page(0, cardCount: 1))
        review.apply(card("quote", page: 0, order: 0, text: "Saved words", attribution: "Rev. Smith"))
        review.keep("p0-0")
        try review.save(root: root)
        let reopened = try XCTUnwrap(LordsDayReview.load(noteId: noteId, root: root))
        XCTAssertEqual(reopened.cards, review.cards)
        XCTAssertEqual(reopened.card("p0-0")?.decision, .keep)
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

    func testPendingReviewIsReachableForNoteDatedEightDaysAgo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pending-old-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let eightDaysAgo = calendar.date(byAdding: .day, value: -8, to: today)!

        let oldNote = LordsDayNote(serviceDate: eightDaysAgo, passageRef: "Psalm 98", extractedText: "Sing a new song")
        try store.save(oldNote)
        var review = LordsDayReview(noteId: oldNote.id, pageCount: 1)
        _ = review.begin()
        review.apply(.page(0, cardCount: 1))
        review.apply(.card(DraftCardPayload(kind: "key_point", page: 0, order: 0, text: "Sing to the Lord.")))
        review.apply(.done(failedPages: []))
        try review.save(root: root)

        // Outside the current week window, yet still reachable by its saved note id.
        XCTAssertNil(try store.currentWeek(on: today, calendar: calendar))
        XCTAssertEqual(try store.pendingReviewNotes(root: root).map(\.id), [oldNote.id])
        XCTAssertEqual(try store.note(id: oldNote.id)?.id, oldNote.id)

        // While it is an active in-progress capture, it is not a pending review.
        try CaptureDraft.setActive(oldNote.id, root: root)
        XCTAssertEqual(try store.pendingReviewNotes(root: root).map(\.id), [])
        try CaptureDraft.setActive(nil, root: root)

        // After finishing, it leaves pending reviews.
        review.keep("p0-0")
        try store.keepCards(review.keptCards(), for: oldNote)
        try LordsDayReview.delete(noteId: oldNote.id, root: root)
        XCTAssertEqual(try store.pendingReviewNotes(root: root).map(\.id), [])
    }

    func testNewerZeroCardPendingReviewDoesNotHideOlderPendingReview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pending-multi-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let eightDaysAgo = calendar.date(byAdding: .day, value: -8, to: today)!

        let older = LordsDayNote(serviceDate: eightDaysAgo, passageRef: "Psalm 98", extractedText: "Sing a new song", updatedAt: eightDaysAgo)
        try store.save(older)
        var olderReview = LordsDayReview(noteId: older.id, pageCount: 1)
        _ = olderReview.begin()
        olderReview.apply(.page(0, cardCount: 1))
        olderReview.apply(.card(DraftCardPayload(kind: "key_point", page: 0, order: 0, text: "Sing to the Lord.")))
        olderReview.apply(.done(failedPages: []))
        try olderReview.save(root: root)

        let newer = LordsDayNote(serviceDate: today, passageRef: "Romans 8", extractedText: "Blank notes", updatedAt: today)
        try store.save(newer)
        var newerReview = LordsDayReview(noteId: newer.id, pageCount: 1)
        _ = newerReview.begin()
        newerReview.apply(.page(0, cardCount: 0))
        newerReview.apply(.done(failedPages: []))
        try newerReview.save(root: root)
        XCTAssertFalse(newerReview.canFinish)

        let pending = try store.pendingReviewNotes(root: root)
        XCTAssertEqual(pending.map(\.id), [newer.id, older.id], "both newer zero-card and older pending reviews remain listed")
        XCTAssertEqual(try store.note(id: older.id)?.id, older.id)
        XCTAssertEqual(try LordsDayReview.load(noteId: older.id, root: root)?.cards.count, 1)
    }
}
