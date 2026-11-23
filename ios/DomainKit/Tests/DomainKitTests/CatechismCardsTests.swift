// TKL-939: the Catechism tab's swipeable card per child (TKL-885 prototype).
// The active child leads (planToday's rule), children still due today come
// before those already practised, so finishing a child's session moves the
// next child to the front.
import Foundation
import Testing
@testable import DomainKit

private func card(_ name: String, practisedToday: Bool = false, finished: Bool = false) -> TodayChild {
    TodayChild(
        id: UUID(), name: name, programSlug: "catechizing-shorter-catechism",
        programShortTitle: "Shorter Catechism", questionNumber: 1, totalQuestions: 107,
        question: nil, learned: 0, practisedToday: practisedToday, finished: finished
    )
}

@Suite("Catechism cards")
struct CatechismCardsTests {
    @Test("no children, no cards")
    func empty() {
        #expect(orderCatechismCards([], activeChildId: nil).isEmpty)
    }

    @Test("nobody practised yet: the order they were added")
    func addedOrder() {
        let s = card("Samuel"), t = card("Thomas")
        #expect(orderCatechismCards([s, t], activeChildId: nil).map(\.name) == ["Samuel", "Thomas"])
    }

    @Test("the active child leads, as on Today")
    func activeFirst() {
        let s = card("Samuel"), t = card("Thomas"), a = card("Anna")
        #expect(orderCatechismCards([s, t, a], activeChildId: a.id).map(\.name) == ["Anna", "Samuel", "Thomas"])
    }

    @Test("finishing a child's session moves the next child to the front")
    func practisedMovesBack() {
        // After Samuel's session he is the active child and practised today.
        let s = card("Samuel", practisedToday: true), t = card("Thomas")
        #expect(orderCatechismCards([s, t], activeChildId: s.id).map(\.name) == ["Thomas", "Samuel"])
    }

    @Test("a child who finished the catechism goes after those still due, order kept")
    func finishedLast() {
        let s = card("Samuel", finished: true), t = card("Thomas", practisedToday: true), a = card("Anna")
        #expect(orderCatechismCards([s, t, a], activeChildId: nil).map(\.name) == ["Anna", "Samuel", "Thomas"])
    }

    @Test("everyone practised: back to the active-first order")
    func allPractised() {
        let s = card("Samuel", practisedToday: true), t = card("Thomas", practisedToday: true)
        #expect(orderCatechismCards([s, t], activeChildId: t.id).map(\.name) == ["Thomas", "Samuel"])
    }

    @Test("the line under a child's name says when they last practised")
    func practiceLine() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_795_000_000) // midday-ish UTC
        let day: TimeInterval = 86_400
        #expect(catechismPracticeLine(lastPractisedAt: nil, now: now, calendar: cal) == "Not started yet")
        #expect(catechismPracticeLine(lastPractisedAt: now.addingTimeInterval(-60), now: now, calendar: cal) == "Practised today")
        #expect(catechismPracticeLine(lastPractisedAt: now.addingTimeInterval(-day), now: now, calendar: cal) == "Last practised yesterday")
        #expect(catechismPracticeLine(lastPractisedAt: now.addingTimeInterval(-4 * day), now: now, calendar: cal) == "Last practised 4 days ago")
    }
}
