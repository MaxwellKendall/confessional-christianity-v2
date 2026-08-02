// Age-labeled checkpoints: a milestone's progress is derived purely from how
// far a track's position has advanced, so it needs no persistence read
// beyond what the caller already has. Ported from src/lib/milestones.ts.
import Foundation

public struct MilestoneDefinition: Equatable, Sendable {
    public let id: String
    public let title: String
    /// inclusive question-number range this milestone covers
    public let range: (Int, Int)
    /// editorial guidance only, e.g. "typical for age 7–8" — not compared
    /// against the child's actual age
    public let typicalAge: (Int, Int)?

    public init(id: String, title: String, range: (Int, Int), typicalAge: (Int, Int)? = nil) {
        self.id = id
        self.title = title
        self.range = range
        self.typicalAge = typicalAge
    }

    public static func == (lhs: MilestoneDefinition, rhs: MilestoneDefinition) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.range == rhs.range
            && lhs.typicalAge?.0 == rhs.typicalAge?.0 && lhs.typicalAge?.1 == rhs.typicalAge?.1
    }
}

// Authored per program slug, same pattern as prayers. Only WSC has real
// milestones so far; other programs render the honest "not yet mapped"
// empty state until someone authors theirs.
private let milestonesBySlug: [String: [MilestoneDefinition]] = [
    "catechizing-shorter-catechism": [
        MilestoneDefinition(id: "first-ten", title: "First Ten Questions", range: (1, 10)),
        MilestoneDefinition(id: "ten-commandments", title: "The Ten Commandments", range: (42, 81), typicalAge: (7, 8)),
        MilestoneDefinition(id: "halfway", title: "Half the Catechism", range: (1, 54), typicalAge: (9, 10)),
        MilestoneDefinition(id: "complete", title: "The Whole Catechism", range: (1, 107), typicalAge: (11, 12)),
    ],
]

public func milestonesFor(_ slug: String) -> [MilestoneDefinition] {
    milestonesBySlug[slug] ?? []
}

public struct MilestoneProgress: Equatable, Sendable {
    public let definition: MilestoneDefinition
    public let seenCount: Int
    public let total: Int
    public let state: State

    public enum State: String, Sendable {
        case complete, in_progress, locked
    }
}

// `currentQuestion` is a 1-indexed position pointer: every question number
// below it has been seen.
public func milestoneProgress(_ definitions: [MilestoneDefinition], currentQuestion: Int) -> [MilestoneProgress] {
    definitions.map { def in
        let (start, end) = def.range
        let total = end - start + 1
        let seenCount = min(total, max(0, currentQuestion - start))
        let state: MilestoneProgress.State = seenCount >= total ? .complete : (seenCount > 0 ? .in_progress : .locked)
        return MilestoneProgress(definition: def, seenCount: seenCount, total: total, state: state)
    }
}
