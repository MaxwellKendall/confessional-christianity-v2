import Foundation
import SwiftData
import Testing
@testable import DomainKit

// TKL-1061: the cards call reads which sermon the notes are on; drafting saves it
// onto the note, and every place that named a Lord's Day by its date names the sermon.

private let smyrna = SermonDetails(title: "To the Church at Smyrna", preacher: "Rev. Ross Hodges", passage: "Revelation 2:8-11", church: nil, serviceDate: nil)

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func day(_ iso: String) -> Date {
    let parts = iso.split(separator: "-").map { Int($0)! }
    return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
}

@Suite struct SermonEventTests {
    @Test func parsesTheSermonEvent() throws {
        let line = #"{"type":"sermon","page":0,"sermon":{"title":"To the Church at Smyrna","preacher":null,"passage":"Revelation 2:8-11","church":null,"serviceDate":"2026-11-22"}}"#
        #expect(try LordsDayCardsEvent.parse(line: line) == .sermon(0, SermonDetails(
            title: "To the Church at Smyrna", preacher: nil, passage: "Revelation 2:8-11", church: nil, serviceDate: "2026-11-22")))
    }

    @Test func aSermonEventWithNoPageOrObjectIsIgnored() throws {
        #expect(try LordsDayCardsEvent.parse(line: #"{"type":"sermon","sermon":{}}"#) == nil)
        #expect(try LordsDayCardsEvent.parse(line: #"{"type":"sermon","page":0}"#) == nil)
    }

    @Test func blankStringsReadAsMissing() {
        let details = SermonDetails(title: "  ", preacher: "", passage: " Romans 8 ", church: nil, serviceDate: nil)
        #expect(details.title == nil)
        #expect(details.preacher == nil)
        #expect(details.passage == "Romans 8")
        #expect(SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: nil).isEmpty)
    }
}

@Suite struct ReviewSermonTests {
    @Test func theReviewKeepsEachFieldFromTheEarliestNotePage() throws {
        var review = LordsDayReview(noteId: UUID(), pageCount: 2)
        _ = review.begin()
        review.apply(.page(1, cardCount: 0))
        review.apply(.sermon(1, SermonDetails(title: nil, preacher: nil, passage: "Revelation 2:10", church: "Grace Presbyterian", serviceDate: nil)))
        review.apply(.page(0, cardCount: 0))
        review.apply(.sermon(0, SermonDetails(title: "To the Church at Smyrna", preacher: nil, passage: "Revelation 2:8-11", church: nil, serviceDate: nil)))
        #expect(review.sermon == SermonDetails(title: "To the Church at Smyrna", preacher: nil, passage: "Revelation 2:8-11", church: "Grace Presbyterian", serviceDate: nil))
    }

    @Test func aRetryMapsTheRequestPageToTheNotePage() throws {
        var review = LordsDayReview(noteId: UUID(), pageCount: 2)
        _ = review.begin()
        review.apply(.page(0, cardCount: 0))
        review.apply(.pageFailed(1))
        review.apply(.done(failedPages: [1]))
        #expect(review.begin() == [1])
        review.apply(.sermon(0, SermonDetails(title: nil, preacher: "Rev. Ross Hodges", passage: nil, church: nil, serviceDate: nil)))
        #expect(review.sermon?.preacher == "Rev. Ross Hodges")
    }

    @Test func survivesSavingAndAReviewSavedBeforeItLoads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var review = LordsDayReview(noteId: UUID(), pageCount: 1)
        _ = review.begin()
        review.apply(.page(0, cardCount: 0))
        review.apply(.sermon(0, smyrna))
        try review.save(root: root)
        #expect(try LordsDayReview.load(noteId: review.noteId, root: root)?.sermon == smyrna)

        // review.json as written before TKL-1061: no sermon key.
        let old = LordsDayReview(noteId: UUID(), pageCount: 1)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "sermon")
        let file = LordsDayReview.url(noteId: old.noteId, root: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        #expect(try LordsDayReview.load(noteId: old.noteId, root: root)?.sermon == nil)
    }
}

@Suite struct FillNoteTests {
    private func note(createdOn created: String, serviceDate: String? = nil) -> LordsDayNote {
        let createdAt = day(created).addingTimeInterval(15 * 3600)
        let sunday = serviceDate.map(day) ?? lastSunday(onOrBefore: createdAt, calendar: utc)
        return LordsDayNote(serviceDate: sunday, createdAt: createdAt, updatedAt: createdAt)
    }

    @Test func fillsEveryEmptyFieldAndMarksTheNoteChanged() {
        let n = note(createdOn: "2026-11-26")
        let before = n.updatedAt
        let details = SermonDetails(title: "To the Church at Smyrna", preacher: "Rev. Ross Hodges", passage: "Revelation 2:8-11", church: "Grace Presbyterian", serviceDate: "2026-11-22")
        #expect(n.fill(with: details, calendar: utc))
        #expect(n.sermonTitle == "To the Church at Smyrna")
        #expect(n.preacher == "Rev. Ross Hodges")
        #expect(n.passageRef == "Revelation 2:8-11")
        #expect(n.church == "Grace Presbyterian")
        #expect(n.serviceDate == day("2026-11-22"))
        #expect(n.updatedAt > before)
    }

    @Test func neverOverwritesWhatThePersonTyped() {
        let n = note(createdOn: "2026-11-26")
        n.sermonTitle = "Smyrna"
        n.passageRef = "Rev 2"
        #expect(n.fill(with: smyrna, calendar: utc))
        #expect(n.sermonTitle == "Smyrna")
        #expect(n.passageRef == "Rev 2")
        #expect(n.preacher == "Rev. Ross Hodges")
    }

    @Test func nothingNewChangesNothing() {
        let n = note(createdOn: "2026-11-26")
        let before = n.updatedAt
        #expect(!n.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: nil), calendar: utc))
        #expect(n.updatedAt == before)
    }

    @Test func aDateFromThePageFillsOnlyAnUntouchedServiceDate() {
        let picked = note(createdOn: "2026-11-26", serviceDate: "2026-11-15")
        _ = picked.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: "2026-11-22"), calendar: utc)
        #expect(picked.serviceDate == day("2026-11-15"))

        let untouched = note(createdOn: "2026-11-26")
        _ = untouched.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: "2026-11-15"), calendar: utc)
        #expect(untouched.serviceDate == day("2026-11-15"))
    }

    @Test func anImplausiblePageDateIsIgnored() {
        // The eval's photo reads 07/26/26 as 2020-07-26; a misread year must not move the week.
        let n = note(createdOn: "2026-11-26")
        let sunday = n.serviceDate
        _ = n.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: "2020-07-26"), calendar: utc)
        #expect(n.serviceDate == sunday)
        _ = n.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: "2026-12-06"), calendar: utc)
        #expect(n.serviceDate == sunday)
        _ = n.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: "not a date"), calendar: utc)
        #expect(n.serviceDate == sunday)
    }
}

@Suite struct SermonHeadingTests {
    @Test func theTitleLeadsWithPreacherAndPassageBeneath() {
        let heading = SermonHeading(title: "To the Church at Smyrna", passage: "Revelation 2:8-11", preacher: "Rev. Ross Hodges", date: "Sun, Nov 22")
        #expect(heading.headline == "To the Church at Smyrna")
        #expect(heading.byline == "Rev. Ross Hodges · Revelation 2:8-11")
        #expect(heading.hasSermonName)
    }

    @Test func withoutATitleThePassageLeads() {
        let heading = SermonHeading(title: nil, passage: "Revelation 2:8-11", preacher: "Rev. Ross Hodges", date: "Sun, Nov 22")
        #expect(heading.headline == "Revelation 2:8-11")
        #expect(heading.byline == "Rev. Ross Hodges")
    }

    @Test func aLordsDayKeptBeforeThisChangeFallsBackToItsDate() {
        let heading = SermonHeading(title: " ", passage: nil, preacher: nil, date: "Sun, Nov 22")
        #expect(heading.headline == "Sun, Nov 22")
        #expect(heading.byline == nil)
        #expect(!heading.hasSermonName)
    }

    @Test @MainActor func aNoteGivesItsHeading() {
        let n = LordsDayNote(serviceDate: day("2026-11-22"), passageRef: "Revelation 2:8-11", sermonTitle: "To the Church at Smyrna")
        #expect(SermonHeading(note: n, date: "Nov 22").headline == "To the Church at Smyrna")
        #expect(SermonHeading(note: LordsDayNote(serviceDate: day("2026-11-22")), date: "Nov 22").headline == "Nov 22")
    }
}

@Suite @MainActor struct FeedNamesTheSermonTests {
    @Test func keyPointsSayWhichSermonTheyAreFrom() throws {
        let container = try ModelContainer(for: LordsDayNote.self, NoteCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LordsDayStore(context: container.mainContext)
        let note = LordsDayNote(serviceDate: day("2026-11-22"), passageRef: "Revelation 2:8-11", sermonTitle: "To the Church at Smyrna")
        try store.save(note)
        try store.appendCard(to: note, kind: .keyPoint, body: "Do not fear.")
        let feed = LordsDayFeed(note: note, cards: try store.cards(for: note), today: day("2026-11-23"), calendar: utc)
        #expect(feed.cards[0].attributionLine == "From your notes on To the Church at Smyrna")

        let untitled = LordsDayNote(serviceDate: day("2026-11-22"), passageRef: "Revelation 2:8-11")
        try store.save(untitled)
        try store.appendCard(to: untitled, kind: .keyPoint, body: "Do not fear.")
        let plain = LordsDayFeed(note: untitled, cards: try store.cards(for: untitled), today: day("2026-11-23"), calendar: utc)
        #expect(plain.cards[0].attributionLine == "From your notes on Revelation 2:8-11")
    }
}
