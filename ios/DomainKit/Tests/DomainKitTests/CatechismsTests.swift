// Ported 1:1 from test/catechisms.test.ts.
import Testing
@testable import DomainKit

@Suite("catechism metadata")
struct CatechismMetadataTests {
    @Test("getCatechismById normalizes ids and resolves CfYC aliases")
    func catechismById() {
        let wsc = getCatechismById("wsc")
        let cfyc = getCatechismById("CFYC")
        #expect(wsc?.id == "WSC")
        #expect(wsc?.totalQuestions == 107)
        #expect(cfyc?.id == "CfYC")
        #expect(cfyc?.totalQuestions == 145)
    }

    @Test("getDocumentById normalizes ids and resolves CfYC aliases")
    func documentById() {
        let wcf = getDocumentById("wcf")
        let cfyc = getDocumentById("CfYC")
        #expect(wcf?.id == "WCF")
        #expect(wcf?.itemLabel == "Chapter")
        #expect(cfyc?.id == "CfYC")
        #expect(cfyc?.itemLabel == "Question")
    }

    @Test("getDocumentsByTradition preserves the intended display order")
    func traditionOrder() {
        let order = getDocumentsByTradition().map(\.tradition)
        #expect(order == ["Westminster Standards", "Three Forms of Unity", "Anglican", "Reformation", "Other"])
    }
}

@Suite("progress and links")
struct ProgressAndLinksTests {
    @Test("generateCatechismLink resolves to the canonical library entry")
    func catechismLink() {
        #expect(generateCatechismLink("WSC", questionNumber: 12) == "/library/westminster-shorter-catechism/12")
    }

    @Test("generateDocumentLink resolves to the canonical library entry")
    func documentLink() {
        #expect(generateDocumentLink("WCF", itemNumber: 3) == "/library/westminster-confession-of-faith/3")
    }

    @Test("calculateProgress returns zero when inputs are missing")
    func progressZero() {
        #expect(calculateProgress(nil, 107) == 0)
    }

    @Test("calculateProgress rounds to the nearest whole percent")
    func progressRounds() {
        #expect(calculateProgress(17, 107) == 16)
    }

    @Test("calculateProgress returns full completion at the upper bound")
    func progressComplete() {
        #expect(calculateProgress(107, 107) == 100)
    }
}
