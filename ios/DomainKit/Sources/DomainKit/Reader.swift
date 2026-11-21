// Pure logic for the verse-by-verse reader (TKL-873, spec "the verse-by-verse
// reader", AC 3, 4 and 9's model half): the card sequence for each entry
// point, the confession clauses citing one verse, the reader settings, and
// the verse-card font step from the approved TKL-838 design. No SwiftUI, no
// network and no stored ESV text: verses arrive from the /api/esv proxy.
import Foundation

/// One verse as the server splits a passage (`GET /api/esv?verses=true`).
public struct ReaderVerse: Decodable, Equatable, Hashable, Sendable {
    public let osis: String
    public let verse: Int
    public let text: String

    public init(osis: String, verse: Int, text: String) {
        self.osis = osis
        self.verse = verse
        self.text = text
    }
}

/// The reader's two entry points (spec: no other way in).
public enum ReaderSource: Equatable, Hashable, Sendable {
    /// This week's sermon text, re-read on `weekday` (day `dayIndex` of `daysInWeek`).
    case sermonText(passageOsis: String, weekday: String, dayIndex: Int, daysInWeek: Int, notesKeyPoint: String?)
    /// A catechism question's proof text.
    case proofText(catechismSlug: String, questionNumber: Int, question: String, answer: String, osis: String)
}

public enum ReaderCard: Equatable, Hashable, Sendable {
    case intro
    case verse(ReaderVerse)
    case notes(String)
    case end
}

/// Sermon: intro, verses, notes (only with a key point), end.
/// Proof text: intro, verses, end. No verses: intro and end only.
public func readerCards(for source: ReaderSource, verses: [ReaderVerse]) -> [ReaderCard] {
    guard !verses.isEmpty else { return [.intro, .end] }
    var cards: [ReaderCard] = [.intro]
    cards += verses.map(ReaderCard.verse)
    if case let .sermonText(_, _, _, _, keyPoint?) = source {
        cards.append(.notes(keyPoint))
    }
    cards.append(.end)
    return cards
}

// MARK: - Citations per verse

/// A comparable position in the canon: (book index, chapter, verse).
private struct OsisPoint: Comparable {
    let book: Int
    let chapter: Int
    let verse: Int

    static func < (a: OsisPoint, b: OsisPoint) -> Bool {
        (a.book, a.chapter, a.verse) < (b.book, b.chapter, b.verse)
    }
}

private let bookIndexByOsis: [String: Int] = Dictionary(
    uniqueKeysWithValues: BIBLE_BOOKS.enumerated().map { ($1.osis, $0) }
)

/// "Rom.8.16" → a point; a chapter-only "Rom.8" takes `chapterVerse`
/// (1 at a range start, Int.max at a range end). Nil when it doesn't parse.
private func osisPoint(_ ref: String, chapterVerse: Int) -> OsisPoint? {
    let parts = ref.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2 || parts.count == 3,
          let book = bookIndexByOsis[String(parts[0])],
          let chapter = Int(parts[1]) else { return nil }
    if parts.count == 2 { return OsisPoint(book: book, chapter: chapter, verse: chapterVerse) }
    guard let verse = Int(parts[2]) else { return nil }
    return OsisPoint(book: book, chapter: chapter, verse: verse)
}

/// True when a cited reference ("Rom.8.29", "Rom.8.28-Rom.8.30",
/// "Rom.7.24-Rom.8.2", "Rom.8", "Rom.8-Rom.9") includes the single verse.
public func osisReference(_ reference: String, containsVerse verseOsis: String) -> Bool {
    guard let verse = osisPoint(verseOsis, chapterVerse: -1), verse.verse >= 0 else { return false }
    let ends = reference.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    guard ends.count == 1 || ends.count == 2,
          let start = osisPoint(ends[0], chapterVerse: 1),
          let end = osisPoint(ends[ends.count - 1], chapterVerse: Int.max) else { return false }
    return start <= verse && verse <= end
}

/// Every cited osis key and its citing entries, in library order.
private let citedReferences: [(osis: String, entries: [ScriptureCitingEntry])] = allScriptureIndexEntries()

/// Every confession clause citing the verse, exactly or through a range (or
/// whole chapter) containing it, de-duplicated by entry id, in library order.
public func citingEntries(forVerse osis: String) -> [ScriptureCitingEntry] {
    var matches: [ScriptureCitingEntry] = []
    for (ref, entries) in citedReferences where osisReference(ref, containsVerse: osis) {
        matches += entries
    }
    var seen = Set<String>()
    return matches
        .filter { seen.insert($0.entryId).inserted }
        .sorted { libraryOrder($0) < libraryOrder($1) }
}

private let libraryOrderByEntryId: [String: Int] = {
    var order: [String: Int] = [:]
    for doc in LIBRARY_DOCUMENTS {
        for entry in getOrderedLeafEntries(doc.slug) where order[entry.id] == nil {
            order[entry.id] = order.count
        }
    }
    return order
}()

private func libraryOrder(_ entry: ScriptureCitingEntry) -> Int {
    libraryOrderByEntryId[entry.entryId] ?? Int.max
}

// MARK: - Settings

/// The reader's settings sheet (spec AC 9). Persisted in UserDefaults.
public struct ReaderSettings: Equatable, Sendable {
    public static let textSizeRange = 0...4
    public static let defaultTextSize = 2

    /// 0–4, five steps; out-of-range values clamp.
    public var textSize: Int {
        didSet { textSize = Self.clampTextSize(textSize) }
    }
    /// Verse numbers in the in-context chapter view.
    public var showVerseNumbers: Bool
    /// Confession seals on verse cards and marks in chapters.
    public var showConfessionMarks: Bool
    public var dark: Bool

    public init(
        textSize: Int = ReaderSettings.defaultTextSize,
        showVerseNumbers: Bool = true,
        showConfessionMarks: Bool = true,
        dark: Bool = false
    ) {
        self.textSize = Self.clampTextSize(textSize)
        self.showVerseNumbers = showVerseNumbers
        self.showConfessionMarks = showConfessionMarks
        self.dark = dark
    }

    static func clampTextSize(_ value: Int) -> Int {
        min(max(value, textSizeRange.lowerBound), textSizeRange.upperBound)
    }

    private enum Key {
        static let textSize = "reader.textSize"
        static let showVerseNumbers = "reader.showVerseNumbers"
        static let showConfessionMarks = "reader.showConfessionMarks"
        static let dark = "reader.dark"
    }

    public static func load(from defaults: UserDefaults = .standard) -> ReaderSettings {
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        let base = ReaderSettings()
        return ReaderSettings(
            textSize: defaults.object(forKey: Key.textSize) == nil ? base.textSize : defaults.integer(forKey: Key.textSize),
            showVerseNumbers: bool(Key.showVerseNumbers, base.showVerseNumbers),
            showConfessionMarks: bool(Key.showConfessionMarks, base.showConfessionMarks),
            dark: bool(Key.dark, base.dark)
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(textSize, forKey: Key.textSize)
        defaults.set(showVerseNumbers, forKey: Key.showVerseNumbers)
        defaults.set(showConfessionMarks, forKey: Key.showConfessionMarks)
        defaults.set(dark, forKey: Key.dark)
    }
}

// MARK: - Verse card font size

/// The design's verse-card size in points: 32 / 27 / 23 / 20 for text under
/// 70 / 120 / 180 characters and longer, plus 2 points per settings step
/// away from the default (step 2).
public func readerVerseFontSize(textLength: Int, textSize: Int) -> Double {
    let base: Double = textLength < 70 ? 32 : textLength < 120 ? 27 : textLength < 180 ? 23 : 20
    let offset = ReaderSettings.clampTextSize(textSize) - ReaderSettings.defaultTextSize
    return base + Double(offset * 2)
}
