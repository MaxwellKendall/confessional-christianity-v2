import Foundation
import Testing
@testable import DomainKit

@Test func readerVerseDecodesProxyPayload() throws {
    let data = Data(#"[{"osis":"Rom.8.38","verse":38,"text":"First"},{"osis":"Rom.9.1","verse":1,"text":"Second"}]"#.utf8)
    let verses = try JSONDecoder().decode([ReaderVerse].self, from: data)
    #expect(verses == [
        ReaderVerse(osis: "Rom.8.38", verse: 38, text: "First"),
        ReaderVerse(osis: "Rom.9.1", verse: 1, text: "Second")
    ])
}
