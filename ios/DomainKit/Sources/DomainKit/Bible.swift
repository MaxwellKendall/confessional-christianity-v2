// OSIS bible-reference helpers, ported from src/lib/bible.ts. Only the
// subset Programs/Library need in this phase (Search's toOsis/citationToOsis
// and the full BIBLE_BOOKS browse structure are deferred to the Search
// phase, when they're actually consumed).
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
