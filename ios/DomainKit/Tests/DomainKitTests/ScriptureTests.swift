// Parity pins against src/lib/scripture.ts's getScriptureCitingEntries.
import Testing
@testable import DomainKit

@Suite struct ScriptureTests {
    @Test func citingEntriesSpanEveryDocumentThatQuotesTheReference() {
        let citing = getScriptureCitingEntries("1Cor.10.31")
        let slugs = Set(citing.map(\.documentSlug))
        #expect(slugs.contains("westminster-shorter-catechism"))
        #expect(slugs.contains("westminster-larger-catechism"))
        #expect(slugs.contains("heidelberg-catechism"))
    }

    @Test func citingEntryCarriesItsClauseAndLabel() {
        let citing = getScriptureCitingEntries("1Cor.10.31")
        let wsc = citing.first { $0.documentSlug == "westminster-shorter-catechism" }
        #expect(wsc?.entryId == "WSC-1")
        #expect(wsc?.entryLabel == "Q. 1")
        #expect(wsc?.clause == "Man's chief end is to glorify God,")
    }

    @Test func unknownReferenceReturnsNoCitingEntries() {
        #expect(getScriptureCitingEntries("Not.1.1").isEmpty)
    }
}
