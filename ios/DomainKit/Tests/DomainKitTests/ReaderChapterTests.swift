import Foundation
import Testing
@testable import DomainKit

struct ReaderChapterTests {
    @Test func usesUTF16OffsetsAndKeepsChapterWhitespace() throws {
        let data = Data(#"{"text":"Title\n\n    A 🌿\n        B\n    C","anchors":[{"osis":"Ps.23.1","verse":1,"offset":7},{"osis":"Ps.23.2","verse":2,"offset":26}]}"#.utf8)
        let chapter = try JSONDecoder().decode(ReaderChapter.self, from: data)
        #expect(chapter.matches("Ps.23"))
        #expect(!chapter.matches("Ps.24"))
        #expect(chapter.text == "Title\n\n    A 🌿\n        B\n    C")
        #expect(chapter.verses.map(\.range) == [NSRange(location: 11, length: 14), NSRange(location: 30, length: 1)])
    }

    @Test func usesUnambiguousQueriesForSingleChapterBooks() {
        for book in ["Obad", "Phlm", "2John", "3John", "Jude"] {
            #expect(ReaderChapter.queryOSIS(for: "\(book).1") == book)
        }
        #expect(ReaderChapter.queryOSIS(for: "Rom.8") == "Rom.8")
    }

    @Test func rejectsInvalidOffsets() {
        let data = Data(#"{"text":"🌿","anchors":[{"osis":"Ps.23.1","verse":1,"offset":1}]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ReaderChapter.self, from: data) }
    }

    @Test func selectsTheTappedChapterAndHighlightsOnlyPassageVerses() {
        let passage = "Rom.8.38-Rom.9.2,Rom.9.5"
        #expect(ReaderChapter.chapterOSIS(for: passage) == "Rom.8")
        #expect(ReaderChapter.chapterOSIS(for: "Rom.9.1") == "Rom.9")
        #expect(ReaderChapter.contains("Rom.8.38", in: passage))
        #expect(ReaderChapter.contains("Rom.9.2", in: passage))
        #expect(ReaderChapter.contains("Rom.9.5", in: passage))
        #expect(!ReaderChapter.contains("Rom.9.3", in: passage))
        #expect(ReaderChapter.contains("Ps.23.6", in: "Ps.23"))
    }
}
