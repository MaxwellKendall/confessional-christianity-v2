// Client-safe content access for programs: catechism questions (the data a
// session teaches — bundled, it IS the program) and the authored prayers.
// Ported from src/lib/programContent.ts. Every program is a catechism today
// (WSC, CFYC, WLC, HC); each just points at its own normalized-data document
// and its own prayers file.
import Foundation

// Add a case here (and to PROGRAMS in Programs.swift) for each new catechism
// program.
public enum ContentId: String, Sendable {
    case wsc = "WSC"
    case wlc = "WLC"
    case hc = "HC"
    case cfyc = "CFYC"
}

// `.copy("BundledContent")` in Package.swift preserves the folder structure
// verbatim, so a file at Sources/DomainKit/BundledContent/a/b/c.json lands in
// the bundle at "BundledContent/a/b/c.json" — split the resource path into
// the subdirectory Bundle.module expects plus the bare filename it looks up.
// (Named deliberately not "Resources": a subdirectory literally named
// "Resources" inside a .bundle trips up codesign's old-style-bundle format
// detection on current Xcode/macOS — see the sibling content-sync script.)
private func resourceURL(_ path: String, extension ext: String) -> URL {
    let full = "BundledContent/" + path
    let dir = (full as NSString).deletingLastPathComponent
    let name = (full as NSString).lastPathComponent
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: dir) else {
        fatalError("DomainKit: missing bundled resource \(full).\(ext)")
    }
    return url
}

private func loadDocument(_ resourcePath: String) -> ConfessionDocumentJson {
    let url = resourceURL(resourcePath, extension: "json")
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ConfessionDocumentJson.self, from: data)
    } catch {
        fatalError("DomainKit: failed to decode \(resourcePath).json: \(error)")
    }
}

private let docsByContentId: [ContentId: ConfessionDocumentJson] = [
    .wsc: loadDocument("normalized-data/westminster/wsc"),
    .wlc: loadDocument("normalized-data/westminster/wlc"),
    .hc: loadDocument("normalized-data/three-forms-of-unity/heidelberg-catechism"),
    .cfyc: loadDocument("normalized-data/miscellany/catechism-young-children"),
]

/// The two `ProgramDefinition` fields this module needs — kept structural
/// (rather than depending on the full type) to avoid a circular reference,
/// mirroring the TS module's own comment.
public protocol ProgramRef {
    var contentId: ContentId { get }
    var slug: String { get }
}

extension ProgramDefinition: ProgramRef {}

public struct ProgramQuestion: Equatable, Sendable {
    public let number: Int
    public let question: String
    public let answer: String
    /// OSIS proof-text refs, deduped, in footnote order
    public let proofTexts: [String]
}

private let questionPrefixStripRegex = try! NSRegularExpression(pattern: "^Question\\s\\d+:\\s*")
private let questionNumberRegex = try! NSRegularExpression(pattern: "^Question\\s(\\d+):")

// The question number lives in `entry.number` for every catechism except the
// Heidelberg — its `number` is the raw content-array position (Lord's Day
// headers share the sequence), so the traditional Q number has to come from
// the title instead. Reading the title everywhere keeps this one lookup, not
// a per-catechism branch.
private func questionNumberOf(_ entry: ConfessionEntry) -> Int? {
    if let title = entry.title {
        let ns = title as NSString
        if let match = questionNumberRegex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) {
            return Int(ns.substring(with: match.range(at: 1)))
        }
    }
    return entry.number
}

private func stripQuestionPrefixLiteral(_ title: String) -> String {
    let ns = title as NSString
    let range = NSRange(location: 0, length: ns.length)
    return questionPrefixStripRegex.stringByReplacingMatches(in: title, range: range, withTemplate: "")
}

private func findEntry(_ contentId: ContentId, _ n: Int) -> ConfessionEntry? {
    docsByContentId[contentId]?.content.first { !$0.isParent && questionNumberOf($0) == n }
}

public func getQuestion(_ program: ProgramRef, _ n: Int) -> ProgramQuestion? {
    guard let entry = findEntry(program.contentId, n) else { return nil }
    let proofTexts: [String] = {
        guard let verses = entry.verses else { return [] }
        var seen = Set<String>()
        return verses.keys.sorted().flatMap { verses[$0] ?? [] }.filter { seen.insert($0).inserted }
    }()
    return ProgramQuestion(
        number: n,
        question: stripQuestionPrefixLiteral(entry.title ?? ""),
        answer: stripFootnoteMarkers(entry.text ?? ""),
        proofTexts: proofTexts
    )
}

/// The catechism entry id (e.g. "WSC-1") a question corresponds to — used to
/// key reflections and clause-level citations, which key off the raw entry.
public func entryId(_ program: ProgramRef, _ n: Int) -> String? {
    findEntry(program.contentId, n)?.id
}

/// Every question's number and text, in order — the index behind "Jump to
/// Question", which browses/searches the whole catechism.
public func listQuestions(_ program: ProgramRef) -> [(number: Int, question: String)] {
    (docsByContentId[program.contentId]?.content ?? [])
        .filter { !$0.isParent }
        .compactMap { entry -> (number: Int, question: String)? in
            guard let number = questionNumberOf(entry) else { return nil }
            return (number, stripQuestionPrefixLiteral(entry.title ?? ""))
        }
        .sorted { $0.number < $1.number }
}

// Per-clause citation markers for the answer: the answer's own segments (so
// markers render inline) plus the proof texts each marker supports, so a tap
// can swap in that clause's specific verse.
public func getQuestionCitations(_ program: ProgramRef, _ n: Int) -> (answerSegments: [TextSegment], groups: [ProofTextGroup])? {
    guard let entry = findEntry(program.contentId, n) else { return nil }
    let segments = entryQuoteSegments(entry)
    let answerLine = segments.count > 1 ? segments[1] : []
    let answerSegments = answerLine.filter { $0.text != "A. " }
    return (answerSegments, proofTextGroups(entry))
}

// Each program's authored prayers, keyed by its slug — add an entry here
// alongside a bundled prayers.json once a program has any.
private func loadPrayers(_ resourcePath: String) -> [String: String] {
    let url = resourceURL(resourcePath, extension: "json")
    guard let data = try? Data(contentsOf: url),
          let prayers = try? JSONDecoder().decode([String: String].self, from: data)
    else {
        return [:]
    }
    return prayers
}

private let prayersBySlug: [String: [String: String]] = [
    "catechizing-shorter-catechism": loadPrayers("content/programs/catechizing-shorter-catechism/prayers"),
]

// Authored prayers are written progressively; nil means "prayer not yet
// written", which the program surfaces honestly.
public func getPrayer(_ program: ProgramRef, _ questionNumber: Int, childName: String) -> String? {
    guard let raw = prayersBySlug[program.slug]?[String(questionNumber)] else { return nil }
    return raw.replacingOccurrences(of: "{name}", with: childName)
}

public func hasPrayer(_ program: ProgramRef, _ questionNumber: Int) -> Bool {
    prayersBySlug[program.slug]?[String(questionNumber)] != nil
}
