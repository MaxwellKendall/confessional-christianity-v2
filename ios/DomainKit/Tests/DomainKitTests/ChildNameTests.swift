import Foundation
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

// Editing a child in Settings (TKL-1116): the same rules as Add a child, but a
// child's own name is not a duplicate of itself.
@Suite struct ChildRenameTests {
    let samuel = UUID()
    let ruth = UUID()
    var children: [(id: UUID, name: String)] { [(samuel, "Samuel"), (ruth, "Ruth")] }

    @Test func keepingTheSameNameIsValid() {
        #expect(ChildName.validateRename("Samuel", childId: samuel, children: children) == .valid("Samuel"))
        #expect(ChildName.validateRename("samuel ", childId: samuel, children: children) == .valid("samuel"))
    }

    @Test func anotherChildsNameIsADuplicate() {
        let check = ChildName.validateRename("RUTH", childId: samuel, children: children)
        #expect(check == .duplicate)
        #expect(check.message == "Ruth is already on this iPhone. Use a different name.")
    }

    @Test func emptyAndOverlongFollowAddRules() {
        #expect(ChildName.validateRename("  ", childId: samuel, children: children) == .empty)
        let long = String(repeating: "a", count: ChildName.maxLength + 1)
        #expect(ChildName.validateRename(long, childId: samuel, children: children) == .tooLong)
    }

    @Test func removalConfirmationNamesTheChildAndTheirProgress() {
        let copy = ChildName.removal(name: "Samuel")
        #expect(copy.title == "Remove Samuel?")
        #expect(copy.message == "Samuel's catechism progress goes with them. This can't be undone.")
        #expect(copy.confirm == "Remove Samuel")
    }
}
