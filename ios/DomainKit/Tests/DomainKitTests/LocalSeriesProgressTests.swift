// Ported 1:1 from test/localSeriesProgress.test.ts.
import Testing
@testable import DomainKit

@Suite("currentPartDay")
struct CurrentPartDayTests {
    @Test("a fresh household starts at part 1")
    func freshStart() {
        #expect(currentPartDay([], totalParts: 24) == 1)
    }

    @Test("finishing part 1 advances the suggested part to 2")
    func advancesAfterFirst() {
        #expect(currentPartDay([1], totalParts: 24) == 2)
    }

    @Test("progress resumes exactly where the household left off")
    func resumesWhereLeftOff() {
        #expect(currentPartDay([1, 2, 3, 4, 5, 6, 7, 8], totalParts: 24) == 9)
    }

    @Test("the first gap is current, even past later completions")
    func firstGapIsCurrent() {
        #expect(currentPartDay([1, 3], totalParts: 24) == 2)
    }

    @Test("completion order in the store does not matter")
    func orderIndependent() {
        #expect(currentPartDay([2, 1], totalParts: 24) == 3)
    }

    @Test("a finished series has no current part")
    func finishedSeries() {
        #expect(currentPartDay([1, 2, 3], totalParts: 3) == nil)
    }
}
