// OSIS bible-reference helpers, ported from src/lib/bible.ts. The full
// BIBLE_BOOKS browse structure isn't ported — nothing in the app browses by
// book yet.
import Foundation

public let bibleBookByAbbreviation: [String: String] = [
    "Gen": "Genesis", "Exod": "Exodus", "Lev": "Leviticus", "Num": "Numbers",
    "Deut": "Deuteronomy", "Josh": "Joshua", "Judg": "Judges", "Ruth": "Ruth",
    "1Sam": "1 Samuel", "2Sam": "2 Samuel", "1Kgs": "1 Kings", "2Kgs": "2 Kings",
    "1Chr": "1 Chronicles", "2Chr": "2 Chronicles", "Ezra": "Ezra", "Neh": "Nehemiah",
    "Esth": "Esther", "Job": "Job", "Ps": "Psalms", "Prov": "Proverbs",
    "Eccl": "Ecclesiastes", "Song": "Song of Solomon", "Isa": "Isaiah", "Jer": "Jeremiah",
    "Lam": "Lamentations", "Ezek": "Ezekiel", "Dan": "Daniel", "Hos": "Hosea",
    "Joel": "Joel", "Amos": "Amos", "Obad": "Obadiah", "Jonah": "Jonah",
    "Mic": "Micah", "Nah": "Nahum", "Hab": "Habakkuk", "Zeph": "Zephaniah",
    "Hag": "Haggai", "Zech": "Zechariah", "Mal": "Malachi", "New": "Testament",
    "Matt": "Matthew", "Mark": "Mark", "Luke": "Luke", "John": "John",
    "Acts": "Acts", "Rom": "Romans", "1Cor": "1 Corinthians", "2Cor": "2 Corinthians",
    "Gal": "Galatians", "Eph": "Ephesians", "Phil": "Philippians", "Col": "Colossians",
    "1Thess": "1 Thessalonians", "2Thess": "2 Thessalonians", "1Tim": "1 Timothy",
    "2Tim": "2 Timothy", "Titus": "Titus", "Phlm": "Philemon", "Heb": "Hebrews",
    "Jas": "James", "1Pet": "1 Peter", "2Pet": "2 Peter", "1John": "1 John",
    "2John": "2 John", "3John": "3 John", "Jude": "Jude", "Rev": "Revelation",
]

/// Renders an OSIS reference ("Ps.73.25-Ps.73.28") as a human-readable
/// citation ("Psalms 73:25-28"), collapsing ranges within a book/chapter.
public func parseOsisBibleReference(_ osisStr: String) -> String {
    guard !osisStr.isEmpty else { return "" }
    if osisStr.contains(",") {
        return osisStr.split(separator: ",", omittingEmptySubsequences: false)
            .map { parseOsisBibleReference(String($0)) }
            .joined(separator: ",")
    }
    let parts = osisStr.components(separatedBy: "-")
    var acc = ""
    for (i, str) in parts.enumerated() {
        let bookChapterVerse = str.components(separatedBy: ".")
        let book = bibleBookByAbbreviation[bookChapterVerse[0]] ?? ""
        let chapterVerse = bookChapterVerse.dropFirst().joined(separator: ":")
        if i == 0 {
            acc = "\(book) \(chapterVerse)"
            continue
        }
        let prevParts = parts[i - 1].components(separatedBy: ".")
        let prevBook = prevParts[0]
        let prevChapter = prevParts.count > 1 ? prevParts[1] : nil
        if prevBook == bookChapterVerse[0], prevChapter == (bookChapterVerse.count > 1 ? bookChapterVerse[1] : nil) {
            let verse = bookChapterVerse.count > 2 ? bookChapterVerse[2] : ""
            acc = "\(acc)-\(verse)"
        } else if prevBook == bookChapterVerse[0] {
            acc = "\(acc)-\(chapterVerse)"
        } else {
            acc = "\(acc) - \(book) \(chapterVerse)"
        }
    }
    return acc
}

private let toOsisMap: [String: String] = {
    var map: [String: String] = ["psalm": "Ps"]
    for (key, value) in bibleBookByAbbreviation {
        map[value.lowercased()] = key
    }
    return map
}()

public func toOsis(_ str: String) -> String? {
    toOsisMap[str.lowercased()]
}

// Books the ESV cites without a chapter number ("Jude 4" means Jude 1:4").
private let singleChapterBooks: Set<String> = ["Obad", "Phlm", "2John", "3John", "Jude"]

private let citationRegex = try! NSRegularExpression(
    pattern: #"^([1-3]?\s?[A-Za-z ]+?)\s+(\d+)(?::(\d+))?(?:\s*-\s*(?:(\d+):)?(\d+))?$"#
)

/// Inverse of parseOsisBibleReference for human citations as the ESV API
/// (and therefore the Algolia citations index) canonicalizes them: "Acts
/// 2:24–27", "Psalm 16:10", "1 Corinthians 15:3–4", "Acts 1:1–2:4",
/// chapter-level refs like "Psalm 73" and "Hebrews 8–10". Returns nil when
/// the string doesn't fit that shape, so callers can degrade gracefully.
public func citationToOsis(_ citation: String) -> String? {
    let normalized = citation
        .replacingOccurrences(of: "[\u{2013}\u{2014}]", with: "-", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let range = NSRange(normalized.startIndex..., in: normalized)
    guard let match = citationRegex.firstMatch(in: normalized, range: range) else { return nil }

    func group(_ i: Int) -> String? {
        guard i < match.numberOfRanges, let r = Range(match.range(at: i), in: normalized) else { return nil }
        return String(normalized[r])
    }

    guard let bookName = group(1), let book = toOsis(bookName) else { return nil }
    let first = group(2) ?? ""
    let second = group(3)
    let endChapter = group(4)
    let end = group(5)

    let chapter: String
    let verse: String?
    if singleChapterBooks.contains(book), second == nil {
        chapter = "1"
        verse = first
    } else {
        chapter = first
        verse = second
    }

    let start = verse.map { "\(book).\(chapter).\($0)" } ?? "\(book).\(chapter)"
    guard let end else { return start }
    if verse == nil, endChapter == nil {
        return "\(start)-\(book).\(end)"
    }
    return "\(start)-\(book).\(endChapter ?? chapter).\(end)"
}
