// Ported 1:1 from test/programContent.test.ts.
import Testing
@testable import DomainKit

@Suite("program content")
struct ProgramContentTests {
    let wsc = getProgram("catechizing-shorter-catechism")!
    let cfyc = getProgram("catechism-for-young-children")!
    let wlc = getProgram("catechizing-larger-catechism")!
    let hc = getProgram("catechizing-heidelberg-catechism")!

    @Test("WSC questions resolve with clean question and answer text")
    func wscQuestion() {
        let q = getQuestion(wsc, 7)
        #expect(q?.question == "What are the decrees of God?")
        #expect(q?.answer.contains("his eternal purpose") == true)
        #expect(q?.answer.contains("[a]") == false)
        #expect(q?.proofTexts.contains("Eph.1.4") == true)
    }

    @Test("WSC citations group proof texts by clause")
    func wscCitations() {
        let c = getQuestionCitations(wsc, 1)
        #expect((c?.groups.count ?? 0) > 0)
        #expect(c?.answerSegments.contains { $0.marker != nil } == true)
    }

    @Test("CfYC questions resolve from their own document")
    func cfycQuestion() {
        let q = getQuestion(cfyc, 1)
        #expect(q?.question == "Who made you?")
        #expect(q?.answer == "God.")
    }

    @Test("CfYC has no proof texts, so citations render an empty group list")
    func cfycCitations() {
        let c = getQuestionCitations(cfyc, 1)
        #expect(c?.groups == [])
        #expect((c?.answerSegments.count ?? 0) > 0)
    }

    @Test("prayers substitute the child name")
    func prayerSubstitution() {
        let prayer = getPrayer(wsc, 7, childName: "Eli")
        #expect(prayer?.contains("Help Eli trust") == true)
    }

    @Test("unwritten prayers are honestly absent")
    func unwrittenPrayer() {
        #expect(hasPrayer(wsc, 99) == false)
        #expect(getPrayer(wsc, 99, childName: "Eli") == nil)
    }

    @Test("a program with no authored prayers yet is honestly absent")
    func noPrayersAuthored() {
        #expect(hasPrayer(cfyc, 1) == false)
        #expect(getPrayer(cfyc, 1, childName: "Eli") == nil)
    }

    @Test("WLC questions resolve, including the last one")
    func wlcQuestions() {
        let first = getQuestion(wlc, 1)
        let last = getQuestion(wlc, 196)
        #expect(first?.question == "What is the chief and highest end of man?")
        #expect(last != nil)
    }

    // The Heidelberg's underlying entry.number is a raw content-array
    // position (Lord's Day headers share the sequence with questions), not
    // the traditional Q number — Question 1's entry.number is actually 2.
    // findEntry has to resolve by the title's stated number instead.
    @Test("HC questions resolve by their stated number, not entry.number")
    func hcQuestionByStatedNumber() {
        let q = getQuestion(hc, 1)
        #expect(q?.question == "What is thy only comfort in life and death?")
        #expect(q?.answer.contains("not my own") == true)
    }

    @Test("HC resolves every question 1..129 with no gaps")
    func hcNoGaps() {
        let questions = (1...129).map { getQuestion(hc, $0) }
        #expect(questions.allSatisfy { $0 != nil })
    }
}
