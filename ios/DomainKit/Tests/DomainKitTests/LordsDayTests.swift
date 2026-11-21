import Foundation
import SwiftData
import XCTest
@testable import DomainKit

@MainActor final class LordsDayTests: XCTestCase {
    func testStoreAndVerseValidation() throws {
        let container = try ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let note = LordsDayNote(serviceDate: date)
        try store.save(note)
        let first = try store.appendCard(to: note, kind: .keyPoint, body: "point")
        let second = try store.appendCard(to: note, kind: .quote, body: "quote")
        XCTAssertThrowsError(try store.appendCard(to: note, kind: .verse, body: "generated", verseRef: "John 1:1"))
        let verse = try store.appendCard(to: note, kind: .verse, body: "", verseRef: "John 1:1")
        XCTAssertThrowsError(try store.editBody(of: verse, body: "generated"))
        try store.reorderCards(for: note, cards: [second, first, verse])
        try store.editBody(of: first, body: "edited")
        try store.switchKind(of: second, to: .verse, verseRef: "John 3:16")
        XCTAssertEqual(second.body, "")
        try store.removeCard(first)
        XCTAssertNotNil(first.deletedAt)
        XCTAssertEqual(try store.cards(for: note).map(\.id), [second.id, verse.id])
        XCTAssertEqual(try store.currentWeek(on: date)?.id, note.id)
        XCTAssertEqual(try store.archive(before: date.addingTimeInterval(8 * 86400)).map(\.id), [note.id])
    }

    func testSavedNoteSurvivesReopening() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let config = ModelConfiguration(schema: progressSchema, url: url)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let container = try ModelContainer(for: progressSchema, configurations: [config])
            let store = LordsDayStore(context: ModelContext(container))
            let note = LordsDayNote(serviceDate: date)
            try store.save(note)
            try store.appendCard(to: note, kind: .quote, body: "remember")
        }
        let reopened = try ModelContainer(for: progressSchema, configurations: [config])
        let store = LordsDayStore(context: ModelContext(reopened))
        let note = try XCTUnwrap(store.currentWeek(on: date))
        XCTAssertEqual(try store.cards(for: note).map(\.body), ["remember"])
    }

    func testTodayCardBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: sunday)! }
        XCTAssertNil(todayCardIndex(serviceDate: sunday, today: day(0), cardCount: 0, calendar: calendar))
        XCTAssertEqual(todayCardIndex(serviceDate: sunday, today: day(0), cardCount: 2, calendar: calendar), 0)
        XCTAssertEqual(todayCardIndex(serviceDate: sunday, today: day(1), cardCount: 2, calendar: calendar), 0)
        XCTAssertEqual(todayCardIndex(serviceDate: sunday, today: day(6), cardCount: 2, calendar: calendar), 1)
        XCTAssertNil(todayCardIndex(serviceDate: sunday, today: day(7), cardCount: 2, calendar: calendar))
        XCTAssertNil(todayCardIndex(serviceDate: sunday, today: day(-1), cardCount: 2, calendar: calendar))
    }
}

// TKL-859: the app is live, so adding the Lord's Day models must be additive.
// A store written with progressSchema as it stands on origin/main (no Lord's
// Day models) must open with this container and keep every record.
@MainActor final class LordsDayUpgradeTests: XCTestCase {
    func testStoreWithoutLordsDayModelsOpensAndKeepsEveryRecord() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tkl859-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Progress.sqlite")

        let mainSchema = Schema([
            LocalCatechismTrack.self, ProgressSettings.self, LocalChild.self, ChildCatechismTrack.self,
        ] + syncModelTypes)
        XCTAssertFalse(mainSchema.entities.map(\.name).contains("LordsDayNote"))

        let started = Date(timeIntervalSince1970: 100)
        let milestones = [
            "3": MilestoneRecord(state: "mastered", introducedAt: started, reviewCount: 8),
            "4": MilestoneRecord(state: "reviewing", introducedAt: started, reviewCount: 2),
        ]
        let firstId: UUID, secondId: UUID
        do {
            let old = try ModelContainer(for: mainSchema, configurations: [ModelConfiguration(schema: mainSchema, url: url)])
            let store = LocalProgressStore(context: old.mainContext)
            let first = try store.addChild(name: "Samuel", age: 7)
            let second = try store.addChild(name: "Hannah")
            firstId = first.id; secondId = second.id
            let wsc = try XCTUnwrap(store.startTrack(childId: first.id, catechismId: "WSC", startingQuestion: 3))
            wsc.milestones = milestones
            wsc.currentQuestion = 9
            _ = try XCTUnwrap(store.startTrack(childId: second.id, catechismId: "HC", startingQuestion: 1))
            old.mainContext.insert(SyncOutboxEntry(sequence: 1, table: "children", rowId: first.id.uuidString,
                                                   payload: Data("{}".utf8), updatedAt: started, deletedAt: nil))
            old.mainContext.insert(SyncCursorRecord(table: "children", changeId: 42))
            try old.mainContext.save()
        }

        let upgraded = try openProgressContainer(at: url)
        let context = upgraded.mainContext
        let progress = LocalProgressStore(context: context)
        XCTAssertEqual(progress.activeChildId, firstId)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<LocalChild>()).map(\.id)), [firstId, secondId])
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalChild>()).first { $0.id == firstId }?.age, 7)
        let wsc = try XCTUnwrap(progress.activeTrack(childId: firstId))
        XCTAssertEqual(wsc.catechismId, "WSC")
        XCTAssertEqual(wsc.currentQuestion, 9)
        XCTAssertEqual(wsc.startedAtQuestion, 3)
        XCTAssertEqual(wsc.milestones, milestones)
        XCTAssertEqual(progress.activeTrack(childId: secondId)?.catechismId, "HC")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChildCatechismTrack>()), 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).map(\.rowId), [firstId.uuidString])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncCursorRecord>()).map(\.changeId), [42])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LordsDayNote>()), 0)

        // The new tables are usable in the upgraded store.
        let lordsDay = LordsDayStore(context: context)
        let note = LordsDayNote(serviceDate: started)
        try lordsDay.save(note)
        try lordsDay.appendCard(to: note, kind: .verse, body: "", verseRef: "Psalm 1:1")
        XCTAssertEqual(try lordsDay.cards(for: note).map(\.verseRef), ["Psalm 1:1"])
    }
}
