// Ported 1:1 from test/milestones.test.ts.
import Testing
@testable import DomainKit

@Suite("milestonesFor")
struct MilestonesForTests {
    @Test("a program with authored milestones returns them")
    func hasMilestones() {
        #expect(milestonesFor("catechizing-shorter-catechism").count > 0)
    }

    @Test("a program with none returns an empty list")
    func noMilestones() {
        #expect(milestonesFor("not-a-real-program") == [])
    }
}

@Suite("milestoneProgress")
struct MilestoneProgressTests {
    private func def(range: (Int, Int)) -> MilestoneDefinition {
        MilestoneDefinition(id: "m", title: "A Milestone", range: range)
    }

    @Test("a position before the range is locked")
    func locked() {
        let result = milestoneProgress([def(range: (1, 10))], currentQuestion: 1)
        #expect(result == [MilestoneProgress(definition: def(range: (1, 10)), seenCount: 0, total: 10, state: .locked)])
    }

    @Test("a position inside the range is in progress")
    func inProgress() {
        let result = milestoneProgress([def(range: (1, 10))], currentQuestion: 5)
        #expect(result == [MilestoneProgress(definition: def(range: (1, 10)), seenCount: 4, total: 10, state: .in_progress)])
    }

    @Test("a position past the range is complete")
    func complete() {
        let result = milestoneProgress([def(range: (1, 10))], currentQuestion: 11)
        #expect(result == [MilestoneProgress(definition: def(range: (1, 10)), seenCount: 10, total: 10, state: .complete)])
    }

    @Test("a range not starting at question 1 locks until reached")
    func offsetLocked() {
        let result = milestoneProgress([def(range: (42, 81))], currentQuestion: 42)
        #expect(result == [MilestoneProgress(definition: def(range: (42, 81)), seenCount: 0, total: 40, state: .locked)])
    }
}
