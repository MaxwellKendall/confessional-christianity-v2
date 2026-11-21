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
    dayLabel: "Thursday",
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
