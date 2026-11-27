// TKL-825: what the Today home screen shows. One primary card (the one thing
// to do now), then the other items due today. The rule, from the issue and
// TKL-885's approved prototype:
//   1. Sunday with the notes not captured yet → "photograph your notes".
//   2. The active child's next catechism session, if not practised today;
//      else the next child still due.
//   3. Else this week's sermon stack's current card. Cards are a numbered
//      stack, not tied to days (TKL-1062): the card shown is the one the
//      stack was last left on in the Lord's Day tab.
//   4. Else (everyone done, no sermon week) the active child, shown as done.
// A new guest with nothing started gets `.empty`: the two pillars, nothing else.
import Foundation
import SwiftData

/// One child's place in their catechism, as Today needs it.
public struct TodayChild: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let programSlug: String
    public let programShortTitle: String
    /// The next question to learn, clamped to the last question once finished.
    public let questionNumber: Int
    public let totalQuestions: Int
    public let question: String?
    public let learned: Int
    public let practisedToday: Bool
    public let finished: Bool
    /// When a question was last introduced to this child, if ever.
    public let lastPractisedAt: Date?

    public init(
        id: UUID, name: String, programSlug: String, programShortTitle: String,
        questionNumber: Int, totalQuestions: Int, question: String?, learned: Int,
        practisedToday: Bool, finished: Bool, lastPractisedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.programSlug = programSlug
        self.programShortTitle = programShortTitle
        self.questionNumber = questionNumber
        self.totalQuestions = totalQuestions
        self.question = question
        self.learned = learned
        self.practisedToday = practisedToday
        self.finished = finished
        self.lastPractisedAt = lastPractisedAt
    }

    /// Still something to do with this child today.
    public var isDue: Bool { !practisedToday && !finished }
}

/// This week's sermon stack's current card, from the Lord's Day store
/// (`LordsDayStore.todaySermon`).
public struct TodaySermonDay: Equatable, Sendable {
    /// The sermon's title, else its passage, else its date (as the reel names it).
    public let sermonTitle: String
    /// The card's place in the stack: "3 of 7".
    public let countLabel: String
    public let kind: String
    public let text: String
    public let attribution: String

    public init(sermonTitle: String, countLabel: String, kind: String, text: String, attribution: String) {
        self.sermonTitle = sermonTitle
        self.countLabel = countLabel
        self.kind = kind
        self.text = text
        self.attribution = attribution
    }
}

public struct TodayInput: Equatable, Sendable {
    public var children: [TodayChild]
    public var activeChildId: UUID?
    public var sermonDay: TodaySermonDay?
    /// It's Sunday and this Sunday's notes aren't captured yet.
    public var sundayCaptureDue: Bool

    public init(
        children: [TodayChild], activeChildId: UUID?,
        sermonDay: TodaySermonDay? = nil, sundayCaptureDue: Bool = false
    ) {
        self.children = children
        self.activeChildId = activeChildId
        self.sermonDay = sermonDay
        self.sundayCaptureDue = sundayCaptureDue
    }
}

public enum TodayItem: Equatable, Sendable {
    case catechism(TodayChild)
    case sermonDay(TodaySermonDay)
    case captureSunday
}

public enum TodayPlan: Equatable, Sendable {
    case empty
    case plan(primary: TodayItem, also: [TodayItem])
}

/// Active child first, the rest in their given order.
func activeChildFirst(_ children: [TodayChild], activeChildId: UUID?) -> [TodayChild] {
    var children = children
    if let activeId = activeChildId, let i = children.firstIndex(where: { $0.id == activeId }) {
        children.insert(children.remove(at: i), at: 0)
    }
    return children
}

/// The Catechism tab's cards (TKL-939): Today's order (active child first),
/// then every child still due today ahead of those already practised or
/// finished, so finishing a session moves the next child to the front.
public func orderCatechismCards(_ children: [TodayChild], activeChildId: UUID?) -> [TodayChild] {
    let ordered = activeChildFirst(children, activeChildId: activeChildId)
    return ordered.filter(\.isDue) + ordered.filter { !$0.isDue }
}

/// The line under a child's name on their card.
public func catechismPracticeLine(lastPractisedAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
    guard let last = lastPractisedAt else { return "Not started yet" }
    let days = calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)
    ).day ?? 0
    switch days {
    case ...0: return "Practised today"
    case 1: return "Last practised yesterday"
    default: return "Last practised \(days) days ago"
    }
}

public func planToday(_ input: TodayInput) -> TodayPlan {
    let children = activeChildFirst(input.children, activeChildId: input.activeChildId)

    if input.sundayCaptureDue {
        return .plan(primary: .captureSunday, also: children.map(TodayItem.catechism))
    }
    if let due = children.first(where: \.isDue) {
        var also = children.filter { $0.id != due.id }.map(TodayItem.catechism)
        if let day = input.sermonDay { also.append(.sermonDay(day)) }
        return .plan(primary: .catechism(due), also: also)
    }
    if let day = input.sermonDay {
        return .plan(primary: .sermonDay(day), also: children.map(TodayItem.catechism))
    }
    if let first = children.first {
        return .plan(primary: .catechism(first), also: children.dropFirst().map(TodayItem.catechism))
    }
    return .empty
}

extension LocalProgressStore {
    /// Supplies a navigation destination only after the tapped child's selection is saved.
    public func selectChildForSession(_ child: TodayChild) throws -> String {
        try selectChild(childId: child.id)
        return child.programSlug
    }

    /// Every child in the order they were added, each at the next question of
    /// their current catechism (the Shorter Catechism at Q. 1 if not started).
    /// "Practised today" means a question was introduced today.
    public func todayChildren(now: Date = Date(), calendar: Calendar = .current) -> [TodayChild] {
        let all = (try? context.fetch(FetchDescriptor<LocalChild>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.map { child in
            let track = activeTrack(childId: child.id)
            let program = track.flatMap { programForContentId($0.catechismId) } ?? PROGRAMS[0]
            let total = program.totalQuestions
            let current = track?.currentQuestion ?? 1
            let number = min(max(current, 1), total)
            let lastPractised = track?.milestones.values.map(\.introducedAt).max()
            let practised = lastPractised.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            return TodayChild(
                id: child.id,
                name: child.name,
                programSlug: program.slug,
                programShortTitle: program.shortTitle,
                questionNumber: number,
                totalQuestions: total,
                question: getQuestion(program, number)?.question,
                learned: min(max(current - 1, 0), total),
                practisedToday: practised,
                finished: current > total,
                lastPractisedAt: lastPractised
            )
        }
    }
}

extension LordsDayStore {
    /// What Today needs from the Lord's Day store: this week's sermon stack's
    /// current card (the page `stackMemory` holds for it; the cover counts as
    /// the first card), if it has cards, and whether it's a Sunday whose notes
    /// aren't saved yet. A note saved but not yet drafted counts as captured
    /// (the Lord's Day tab offers its review).
    public func todaySermon(
        on date: Date = Date(), calendar: Calendar = .current, stackMemory: LordsDayStackMemory = LordsDayStackMemory()
    ) -> (day: TodaySermonDay?, sundayCaptureDue: Bool) {
        let week = try? currentWeek(on: date, calendar: calendar)
        let capturedToday = week.map { calendar.isDate($0.serviceDate, inSameDayAs: date) } ?? false
        let sundayCaptureDue = calendar.component(.weekday, from: date) == 1 && !capturedToday

        guard let kept = try? currentWeekWithCards(on: date, calendar: calendar) else { return (nil, sundayCaptureDue) }
        let sermon = ReelSermon(note: kept.note, cards: kept.cards, today: date, calendar: calendar)
        guard !sermon.cards.isEmpty else { return (nil, sundayCaptureDue) }
        let index = max(stackMemory.page(for: sermon) - 1, 0)
        let card = sermon.cards[index]
        let day = TodaySermonDay(
            sermonTitle: sermon.title,
            countLabel: "\(index + 1) of \(sermon.cards.count)",
            kind: card.kind.label,
            text: card.kind == .verse ? (card.reference ?? "") : card.body,
            attribution: card.attributionLine ?? card.passage.map { "From your notes on \($0)" } ?? "From your notes"
        )
        return (day, sundayCaptureDue)
    }

    /// The Sunday capture card's line about the previous Sunday's kept sermon
    /// ("Last Sunday: More than conquerors · Romans 8:28–39"), or nil when none
    /// was kept that day.
    public func lastSundayLine(on date: Date = Date(), calendar: Calendar = .current) -> String? {
        let today = calendar.startOfDay(for: date)
        guard let previous = calendar.date(byAdding: .day, value: -7, to: today),
              let notes = try? allNotes() else { return nil }
        let kept = notes
            .filter { calendar.isDate($0.serviceDate, inSameDayAs: previous) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first { !((try? cards(for: $0))?.isEmpty ?? true) }
        guard let note = kept else { return nil }
        let sermon = ReelSermon(note: note, cards: (try? cards(for: note)) ?? [], today: date, calendar: calendar)
        let passage = sermon.title == sermon.passage ? nil : sermon.passage
        return "Last Sunday: " + ([sermon.title, passage].compactMap { $0 }.joined(separator: " · "))
    }
}
