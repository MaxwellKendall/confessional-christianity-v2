import Foundation

public struct ReaderChapter: Decodable, Sendable {
    public struct Verse: Sendable {
        public let osis: String
        public let number: Int
        public let range: NSRange
    }

    private struct Anchor: Decodable {
        let osis: String
        let verse: Int
        let offset: Int
    }

    private enum CodingKeys: String, CodingKey {
        case text, anchors
    }

    public let text: String
    public let verses: [Verse]

    public init(from decoder: any Decoder) throws {
        let response = try decoder.container(keyedBy: CodingKeys.self)
        let text = try response.decode(String.self, forKey: .text)
        let anchors = try response.decode([Anchor].self, forKey: .anchors)
        let length = text.utf16.count
        self.text = text
        guard !anchors.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .anchors, in: response, debugDescription: "Missing verse anchors")
        }
        verses = try anchors.enumerated().map { index, anchor in
            let end = index + 1 < anchors.count ? anchors[index + 1].offset : length
            // The server reports JavaScript string indices, which are UTF-16 offsets.
            guard anchor.offset >= 0, end <= length, anchor.offset < end else {
                throw DecodingError.dataCorruptedError(forKey: .anchors, in: response, debugDescription: "Invalid verse offsets")
            }
            let startOffset = text.utf16.index(text.utf16.startIndex, offsetBy: anchor.offset)
            let endOffset = text.utf16.index(text.utf16.startIndex, offsetBy: end)
            guard let start = String.Index(startOffset, within: text),
                  let end = String.Index(endOffset, within: text),
                  let first = text[start..<end].firstIndex(where: { !$0.isWhitespace }),
                  let last = text[start..<end].lastIndex(where: { !$0.isWhitespace }) else {
                throw DecodingError.dataCorruptedError(forKey: .anchors, in: response, debugDescription: "Invalid verse bounds")
            }
            return Verse(osis: anchor.osis, number: anchor.verse, range: NSRange(first...last, in: text))
        }
    }

    public static func chapterOSIS(for reference: String) -> String? {
        let parts = reference.prefix { $0 != "-" && $0 != "," }.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, bibleBookByAbbreviation[String(parts[0])] != nil,
              let chapter = Int(parts[1]), chapter > 0 else { return nil }
        return "\(parts[0]).\(chapter)"
    }

    /// The ESV proxy reads e.g. "Jude 1" as verse 1. Its bare book query
    /// returns the entire chapter.
    public static func queryOSIS(for chapter: String) -> String {
        let book = String(chapter.prefix { $0 != "." })
        return singleChapterBooks.contains(book) && chapter == "\(book).1" ? book : chapter
    }

    public func matches(_ chapter: String) -> Bool {
        verses.allSatisfy { Self.chapterOSIS(for: $0.osis) == chapter }
    }

    public static func contains(_ verse: String, in passage: String) -> Bool {
        passage.split(separator: ",").contains {
            osisReference($0.trimmingCharacters(in: .whitespaces), containsVerse: verse)
        }
    }
}
