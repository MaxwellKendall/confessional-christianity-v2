// Ported 1:1 from test/programs.test.ts.
import Testing
@testable import DomainKit

@Suite("getProgram")
struct ProgramsTests {
    @Test("finds a registered program by slug")
    func findsBySlug() {
        #expect(getProgram(PROGRAMS[0].slug)?.slug == PROGRAMS[0].slug)
    }

    @Test("returns nil for an unknown slug")
    func unknownSlug() {
        #expect(getProgram("not-a-real-program") == nil)
    }
}
