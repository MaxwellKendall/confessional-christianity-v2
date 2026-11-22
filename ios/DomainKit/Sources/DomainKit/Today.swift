// TKL-825: what the Today home screen shows. One primary card (the one thing
// to do now), then the other items due today. The rule, from the issue and
// TKL-885's approved prototype:
//   1. Sunday with the notes not captured yet → "photograph your notes".
//   2. The active child's next catechism session, if not practised today;
//      else the next child still due.
//   3. Else today's day of the current sermon week.
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

    public init(
        id: UUID, name: String, programSlug: String, programShortTitle: String,
        questionNumber: Int, totalQuestions: Int, question: String?, learned: Int,
        practisedToday: Bool, finished: Bool
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
    }

    /// Still something to do with this child today.
    public var isDue: Bool { !practisedToday && !finished }
}

/// Today's card of the current sermon week. The Lord's Day store (TKL-859)
/// supplies it; until then the app passes nil.
public struct TodaySermonDay: Equatable, Sendable {
    public let dayLabel: String
    public let kind: String
    public let text: String
    public let attribution: String

    public init(dayLabel: String, kind: String, text: String, attribution: String) {
        self.dayLabel = dayLabel
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

public func planToday(_ input: TodayInput) -> TodayPlan {
    // Active child first, the rest in their given order.
    var children = input.children
    if let activeId = input.activeChildId, let i = children.firstIndex(where: { $0.id == activeId }) {
        children.insert(children.remove(at: i), at: 0)
    }

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
            let practised = track?.milestones.values.contains {
                calendar.isDate($0.introducedAt, inSameDayAs: now)
            } ?? false
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
                finished: current > total
            )
        }
    }
}
