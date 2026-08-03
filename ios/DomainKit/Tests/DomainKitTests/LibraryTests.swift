// Parity pins against test/library.test.ts and the compareEntryIds cases in
// test/helpers.test.ts.
import Testing
@testable import DomainKit

@Suite struct LibraryTests {
    @Test func compareEntryIdsOrdersCanonsArticlesBeforeRejections() {
        let sorted = ["CoD-1-rejections-2", "CoD-1-articles-3", "CoD-1-articles-1"]
            .sorted(by: compareEntryIds)
        #expect(sorted == ["CoD-1-articles-1", "CoD-1-articles-3", "CoD-1-rejections-2"])
    }

    @Test func loadConfessionContentReturnsContentKeyedById() {
        let content = loadConfessionContent("westminster-confession-of-faith")
        #expect(content?.documentId == "WCoF")
        #expect(content?.contentById["WCoF-1"]?.isParent == true)
        #expect(content?.contentById["WCoF-1-1"]?.parent == "WCoF-1")
    }

    @Test func loadConfessionContentReturnsNilForUnknownSlugs() {
        #expect(loadConfessionContent("not-a-real-confession") == nil)
    }

    @Test func entryPageReturnsTheLeafAndAdjacentLinks() {
        let page = getEntryPage("westminster-confession-of-faith", entryId: "WCoF-1-2")
        #expect(page?.item.id == "WCoF-1-2")
        #expect(page?.documentTitle == "Westminster Confession of Faith")
        #expect(page?.prevEntry == AdjacentEntry(entryId: "WCoF-1-1", title: "Article 1"))
        #expect(page?.nextEntry == AdjacentEntry(entryId: "WCoF-1-3", title: "Article 3"))
    }

    @Test func entryPageReturnsNilForUnknownIds() {
        #expect(getEntryPage("westminster-confession-of-faith", entryId: "WCoF-999") == nil)
    }

    @Test func entryPageReturnsNilForParentIds() {
        #expect(getEntryPage("westminster-confession-of-faith", entryId: "WCoF-1") == nil)
    }

    @Test func documentDescriptionOpensFromTheFirstLeafEntry() {
        let leaves = getOrderedLeafEntries("westminster-confession-of-faith")
        #expect(leaves.first?.text?.contains("Although the light of nature") == true)
    }

    @Test func allEightLibraryDocumentsLoad() {
        for doc in LIBRARY_DOCUMENTS {
            #expect(loadConfessionContent(doc.slug) != nil, "expected \(doc.slug) to load")
        }
    }
}
