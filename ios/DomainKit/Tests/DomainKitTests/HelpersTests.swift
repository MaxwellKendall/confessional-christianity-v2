import Testing
@testable import DomainKit

@Suite struct ParseFacetsTests {
    @Test func wholeConfessionSearchResolvesToFirstChapter() {
        #expect(parseFacets("WCF") == [.and("parent:WCoF-1")])
    }

    @Test func catechismSearchResolvesToFirstQuestion() {
        #expect(parseFacets("WSC") == [.and("id:WSC-1")])
    }

    @Test func chapterAndArticleSearchResolvesToSingleEntryId() {
        #expect(parseFacets("WCF.1.2") == [.and("id:WCoF-1-2")])
    }

    @Test func canonsRejectionSearchResolvesToRejectionEntryId() {
        #expect(parseFacets("CD.1.r2") == [.and("id:CoD-1-rejections-2")])
    }

    @Test func keywordBundleSearchExpandsToWestminsterDocumentFacets() {
        #expect(parseFacets("westminster standards") == [.or([
            "document:Westminster Shorter Catechism",
            "document:Westminster Larger Catechism",
            "document:Westminster Confession of Faith",
        ])])
    }

    @Test func bibleRangeSearchResolvesToBookAndCitationFacets() {
        #expect(parseFacets("John 3:16-17") == [
            .and("book:John"),
            .and("startChapter:3"),
            .and("startVerse:16"),
            .and("endVerse:17"),
        ])
    }

    @Test func remainsStableAcrossRepeatedKeywordSearches() {
        let expected: FacetFilters = [.or([
            "document:Westminster Shorter Catechism",
            "document:Westminster Larger Catechism",
            "document:Westminster Confession of Faith",
        ])]
        #expect(parseFacets("westminster standards") == expected)
        #expect(parseFacets("westminster standards") == expected)
    }
}

@Suite struct LinkGenerationTests {
    @Test func searchLinksUseV2Format() {
        #expect(generateSearchLink("WCoF-1-2") == "/search?q=WCF.1.2")
    }

    @Test func canonicalEntryLinksUseSingleSegmentLibraryFormat() {
        #expect(generateCanonicalEntryLink("CoD-1-articles-3") == "/library/canons-of-dort/1-articles-3")
    }

    @Test func navLinksPreferCanonicalEntryPagesForLeafContent() {
        let entries: ContentById = [
            "WCoF-1-2": ConfessionEntry(id: "WCoF-1-2", parent: "WCoF-1", title: nil, isParent: false),
        ]
        #expect(generateNavLink("WCoF-1-2", entries) == "/library/westminster-confession-of-faith/1-2")
    }

    @Test func navLinksFallBackToSearchRoutesForChapterLevelTargets() {
        let entries: ContentById = [
            "WCoF-1": ConfessionEntry(id: "WCoF-1", parent: "WCoF", title: nil, isParent: true),
        ]
        #expect(generateNavLink("WCoF-1", entries) == "/search?q=WCF.1")
    }

    @Test func entryIdToPathSegmentStripsDocumentPrefix() {
        #expect(entryIdToPathSegment("CoD-1-articles-3", "CoD") == "1-articles-3")
    }
}

@Suite struct ParseCitedByIdTests {
    @Test func wcfChapterArticleWithLetterMarker() {
        let cited = parseCitedById("WCoF-10-3-a")
        #expect(cited.entryId == "WCoF-10-3")
        #expect(cited.label == "Westminster Confession 10.3")
    }

    @Test func wlcQuestionWithNumericMarker() {
        let cited = parseCitedById("WLC-50-2")
        #expect(cited.entryId == "WLC-50")
        #expect(cited.label == "Larger Catechism Q. 50")
    }

    @Test func wscQuestionWithLetterMarker() {
        let cited = parseCitedById("WSC-27-g")
        #expect(cited.entryId == "WSC-27")
        #expect(cited.label == "Shorter Catechism Q. 27")
    }

    @Test func heidelbergLordsDayQuestionAndAnswerWithLetterMarker() {
        let cited = parseCitedById("HC-6-17-d")
        #expect(cited.entryId == "HC-6-17")
        #expect(cited.label == "Heidelberg Catechism Q&A 17")
    }
}
