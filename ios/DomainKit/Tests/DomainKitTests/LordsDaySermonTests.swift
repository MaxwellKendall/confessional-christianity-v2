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

@Suite struct SermonPassageValidationTests {
    @Test func emptyInputIsAllowedBecausePassageIsOptional() {
        #expect(validateSermonPassage("") == .empty)
        #expect(validateSermonPassage("   \n\t ") == .empty)
    }

    @Test func validReferencesMatchServerOsisPath() {
        #expect(validateSermonPassage("Revelation 2:8-11") == .valid(canonical: "Revelation 2:8-11", osis: "Rev.2.8-Rev.2.11"))
        #expect(validateSermonPassage("Revelation 2:8–11") == .valid(canonical: "Revelation 2:8-11", osis: "Rev.2.8-Rev.2.11"))
        #expect(validateSermonPassage("Romans 8:28") == .valid(canonical: "Romans 8:28", osis: "Rom.8.28"))
        #expect(validateSermonPassage("Psalm 86:5") == .valid(canonical: "Psalms 86:5", osis: "Ps.86.5"))
        #expect(validateSermonPassage("Ps. 23:1") == .valid(canonical: "Psalms 23:1", osis: "Ps.23.1"))
        #expect(validateSermonPassage("Pss 119:105") == .valid(canonical: "Psalms 119:105", osis: "Ps.119.105"))
        #expect(validateSermonPassage("Jude 4") == .valid(canonical: "Jude 1:4", osis: "Jude.1.4"))
        #expect(validateSermonPassage("Hebrews 8-10") == .valid(canonical: "Hebrews 8-10", osis: "Heb.8-Heb.10"))
        #expect(validateSermonPassage("1 Corinthians 13:4-7") == .valid(canonical: "1 Corinthians 13:4-7", osis: "1Cor.13.4-1Cor.13.7"))
    }

    @Test func invalidReferencesProduceAnErrorInsteadOfSilentlyDropping() {
        for bad in ["Not a book 1:1", "Romans 99:1", "Jude 2:1", "Psalm 151:1", "Genesis 0:1", "Romans", "hello", String(repeating: "Romans 8:28 ", count: 5)] {
            if case .invalid(let msg) = validateSermonPassage(bad) {
                #expect(!msg.isEmpty)
            } else {
                Issue.record("Expected invalid for \(bad)")
            }
        }
    }
}

@Suite struct SermonDetailsReadFlagsTests {
    @Test func marksOnlyFieldsReadFromNotesThatStillMatch() {
        let extracted = SermonDetails(title: "To the Church at Smyrna", preacher: "Rev. Ross Hodges", passage: "Revelation 2:8-11", church: nil, serviceDate: "2026-11-22")
        let flags = extracted.readFlags(
            title: "To the Church at Smyrna",
            preacher: "Rev. Other",
            passage: "Revelation 2:8–11",
            church: "Grace Presbyterian",
            serviceDate: day("2026-11-22"),
            calendar: utc
        )
        #expect(flags.title)
        #expect(!flags.preacher)
        #expect(flags.passage)
        #expect(!flags.church)
        #expect(flags.serviceDate)
    }
}

@Suite @MainActor struct UpdateSermonDetailsTests {
    @Test func updatesAllFieldsCanonicalizesPassageAndEnqueuesSync() throws {
        let container = try ModelContainer(for: progressSchema, configurations: ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true))
        var localWrites = 0
        let store = LordsDayStore(context: container.mainContext, syncSubject: "sub-1", onLocalWrite: { localWrites += 1 })
        let note = LordsDayNote(serviceDate: day("2026-11-15"), sermonTitle: "Old")
        try store.save(note)
        let before = note.updatedAt

        try store.updateDetails(SermonDetailsEdit(
            title: "  To the Church at Smyrna  ",
            preacher: "Rev. Ross Hodges",
            passage: "Revelation 2:8–11",
            church: "Grace Presbyterian",
            serviceDate: day("2026-11-22")
        ), for: note)

        #expect(note.sermonTitle == "To the Church at Smyrna")
        #expect(note.preacher == "Rev. Ross Hodges")
        #expect(note.passageRef == "Revelation 2:8-11")
        #expect(note.church == "Grace Presbyterian")
        #expect(note.serviceDate == day("2026-11-22"))
        #expect(note.updatedAt > before)
        #expect(localWrites == 2)
    }

    @Test func rejectsInvalidPassageWithoutModifyingTheNote() throws {
        let container = try ModelContainer(for: progressSchema, configurations: ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true))
        let store = LordsDayStore(context: container.mainContext)
        let note = LordsDayNote(serviceDate: day("2026-11-15"), passageRef: "Romans 8:28", sermonTitle: "Kept")
        try store.save(note)

        #expect(throws: LordsDayError.invalidPassage) {
            try store.updateDetails(SermonDetailsEdit(
                title: "Changed",
                preacher: nil,
                passage: "Romans 99:1",
                church: nil,
                serviceDate: day("2026-11-22")
            ), for: note)
        }
        #expect(note.sermonTitle == "Kept")
        #expect(note.passageRef == "Romans 8:28")
    }
}

// TKL-1085 (2026-11-28): a single capture is dated by the notes, then the photos, then last Sunday.
@Suite struct SingleCaptureDateTests {
    private func note(createdOn created: String) -> LordsDayNote {
        let createdAt = day(created).addingTimeInterval(15 * 3600)
        return LordsDayNote(serviceDate: lastSunday(onOrBefore: createdAt, calendar: utc), createdAt: createdAt, updatedAt: createdAt)
    }
    private let noDetails = SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: nil)

    @Test func photosFromTheLibraryDateTheNoteNotTheUploadDay() {
        let n = note(createdOn: "2026-11-26") // a Thursday; the default is Sun 22 Nov
        let before = n.updatedAt
        // Two pages, taken on Sun 1 Nov and Mon 2 Nov: the earliest page wins.
        #expect(n.dateFromPhotos([day("2026-11-02"), nil, day("2026-11-01").addingTimeInterval(11 * 3600)], calendar: utc))
        #expect(n.serviceDate == day("2026-11-01"))
        #expect(n.updatedAt > before)
        #expect(!n.serviceDateIsGuess(photoDates: [day("2026-11-01")], calendar: utc))
    }

    @Test func aDateReadFromTheNotesStillWinsOverThePhotoDate() {
        let n = note(createdOn: "2026-11-26")
        let photos = [day("2026-11-03")]
        _ = n.dateFromPhotos(photos, calendar: utc)
        #expect(n.serviceDate == day("2026-11-01"))
        _ = n.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: "2026-10-25"), photoDates: photos, calendar: utc)
        #expect(n.serviceDate == day("2026-10-25"))
    }

    @Test func aNotesDateNearOldPhotosIsNotRejectedAsImplausible() {
        // Photos from two years back, notes naming that Sunday: the window follows the photos.
        let n = note(createdOn: "2026-11-26")
        let photos = [day("2024-09-17")]
        _ = n.dateFromPhotos(photos, calendar: utc)
        #expect(n.serviceDate == day("2024-09-15"))
        _ = n.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: "2024-09-08"), photoDates: photos, calendar: utc)
        #expect(n.serviceDate == day("2024-09-08"))
    }

    @Test func withNeitherItIsLastSundayAndSaysItIsAGuess() {
        let n = note(createdOn: "2026-11-26")
        #expect(!n.dateFromPhotos([nil, nil], calendar: utc))
        #expect(n.serviceDate == day("2026-11-22"))
        #expect(n.serviceDateIsGuess(photoDates: [nil, nil], calendar: utc))
        #expect(n.serviceDateIsGuess(photoDates: [], calendar: utc), "typed notes have no photo date")
        _ = n.fill(with: noDetails, photoDates: [], calendar: utc)
        #expect(n.serviceDate == day("2026-11-22"))
    }

    @Test func aDateThePersonChoseIsNeitherMovedByPhotosNorAGuess() {
        let n = note(createdOn: "2026-11-26")
        n.serviceDate = day("2026-11-15")
        #expect(!n.dateFromPhotos([day("2026-11-01")], calendar: utc))
        #expect(n.serviceDate == day("2026-11-15"))
        #expect(!n.serviceDateIsGuess(photoDates: [], calendar: utc))
        _ = n.fill(with: SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: "2026-10-25"), photoDates: [day("2026-11-01")], calendar: utc)
        #expect(n.serviceDate == day("2026-11-15"))
    }

    @Test func aPhotoClockInTheFutureIsPassedOver() {
        let n = note(createdOn: "2026-11-26")
        #expect(!n.dateFromPhotos([day("2027-03-01")], now: day("2026-11-26"), calendar: utc))
        #expect(n.serviceDate == day("2026-11-22"))
    }
}
