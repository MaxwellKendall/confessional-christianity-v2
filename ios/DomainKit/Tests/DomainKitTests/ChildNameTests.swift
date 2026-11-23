import Testing
@testable import DomainKit

// The Add a child sheet's inline errors (TKL-941).
@Suite struct ChildNameTests {
    @Test func acceptsATrimmedFirstName() {
        #expect(ChildName.validate("  Ruth \n", existing: []) == .valid("Ruth"))
    }

    @Test func emptyIsNotAnErrorUntilSubmitted() {
        #expect(ChildName.validate("   ", existing: []) == .empty)
        #expect(ChildName.Check.empty.message == nil)
    }

    @Test func rejectsANameAlreadyInUseIgnoringCase() {
        let check = ChildName.validate("ruth", existing: ["Samuel", "Ruth"])
        #expect(check == .duplicate)
        #expect(check.message == "Ruth is already on this iPhone. Use a different name.")
    }

    @Test func rejectsOverlongNames() {
        let long = String(repeating: "a", count: ChildName.maxLength + 1)
        #expect(ChildName.validate(long, existing: []) == .tooLong)
        #expect(ChildName.Check.tooLong.message == "Keep it to \(ChildName.maxLength) letters or fewer.")
        let fits = String(repeating: "a", count: ChildName.maxLength)
        #expect(ChildName.validate(fits, existing: []) == .valid(fits))
    }
}
