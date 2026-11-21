// A catechism session's proof text opens the verse reader (TKL-878): the
// session builds the reader's source from the program and question, and the
// intro/end cards name the catechism.
import Foundation
import Testing
@testable import DomainKit

@Suite struct ProofTextReaderTests {
    private let wsc = getProgram("catechizing-shorter-catechism")!

    @Test func wscQuestion32ProofTextBuildsAReaderSource() throws {
        let question = try #require(getQuestion(wsc, 32))
        let osises = try #require(getQuestionCitations(wsc, 32)).groups.flatMap { $0.refs.map(\.osis) }
        #expect(osises.contains("Rom.8.30"))

        let source = proofTextReaderSource(program: wsc, question: question, osis: "Rom.8.30")
        #expect(source == .proofText(
            catechismSlug: "westminster-shorter-catechism",
            questionNumber: 32,
            question: question.question,
            answer: question.answer,
            osis: "Rom.8.30"
        ))
        #expect(readerCatechismName(for: "westminster-shorter-catechism") == "Westminster Shorter Catechism")
    }

    @Test func everyProgramHasACatechismName() {
        for program in PROGRAMS {
            let question = ProgramQuestion(number: 1, question: "", answer: "", proofTexts: [])
            guard case let .proofText(slug, _, _, _, _) = proofTextReaderSource(program: program, question: question, osis: "Gen.1.1") else {
                Issue.record("expected proofText for \(program.slug)")
                continue
            }
            #expect(readerCatechismName(for: slug) != "Catechism", "\(program.slug)")
        }
    }

    /// Rom 8:30 is not in the bundled ESV subset (coverage is partial by
    /// design), so offline the reader opens whatever session proof text is.
    @Test func aWscSessionProofTextIsBundledForOffline() throws {
        let bundled = (1...wsc.totalQuestions).lazy.compactMap { n in
            getQuestionCitations(wsc, n)?.groups.flatMap(\.refs).first { bundledEsvText(for: $0.osis) != nil }
                .map { (n, $0.osis) }
        }.first
        let (number, osis) = try #require(bundled)
        print("bundled WSC proof text: Q. \(number) \(osis)")
        #expect(bundledEsvText(for: osis)?.isEmpty == false)
    }
}
