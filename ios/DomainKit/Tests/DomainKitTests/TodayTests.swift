// TKL-825: the Today home screen's primary card. The rule: the active child's
// next catechism session, else today's day of the current sermon week. On a
// Sunday whose notes aren't captured yet, "photograph your notes" leads
// (decided by default in TKL-885's approved prototype). A new guest with
// nothing started gets the empty state.
import Foundation
import Testing
import SwiftData
@testable import DomainKit

private func child(
    _ name: String,
    q: Int = 1,
    practisedToday: Bool = false,
    finished: Bool = false
) -> TodayChild {
    TodayChild(
        id: UUID(),
        name: name,
        programSlug: "catechizing-shorter-catechism",
        programShortTitle: "Shorter Catechism",
        questionNumber: q,
        totalQuestions: 107,
        question: "Q\(q)",
        learned: q - 1,
        practisedToday: practisedToday,
        finished: finished
    )
}

private let thursday = TodaySermonDay(
    sermonTitle: "More than conquerors",
    countLabel: "4 of 7",
    kind: "Key point",
    text: "Nothing shall separate us.",
    attribution: "From my notes"
)

@Suite("Today planner")
struct TodayPlannerTests {
    @Test("a new guest with nothing started gets the empty state")
    func empty() {
        #expect(planToday(TodayInput(children: [], activeChildId: nil)) == .empty)
    }

    @Test("the active child's next session leads, other children and the sermon day follow")
    func activeChildFirst() {
        let samuel = child("Samuel", q: 9)
        let thomas = child("Thomas", q: 4)
        let plan = planToday(TodayInput(children: [samuel, thomas], activeChildId: thomas.id, sermonDay: thursday))
        #expect(plan == .plan(primary: .catechism(thomas), also: [.catechism(samuel), .sermonDay(thursday)]))
    }

    @Test("no active child set: the first child leads")
    func noActiveChild() {
        let samuel = child("Samuel")
        let thomas = child("Thomas")
        let plan = planToday(TodayInput(children: [samuel, thomas], activeChildId: nil))
        #expect(plan == .plan(primary: .catechism(samuel), also: [.catechism(thomas)]))
    }

    @Test("a child already practised today gives way to the next child still due")
    func practisedChildGivesWay() {
        let samuel = child("Samuel", q: 10, practisedToday: true)
        let thomas = child("Thomas", q: 4)
        let plan = planToday(TodayInput(children: [samuel, thomas], activeChildId: samuel.id, sermonDay: thursday))
        #expect(plan == .plan(primary: .catechism(thomas), also: [.catechism(samuel), .sermonDay(thursday)]))
    }

    @Test("every child done today: today's sermon day leads")
    func sermonDayWhenChildrenDone() {
        let samuel = child("Samuel", q: 10, practisedToday: true)
        let thomas = child("Thomas", q: 108, finished: true)
        let plan = planToday(TodayInput(children: [samuel, thomas], activeChildId: samuel.id, sermonDay: thursday))
        #expect(plan == .plan(primary: .sermonDay(thursday), also: [.catechism(samuel), .catechism(thomas)]))
    }

    @Test("no children but a sermon week: the sermon day leads")
    func sermonOnly() {
        #expect(planToday(TodayInput(children: [], activeChildId: nil, sermonDay: thursday))
            == .plan(primary: .sermonDay(thursday), also: []))
    }

    @Test("every child done and no sermon week: the active child stays as the (done) primary card")
    func allDoneNoSermon() {
        let samuel = child("Samuel", q: 10, practisedToday: true)
        let thomas = child("Thomas", q: 5, practisedToday: true)
        let plan = planToday(TodayInput(children: [samuel, thomas], activeChildId: thomas.id))
        #expect(plan == .plan(primary: .catechism(thomas), also: [.catechism(samuel)]))
    }

    @Test("Sunday with notes not captured: photographing them leads, the children follow")
    func sundayCapture() {
        let samuel = child("Samuel", q: 9)
        let plan = planToday(TodayInput(
            children: [samuel], activeChildId: samuel.id, sermonDay: thursday, sundayCaptureDue: true
        ))
        #expect(plan == .plan(primary: .captureSunday, also: [.catechism(samuel)]))
    }

    @Test("Sunday capture due counts as something started, even with no children")
    func sundayCaptureAlone() {
        #expect(planToday(TodayInput(children: [], activeChildId: nil, sundayCaptureDue: true))
            == .plan(primary: .captureSunday, also: []))
    }
}

@Suite("Today children from the progress store")
@MainActor
struct TodayChildrenTests {
    // The suite owns the container so SwiftData can't release it mid-test.
    let container: ModelContainer
    let store: LocalProgressStore

    init() throws {
        let config = ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: progressSchema, configurations: [config])
        store = LocalProgressStore(context: container.mainContext)
    }

    @Test("no children: empty list")
    func none() throws {
        #expect(store.todayChildren().isEmpty)
    }

    @Test("children in the order they were added, each at their own next question")
    func ordersAndMaps() throws {
        let samuel = try store.addChild(name: "Samuel")
        let thomas = try store.addChild(name: "Thomas")
        store.startTrack(childId: samuel.id, catechismId: "WSC", startingQuestion: 9)

        let rows = store.todayChildren()
        #expect(rows.map(\.name) == ["Samuel", "Thomas"])
        #expect(rows[0].id == samuel.id)
        #expect(rows[0].questionNumber == 9)
        #expect(rows[0].learned == 8)
        #expect(rows[0].question == "What is the work of creation?")
        #expect(rows[0].programSlug == "catechizing-shorter-catechism")
        #expect(rows[0].practisedToday == false)
        // A child with no track yet starts at Q. 1 of the Shorter Catechism.
        #expect(rows[1].id == thomas.id)
        #expect(rows[1].questionNumber == 1)
        #expect(rows[1].question == "What is the chief end of man?")
        #expect(rows[1].learned == 0)
    }

    @Test("advancing a question today marks the child practised today; yesterday's doesn't")
    func practisedToday() throws {
        let samuel = try store.addChild(name: "Samuel")
        store.startTrack(childId: samuel.id, catechismId: "WSC", startingQuestion: 1)
        store.advanceQuestion(childId: samuel.id, catechismId: "WSC", totalQuestions: 107)

        let today = store.todayChildren()
        #expect(today[0].practisedToday)
        #expect(today[0].questionNumber == 2)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        #expect(store.todayChildren(now: tomorrow)[0].practisedToday == false)
    }

    @Test("a finished catechism reads as finished, clamped to the last question")
    func finished() throws {
        let samuel = try store.addChild(name: "Samuel")
        store.startTrack(childId: samuel.id, catechismId: "WSC", startingQuestion: 107)
        store.advanceQuestion(childId: samuel.id, catechismId: "WSC", totalQuestions: 107)
        let row = store.todayChildren()[0]
        #expect(row.finished)
        #expect(row.questionNumber == 107)
        #expect(row.learned == 107)
    }
}

extension TodayChildrenTests {
    @Test("a failed child selection produces no session route and leaves existing progress alone")
    func failedSessionSelection() throws {
        let samuel = try store.addChild(name: "Samuel")
        let track = try #require(store.startTrack(childId: samuel.id, catechismId: "WSC", startingQuestion: 9))
        let tapped = child("Thomas")
        let previousUpdate = track.updatedAt

        #expect(throws: (any Error).self) {
            try store.selectChildForSession(tapped)
        }
        #expect(store.activeChildId == samuel.id)
        #expect(track.currentQuestion == 9)
        #expect(track.updatedAt == previousUpdate)
        #expect(!container.mainContext.hasChanges)
    }

    @Test("a failed selection save leaves the prior child's progress untouched")
    func failedSessionSelectionSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Progress.sqlite")
        let writable = ModelConfiguration(schema: progressSchema, url: url)
        let writer = try ModelContainer(for: progressSchema, configurations: [writable])
        let writerStore = LocalProgressStore(context: writer.mainContext)
        let samuel = try writerStore.addChild(name: "Samuel")
        let thomas = try writerStore.addChild(name: "Thomas")
        let track = try #require(writerStore.startTrack(childId: samuel.id, catechismId: "WSC", startingQuestion: 9))

        let readOnly = ModelConfiguration(schema: progressSchema, url: url, allowsSave: false)
        let reader = try ModelContainer(for: progressSchema, configurations: [readOnly])
        let readerStore = LocalProgressStore(context: reader.mainContext)
        let tapped = try #require(readerStore.todayChildren().first { $0.id == thomas.id })
        let previousUpdate = track.updatedAt
        #expect(readerStore.activeChildId == samuel.id)

        #expect(throws: (any Error).self) {
            try readerStore.selectChildForSession(tapped)
        }
        let persistedContext = ModelContext(writer)
        #expect(LocalProgressStore(context: persistedContext).activeChildId == samuel.id)
        let tracks = try persistedContext.fetch(FetchDescriptor<ChildCatechismTrack>())
        let savedTrack = try #require(tracks.first)
        #expect(tracks.count == 1)
        #expect(savedTrack.childId == samuel.id)
        #expect(savedTrack.currentQuestion == 9)
        #expect(savedTrack.updatedAt == previousUpdate)
        #expect(!reader.mainContext.hasChanges)
    }

    @Test("a Today session route loads the tapped child's track after switching children")
    func sessionSelectionLoadsTappedChild() throws {
        let samuel = try store.addChild(name: "Samuel")
        let thomas = try store.addChild(name: "Thomas")
        store.startTrack(childId: samuel.id, catechismId: "WSC", startingQuestion: 9)
        store.startTrack(childId: thomas.id, catechismId: "WSC", startingQuestion: 4)
        #expect(store.activeChildId == samuel.id)
        let tapped = try #require(store.todayChildren().first { $0.id == thomas.id })

        let slug = try store.selectChildForSession(tapped)
        let program = try #require(getProgram(slug))
        let activeChildId = try #require(store.activeChildId)
        let track = try #require(store.resumeOrStartTrack(
            childId: activeChildId, catechismId: program.contentId.rawValue
        ))

        #expect(track.childId == thomas.id)
        #expect(track.currentQuestion == 4)
    }
}

// What Today reads from the Lord's Day store: today's card of the current
// sermon week, and whether this Sunday's notes are still to photograph.
@Suite("Today's sermon from the Lord's Day store")
@MainActor struct TodaySermonTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func day(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    private func makeStore() throws -> LordsDayStore {
        let container = try ModelContainer(
            for: progressSchema,
            configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)]
        )
        return LordsDayStore(context: ModelContext(container))
    }

    /// 15 Nov 2026 is a Sunday. Cards: Monday a key point, Tuesday a verse, Wednesday a quote.
    private func seedWeek(_ store: LordsDayStore, sunday: Int = 15) throws -> LordsDayNote {
        let note = LordsDayNote(serviceDate: day(sunday), passageRef: "Romans 8:28–30", preacher: "Rev. Smith")
        try store.save(note)
        try store.appendCard(to: note, kind: .keyPoint, body: "God's purpose decides what is good.")
        try store.appendCard(to: note, kind: .verse, body: "", verseRef: "Romans 8:28")
        try store.appendCard(to: note, kind: .quote, body: "He is not finished.")
        return note
    }

    @Test("no notes at all: nothing on a weekday, the capture card on Sunday")
    func emptyStore() throws {
        let store = try makeStore()
        let weekday = store.todaySermon(on: day(18), calendar: calendar)
        #expect(weekday.day == nil)
        #expect(weekday.sundayCaptureDue == false)
        let sunday = store.todaySermon(on: day(22), calendar: calendar)
        #expect(sunday.day == nil)
        #expect(sunday.sundayCaptureDue == true)
    }

    @Test("the current week's stack gives its first card when it was never opened")
    func firstCardByDefault() throws {
        let store = try makeStore()
        _ = try seedWeek(store)
        let monday = store.todaySermon(on: day(16), calendar: calendar)
        #expect(monday.sundayCaptureDue == false)
        #expect(monday.day == TodaySermonDay(
            sermonTitle: "Romans 8:28–30", countLabel: "1 of 3", kind: "Key point",
            text: "God's purpose decides what is good.",
            attribution: "From your notes on Romans 8:28–30"
        ))
    }

    @Test("cards aren't tied to days: every day of the week shows the same card (TKL-941)")
    func notTiedToDays() throws {
        let store = try makeStore()
        _ = try seedWeek(store)
        let monday = store.todaySermon(on: day(16), calendar: calendar).day
        for d in 17...21 {
            #expect(store.todaySermon(on: day(d), calendar: calendar).day == monday)
        }
    }

    @Test("the stack's current card is the one it was last on (cover counts as the first card)")
    func followsStackMemory() throws {
        let store = try makeStore()
        let note = try seedWeek(store)
        var memory = LordsDayStackMemory()
        memory.remember(page: 3, for: note.id)
        let quote = try #require(store.todaySermon(on: day(18), calendar: calendar, stackMemory: memory).day)
        #expect(quote == TodaySermonDay(
            sermonTitle: "Romans 8:28–30", countLabel: "3 of 3", kind: "Quote", text: "He is not finished.",
            attribution: "Rev. Smith · Romans 8:28–30"
        ))
        memory.remember(page: 0, for: note.id)
        let cover = try #require(store.todaySermon(on: day(18), calendar: calendar, stackMemory: memory).day)
        #expect(cover.countLabel == "1 of 3")
        memory.remember(page: 99, for: note.id)
        let past = try #require(store.todaySermon(on: day(18), calendar: calendar, stackMemory: memory).day)
        #expect(past.countLabel == "3 of 3")
    }

    @Test("a titled sermon is named by its title")
    func titledSermon() throws {
        let store = try makeStore()
        let note = try seedWeek(store)
        note.sermonTitle = "More than conquerors"
        let card = try #require(store.todaySermon(on: day(18), calendar: calendar).day)
        #expect(card.sermonTitle == "More than conquerors")
    }

    @Test("a verse card shows its reference, since its text is fetched later")
    func verseCard() throws {
        let store = try makeStore()
        let note = try seedWeek(store)
        var memory = LordsDayStackMemory()
        memory.remember(page: 2, for: note.id)
        let verse = try #require(store.todaySermon(on: day(17), calendar: calendar, stackMemory: memory).day)
        #expect(verse.kind == "Verse")
        #expect(verse.text == "Romans 8:28")
        #expect(verse.attribution == "From your notes on Romans 8:28–30")
    }

    @Test("Sunday's capture card names last Sunday's sermon, only when one was kept that day")
    func lastSundayLine() throws {
        let store = try makeStore()
        #expect(store.lastSundayLine(on: day(22), calendar: calendar) == nil)
        let note = try seedWeek(store)
        #expect(store.lastSundayLine(on: day(22), calendar: calendar) == "Last Sunday: Romans 8:28–30")
        note.sermonTitle = "More than conquerors"
        #expect(store.lastSundayLine(on: day(22), calendar: calendar) == "Last Sunday: More than conquerors · Romans 8:28–30")
        #expect(store.lastSundayLine(on: day(29), calendar: calendar) == nil) // two weeks on
    }

    @Test("the next Sunday asks for new notes; last week's cards are over")
    func nextSundayAsksForNotes() throws {
        let store = try makeStore()
        _ = try seedWeek(store)
        let sunday = store.todaySermon(on: day(22), calendar: calendar)
        #expect(sunday.sundayCaptureDue == true)
        #expect(sunday.day == nil)
    }

    @Test("Sunday after photographing: no capture card, and the week's first card shows")
    func sundayAfterCapture() throws {
        let store = try makeStore()
        _ = try seedWeek(store, sunday: 22)
        let sunday = store.todaySermon(on: day(22, hour: 14), calendar: calendar)
        #expect(sunday.sundayCaptureDue == false)
        #expect(sunday.day?.countLabel == "1 of 3")
        #expect(sunday.day?.text == "God's purpose decides what is good.")
    }

    @Test("Sunday notes saved but not drafted yet: no capture card and no day card")
    func sundayCapturedNoCards() throws {
        let store = try makeStore()
        try store.save(LordsDayNote(serviceDate: day(22)))
        let sunday = store.todaySermon(on: day(22, hour: 14), calendar: calendar)
        #expect(sunday.sundayCaptureDue == false)
        #expect(sunday.day == nil)
    }

    @Test("a deleted Sunday note doesn't count as captured")
    func deletedNoteNotCaptured() throws {
        let store = try makeStore()
        let note = try seedWeek(store, sunday: 22)
        note.deletedAt = Date()
        let sunday = store.todaySermon(on: day(22, hour: 14), calendar: calendar)
        #expect(sunday.sundayCaptureDue == true)
        #expect(sunday.day == nil)
    }
}
