import Foundation
import SwiftData
import XCTest
@testable import DomainKit

/// TKL-860: photographing Sunday's notes. Pages live in files on the device,
/// never in the note record, and survive the app being killed mid-capture.
final class LordsDayCaptureTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func jpeg(_ byte: UInt8) -> Data { Data([0xFF, 0xD8, byte, 0xFF, 0xD9]) }

    func testPagesKeepOrderAndCanBeRetakenOrRemoved() throws {
        let noteId = UUID()
        let draft = try CaptureDraft(noteId: noteId, root: root)
        let first = try draft.addPage(jpeg(1))
        let second = try draft.addPage(jpeg(2))
        let third = try draft.addPage(jpeg(3))
        XCTAssertEqual(draft.pages.map(\.id), [first, second, third])

        try draft.retakePage(second, with: jpeg(9))
        XCTAssertEqual(draft.pages.map(\.id), [first, second, third], "a retake keeps the page in its place")
        XCTAssertEqual(try draft.data(for: second), jpeg(9))

        try draft.removePage(first)
        XCTAssertEqual(draft.pages.map(\.id), [second, third])
        XCTAssertEqual(try draft.pageData(), [jpeg(9), jpeg(3)])
        XCTAssertThrowsError(try draft.data(for: first))
    }

    func testDraftSurvivesTheAppBeingKilled() throws {
        let noteId = UUID()
        do {
            let draft = try CaptureDraft(noteId: noteId, root: root)
            try draft.addPage(jpeg(1))
            try draft.addPage(jpeg(2))
            try CaptureDraft.setActive(noteId, root: root)
        }
        // A fresh process: nothing in memory, only what is on disk.
        XCTAssertEqual(try CaptureDraft.activeNoteId(root: root), noteId)
        let reopened = try CaptureDraft(noteId: noteId, root: root)
        XCTAssertEqual(try reopened.pageData(), [jpeg(1), jpeg(2)])

        try CaptureDraft.setActive(nil, root: root)
        XCTAssertNil(try CaptureDraft.activeNoteId(root: root))
        XCTAssertEqual(try CaptureDraft(noteId: noteId, root: root).pages.count, 2, "finishing capture keeps the pages for the generator")
    }

    func testPageLimitMatchesTheGenerator() throws {
        let draft = try CaptureDraft(noteId: UUID(), root: root)
        for i in 0..<CaptureDraft.maxPages { try draft.addPage(jpeg(UInt8(i))) }
        XCTAssertFalse(draft.canAddPage)
        XCTAssertThrowsError(try draft.addPage(jpeg(99)))
        XCTAssertEqual(CaptureDraft.maxPages, 6)
    }

    func testDiscardDeletesThePhotos() throws {
        let noteId = UUID()
        let draft = try CaptureDraft(noteId: noteId, root: root)
        try draft.addPage(jpeg(1))
        try draft.discard()
        XCTAssertEqual(try CaptureDraft(noteId: noteId, root: root).pages.count, 0)
    }

    @MainActor func testNoteSavesWithAPhotoAndNothingElseAndKeepsNoImage() throws {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let note = LordsDayNote(serviceDate: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(note)
        let draft = try CaptureDraft(noteId: note.id, root: root)
        try draft.addPage(jpeg(1))

        XCTAssertTrue(CaptureContent(pageCount: draft.pages.count, typedText: note.extractedText).canFinish)
        XCTAssertNil(note.passageRef); XCTAssertNil(note.sermonTitle); XCTAssertNil(note.preacher)
        // The note record has no field that could hold image bytes.
        let attributes = Schema([LordsDayNote.self]).entitiesByName["LordsDayNote"]!.attributes
        XCTAssertFalse(attributes.contains { $0.valueType == Data.self || $0.valueType == Optional<Data>.self })
    }

    func testCaptureCanFinishWithPagesOrTypedText() {
        XCTAssertFalse(CaptureContent(pageCount: 0, typedText: nil).canFinish)
        XCTAssertFalse(CaptureContent(pageCount: 0, typedText: "  \n").canFinish)
        XCTAssertTrue(CaptureContent(pageCount: 0, typedText: "Grace precedes faith").canFinish)
        XCTAssertTrue(CaptureContent(pageCount: 2, typedText: nil).canFinish)
    }

    func testOptionalFieldsNormalizeToNil() {
        XCTAssertNil(normalizedNoteField("   "))
        XCTAssertNil(normalizedNoteField(nil))
        XCTAssertEqual(normalizedNoteField("  Romans 8:28 "), "Romans 8:28")
    }

    // MARK: - The generator call (POST /api/lords-day/cards)

    private func decode(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPhotoRequestSendsPagesAsBase64JPEG() throws {
        let body = try decode(LordsDayCardsRequest(pages: [jpeg(1), jpeg(2)], typedText: nil, passage: " Rom 8:28 ", title: "", preacher: nil).body())
        let images = try XCTUnwrap(body["images"] as? [[String: String]])
        XCTAssertEqual(images.map { $0["mimeType"] }, ["image/jpeg", "image/jpeg"])
        XCTAssertEqual(images.map { $0["data"] }, [jpeg(1).base64EncodedString(), jpeg(2).base64EncodedString()])
        XCTAssertNil(body["extractedText"])
        XCTAssertEqual(body["passage"] as? String, "Rom 8:28")
        XCTAssertNil(body["title"]); XCTAssertNil(body["preacher"])
    }

    func testTypedRequestSendsTheSameExtractedText() throws {
        let body = try decode(LordsDayCardsRequest(pages: [], typedText: "Called, justified, glorified", passage: nil, title: nil, preacher: "Rev. Smith").body())
        XCTAssertEqual(body["extractedText"] as? String, "Called, justified, glorified")
        XCTAssertNil(body["images"])
        XCTAssertEqual(body["preacher"] as? String, "Rev. Smith")
    }

    func testPhotosWinOverTypedTextAndEmptyIsRejected() throws {
        let body = try decode(LordsDayCardsRequest(pages: [jpeg(1)], typedText: "also typed", passage: nil, title: nil, preacher: nil).body())
        XCTAssertNotNil(body["images"]); XCTAssertNil(body["extractedText"], "the endpoint takes exactly one of the two")
        XCTAssertThrowsError(try LordsDayCardsRequest(pages: [], typedText: " ", passage: nil, title: nil, preacher: nil).body())
    }

    func testRequestRefusesMorePagesOrBytesThanTheEndpointTakes() {
        XCTAssertThrowsError(try LordsDayCardsRequest(pages: Array(repeating: jpeg(1), count: 7), typedText: nil, passage: nil, title: nil, preacher: nil).body())
        let big = Data(repeating: 7, count: 3_100_000) // base64 grows it past 4 MB
        XCTAssertThrowsError(try LordsDayCardsRequest(pages: [big], typedText: nil, passage: nil, title: nil, preacher: nil).body())
    }
}
