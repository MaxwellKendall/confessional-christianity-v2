import Foundation
import XCTest
@testable import DomainKit

/// TKL-1107: many sermons' photos at once. Pages are read in chunks through the
/// existing cards call, grouped into sermons (SermonGrouping), dated, and each
/// group becomes its own note with its own pending review.
final class LordsDayBatchImportTests: XCTestCase {
    private var root: URL!
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func jpeg(_ byte: UInt8) -> Data { Data([0xFF, 0xD8, byte, 0xFF, 0xD9]) }
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    private func sermon(title: String? = nil, passage: String? = nil, date: String? = nil) -> SermonDetails {
        SermonDetails(title: title, preacher: nil, passage: passage, church: nil, serviceDate: date)
    }
    private func page(_ title: String? = nil, passage: String? = nil, date: String? = nil, at takenAt: Date? = nil) -> GroupingPage {
        GroupingPage(id: UUID(), takenAt: takenAt, sermon: sermon(title: title, passage: passage, date: date))
    }
    private func indexGroups(_ grouping: SermonGrouping, _ pages: [GroupingPage]) -> [[Int]] {
        grouping.groups.map { group in group.pageIds.map { id in pages.firstIndex { $0.id == id }! } }
    }

    func testMoveToNewGroupAndBackRemovesEmptyGroup() {
        let pages = [page(), page(), page()]
        var grouping = SermonGrouping.propose(pages)
        let original = grouping.groups[0].id
        grouping.moveToNewGroup(pages[0].id)
        XCTAssertEqual(indexGroups(grouping, pages), [[1, 2], [0]])
        grouping.move(pages[0].id, to: original)
        XCTAssertEqual(indexGroups(grouping, pages), [[0, 1, 2]])
    }

    func testEditingGuessedDatePersistsThroughBatchReview() throws {
        let draft = try BatchImportDraft(root: root)
        try draft.addPage(jpeg(1), takenAt: nil)
        let group = try XCTUnwrap(draft.proposeGroups().groups.first)
        let now = day(2026, 11, 28)
        let chosenDay = day(2026, 11, 15, 0)
        XCTAssertTrue(draft.date(of: group, now: now, calendar: calendar).isGuess)

        let edit = SermonDetailsEdit(title: "A remembered sermon", preacher: nil, passage: nil, church: nil, serviceDate: chosenDay)
        try draft.setDetails(edit, for: group.id)
        let reopened = try BatchImportDraft(root: root)
        XCTAssertEqual(reopened.editedDetails(for: group.id), edit)
        let made = try reopened.materialize(group, now: now, calendar: calendar)
        XCTAssertEqual(made.date.date, chosenDay)
        XCTAssertFalse(made.date.isGuess)
        XCTAssertEqual(made.sermon?.title, edit.title)
    }

    // MARK: The request plan

    func testTwentyPagesAreReadInFourChunksWithNoSermonMetadata() throws {
        let draft = try BatchImportDraft(root: root)
        for i in 0..<20 { try draft.addPage(jpeg(UInt8(i)), takenAt: nil) }
        XCTAssertEqual(draft.chunks, [0..<6, 6..<12, 12..<18, 18..<20])
        for chunk in draft.chunks {
            let body = try draft.request(for: chunk).body()
            let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            XCTAssertEqual((json["images"] as? [Any])?.count, chunk.count)
            for key in ["title", "preacher", "passage", "extractedText"] { XCTAssertNil(json[key], key) }
        }
    }

    func testABatchTakesUpToThirtyPhotos() throws {
        let draft = try BatchImportDraft(root: root)
        for i in 0..<BatchImportDraft.maxPhotos { try draft.addPage(jpeg(UInt8(i)), takenAt: nil) }
        XCTAssertEqual(BatchImportDraft.maxPhotos, 30)
        XCTAssertFalse(draft.canAddPage)
        XCTAssertThrowsError(try draft.addPage(jpeg(99), takenAt: nil))
    }

    func testAChunkIsRecordedOnlyOnceItIsDoneAndAFailedPageIsMarked() throws {
        let draft = try BatchImportDraft(root: root)
        for i in 0..<8 { try draft.addPage(jpeg(UInt8(i)), takenAt: nil) }
        var reader = BatchChunkReader(chunk: 6..<8)
        reader.apply(.started(pages: 2))
        reader.apply(.page(0, cardCount: 1, extractedText: "Rom 8", generationId: "g1"))
        reader.apply(.sermon(0, sermon(title: "Golden Chain")))
        reader.apply(.card(DraftCardPayload(kind: "key_point", page: 0, order: 0, text: "No weak link.")))
        XCTAssertFalse(reader.isDone)
        reader.apply(.pageFailed(1))
        reader.apply(.done(failedPages: [1]))
        XCTAssertTrue(reader.isDone)
        try draft.record(reader)
        XCTAssertEqual(draft.pages[6].read?.sermon?.title, "Golden Chain")
        XCTAssertEqual(draft.pages[6].read?.cards.count, 1)
        XCTAssertEqual(draft.pages[7].read?.failed, true)
        XCTAssertEqual(draft.pendingChunks, [0..<6], "a failed page is read (and retried in its sermon's review), not pending")
    }

    func testKilledAfterTwoOfFourChunksResumesTheOtherTwo() throws {
        do {
            let draft = try BatchImportDraft(root: root)
            for i in 0..<20 { try draft.addPage(jpeg(UInt8(i)), takenAt: nil) }
            for chunk in draft.chunks.prefix(2) { try draft.record(Self.readChunk(chunk)) }
            // A third chunk was streaming when the app was killed: nothing of it is recorded.
            var partial = BatchChunkReader(chunk: draft.chunks[2])
            partial.apply(.page(0, cardCount: 0, extractedText: "x", generationId: nil))
            XCTAssertThrowsError(try draft.record(partial))
        }
        let resumed = try BatchImportDraft(root: root)
        XCTAssertEqual(resumed.pages.count, 20)
        XCTAssertEqual(resumed.pendingChunks, [12..<18, 18..<20])
        XCTAssertEqual(try resumed.data(for: resumed.pages[19].id), jpeg(19))
    }

    // MARK: Grouping

    func testAHeadingChangeStartsANewSermon() {
        let pages = [page("Gospel Partnership"), page(), page("A Tale of Two Prayers"), page()]
        XCTAssertEqual(indexGroups(.propose(pages), pages), [[0, 1], [2, 3]])
    }

    func testADateChangeStartsANewSermon() {
        let pages = [page(date: "2020-09-06"), page(), page(date: "2020-09-20")]
        XCTAssertEqual(indexGroups(.propose(pages), pages), [[0, 1], [2]])
    }

    func testTheSameTitleOrDateContinuesTheSermon() {
        let pages = [page("Benediction", date: "2020-07-26"), page("benediction."), page(date: "2020-07-26")]
        XCTAssertEqual(indexGroups(.propose(pages), pages), [[0, 1, 2]])
    }

    func testAPassageChangeStartsANewSermon() {
        let pages = [page("Rules for Walking", passage: "Psalms 1"), page(passage: "Malachi 1:2-5")]
        XCTAssertEqual(indexGroups(.propose(pages), pages), [[0], [1]])
    }

    func testATimestampGapStartsANewSermon() {
        let sunday = day(2026, 11, 1, 11)
        let pages = [page(at: sunday), page(at: sunday.addingTimeInterval(120)),
                     page(at: sunday.addingTimeInterval(7 * 86_400))]
        XCTAssertEqual(indexGroups(.propose(pages), pages), [[0, 1], [2]])
        let shortGap = [page(at: sunday), page(at: sunday.addingTimeInterval(5 * 3600))]
        XCTAssertEqual(indexGroups(.propose(shortGap), shortGap), [[0, 1]], "under 6 hours is the same sitting")
    }

    func testAPageWithNothingReadJoinsThePreviousGroup() {
        let pages = [page("Triumph of the Lamb"), GroupingPage(id: UUID(), takenAt: nil, sermon: nil), page()]
        XCTAssertEqual(indexGroups(.propose(pages), pages), [[0, 1, 2]])
    }

    func testMoveSplitAndMerge() throws {
        let pages = (0..<5).map { _ in page() }
        var grouping = SermonGrouping(order: pages.map(\.id), groups: [
            SermonGroup(pageIds: [pages[0].id, pages[1].id, pages[2].id]),
            SermonGroup(pageIds: [pages[3].id, pages[4].id]),
        ])
        let second = grouping.groups[1].id

        grouping.move(pages[2].id, to: second)
        XCTAssertEqual(indexGroups(grouping, pages), [[0, 1], [2, 3, 4]], "a moved page takes its place in batch order")
        XCTAssertEqual(grouping.groups[1].id, second)

        grouping.split(second, at: pages[3].id)
        XCTAssertEqual(indexGroups(grouping, pages), [[0, 1], [2], [3, 4]])

        grouping.merge(grouping.groups[1].id, into: grouping.groups[0].id)
        XCTAssertEqual(indexGroups(grouping, pages), [[0, 1, 2], [3, 4]])

        grouping.move(pages[3].id, to: grouping.groups[0].id)
        grouping.move(pages[4].id, to: grouping.groups[0].id)
        XCTAssertEqual(indexGroups(grouping, pages), [[0, 1, 2, 3, 4]], "an emptied group goes away")
    }

    func testAGroupPastSixPagesMustBeSplitBeforeContinuing() {
        let pages = (0..<7).map { _ in page() }
        var grouping = SermonGrouping.propose(pages)
        XCTAssertEqual(grouping.oversizedGroups, [grouping.groups[0].id])
        XCTAssertFalse(grouping.canContinue)
        grouping.split(grouping.groups[0].id, at: pages[6].id)
        XCTAssertTrue(grouping.canContinue)
    }

    /// The offline eval (evals/lords-day-cards/grouping.json), scored by the same rule as the TS port.
    func testGroupingEvalCasesFromRecordedPageEvents() throws {
        struct Eval: Decodable {
            struct Page: Decodable { let `case`: String; let takenAt: Date? }
            struct Batch: Decodable { let id: String; let pages: [Page]; let truth: [[Int]] }
            let gapHours: Double
            let recorded: [String: SermonDetails]
            let batches: [Batch]
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("evals/lords-day-cards/grouping.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let eval = try decoder.decode(Eval.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(eval.batches.count, 3)
        for batch in eval.batches {
            let pages = batch.pages.map { GroupingPage(id: UUID(), takenAt: $0.takenAt, sermon: eval.recorded[$0.case]) }
            let grouping = SermonGrouping.propose(pages, gap: eval.gapHours * 3600)
            XCTAssertEqual(indexGroups(grouping, pages), batch.truth, batch.id)
        }
    }

    // MARK: Dates

    func testADateReadFromTheNotesWins() {
        let now = day(2026, 11, 28)
        let resolved = resolveServiceDate(readDate: "2020-09-20", photoDates: [day(2026, 11, 3)], now: now, calendar: calendar)
        XCTAssertEqual(resolved, ServiceDateResolution(date: calendar.startOfDay(for: day(2020, 9, 20)), source: .notes))
        XCTAssertFalse(resolved.isGuess)
    }

    func testOtherwiseTheSundayOnOrBeforeTheEarliestPhoto() {
        let now = day(2026, 11, 28)
        // Wednesday Nov 11 and Tuesday Nov 10: the earliest is Tuesday, whose Sunday is Nov 8.
        let resolved = resolveServiceDate(readDate: nil, photoDates: [day(2026, 11, 11), nil, day(2026, 11, 10)], now: now, calendar: calendar)
        XCTAssertEqual(resolved, ServiceDateResolution(date: calendar.startOfDay(for: day(2026, 11, 8)), source: .photo))
        let future = resolveServiceDate(readDate: "2027-01-03", photoDates: [day(2026, 11, 11)], now: now, calendar: calendar)
        XCTAssertEqual(future.source, .photo, "a date after today is a misread")
    }

    func testOtherwiseLastSundayIsAGuess() {
        let now = day(2026, 11, 28)
        let resolved = resolveServiceDate(readDate: "not a date", photoDates: [nil], now: now, calendar: calendar)
        XCTAssertEqual(resolved, ServiceDateResolution(date: calendar.startOfDay(for: day(2026, 11, 22)), source: .guess))
        XCTAssertTrue(resolved.isGuess)
    }

    func testPhotoTakenAtReadsExifDateTimeOriginal() throws {
        XCTAssertNil(photoTakenAt(jpeg(1), calendar: calendar))
        let date = parseExifDate("2026:11:08 10:42:05", calendar: calendar)
        XCTAssertEqual(date, calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 10, minute: 42, second: 5)))
    }

    // MARK: One note per group

    private static func readChunk(_ chunk: Range<Int>, sermons: [Int: SermonDetails] = [:], failed: Set<Int> = []) -> BatchChunkReader {
        var reader = BatchChunkReader(chunk: chunk)
        reader.apply(.started(pages: chunk.count))
        for (i, batchIndex) in chunk.enumerated() {
            if failed.contains(batchIndex) { reader.apply(.pageFailed(i)); continue }
            reader.apply(.page(i, cardCount: 2, extractedText: "page \(batchIndex)", generationId: "gen-\(batchIndex)"))
            if let s = sermons[batchIndex] { reader.apply(.sermon(i, s)) }
            reader.apply(.card(DraftCardPayload(kind: "key_point", page: i, order: 0, text: "Point from page \(batchIndex).", sourceKey: "gen-\(batchIndex):0")))
            reader.apply(.card(DraftCardPayload(kind: "verse", page: i, order: 1, reference: "Romans 8:28", osis: "Rom.8.28", sourceKey: "gen-\(batchIndex):1")))
        }
        reader.apply(.done(failedPages: chunk.enumerated().filter { failed.contains($0.element) }.map(\.offset)))
        return reader
    }

    func testEachGroupBecomesItsOwnReviewWithItsOwnPages() throws {
        let draft = try BatchImportDraft(root: root)
        for i in 0..<5 { try draft.addPage(jpeg(UInt8(i)), takenAt: nil) }
        try draft.record(Self.readChunk(0..<5, sermons: [0: sermon(title: "Triumph of the Lamb", date: "2020-09-20"), 3: sermon(title: "Gospel Partnership")], failed: [4]))
        let grouping = try draft.proposeGroups()
        XCTAssertEqual(grouping.groups.map(\.pageIds.count), [3, 2])

        let now = day(2026, 11, 28)
        let first = try draft.materialize(grouping.groups[0], now: now, calendar: calendar)
        XCTAssertEqual(first.noteId, grouping.groups[0].id)
        XCTAssertEqual(first.sermon?.title, "Triumph of the Lamb")
        XCTAssertEqual(first.date.source, .notes)
        XCTAssertEqual(try CaptureDraft(noteId: first.noteId, root: root).pageData(), [jpeg(0), jpeg(1), jpeg(2)])
        let review = try XCTUnwrap(try LordsDayReview.load(noteId: first.noteId, root: root))
        XCTAssertEqual(review.phase, .ready)
        XCTAssertEqual(review.pageCount, 3)
        XCTAssertEqual(review.readPages, [0, 1, 2])
        XCTAssertEqual(review.cards.map(\.page), [0, 0, 1, 1, 2, 2], "cards are renumbered to the note's pages")
        XCTAssertEqual(review.cards[2].words, "Point from page 1.")
        XCTAssertFalse(review.dateIsGuess)

        let second = try draft.materialize(grouping.groups[1], now: now, calendar: calendar)
        let secondReview = try XCTUnwrap(try LordsDayReview.load(noteId: second.noteId, root: root))
        XCTAssertEqual(secondReview.failedPages, [1], "a page that failed in the batch is retried in its own review")
        XCTAssertTrue(secondReview.canRetry)
        XCTAssertEqual(second.date.source, .guess)
        XCTAssertTrue(secondReview.dateIsGuess)
    }

    func testKilledAfterTwoOfFourGroupsTheOtherTwoAreStillPending() throws {
        let sunday = day(2026, 11, 1, 11)
        let ids: [UUID]
        do {
            let draft = try BatchImportDraft(root: root)
            for i in 0..<8 { try draft.addPage(jpeg(UInt8(i)), takenAt: sunday.addingTimeInterval(Double(i / 2) * 7 * 86_400)) }
            for chunk in draft.chunks { try draft.record(Self.readChunk(chunk)) }
            let grouping = try draft.proposeGroups()
            XCTAssertEqual(grouping.groups.count, 4)
            ids = grouping.groups.map(\.id)
            for group in grouping.groups.prefix(2) {
                _ = try draft.materialize(group, now: day(2026, 11, 28), calendar: calendar)
                try draft.markMaterialized(group.id)
            }
            // The third was being written when the app was killed: files, but not marked.
            _ = try draft.materialize(grouping.groups[2], now: day(2026, 11, 28), calendar: calendar)
        }
        let resumed = try BatchImportDraft(root: root)
        XCTAssertEqual(resumed.pendingGroups.map(\.id), Array(ids.suffix(2)))
        for (offset, id) in ids.enumerated() {
            let pages = try CaptureDraft(noteId: id, root: root).pageData()
            if offset < 3 { XCTAssertEqual(pages, [jpeg(UInt8(offset * 2)), jpeg(UInt8(offset * 2 + 1))]) }
        }
        // Writing a group again is harmless: same pages, no duplicates.
        let again = try resumed.materialize(resumed.pendingGroups[0], now: day(2026, 11, 28), calendar: calendar)
        XCTAssertEqual(try CaptureDraft(noteId: again.noteId, root: root).pages.count, 2)
        XCTAssertEqual(again.date, ServiceDateResolution(date: calendar.startOfDay(for: day(2026, 11, 15)), source: .photo))
        try resumed.markMaterialized(ids[2])
        let last = try resumed.materialize(resumed.pendingGroups[0], now: day(2026, 11, 28), calendar: calendar)
        try resumed.markMaterialized(last.noteId)
        XCTAssertTrue(resumed.pendingGroups.isEmpty)
        try resumed.discard()
        XCTAssertFalse(BatchImportDraft.exists(root: root))
        XCTAssertEqual(try CaptureDraft(noteId: ids[3], root: root).pages.count, 2, "discarding the batch keeps each note's pages")
    }

    func testAnOldReviewFileWithoutTheGuessFlagStillLoads() throws {
        let review = LordsDayReview(noteId: UUID(), pageCount: 1)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as! [String: Any]
        json["dateIsGuess"] = nil
        let decoded = try JSONDecoder().decode(LordsDayReview.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.dateIsGuess)
    }
}
