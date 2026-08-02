// Presentation helpers for confession entries, ported from src/lib/entryDisplay.ts.
// Entry titles render in short forms ("Q. 1 — What is the chief end of man?",
// "Chapter 1 · Article 2") derived from the stored titles documented in
// docs/DOMAIN.md (in the Next.js repo).
import Foundation

private let questionPrefixRegex = try! NSRegularExpression(pattern: "^Question\\s(\\d+):\\s*")

private func questionPrefixMatch(_ title: String?) -> (number: String, range: NSRange)? {
    guard let title else { return nil }
    let ns = title as NSString
    guard let match = questionPrefixRegex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) else {
        return nil
    }
    return (ns.substring(with: match.range(at: 1)), match.range)
}

private func stripQuestionPrefix(_ title: String) -> String {
    let ns = title as NSString
    guard let match = questionPrefixRegex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) else {
        return title
    }
    return ns.replacingCharacters(in: match.range, with: "")
}

/// TOC / list row title: "Q. 1 — What is the chief end of man?" for Q&A
/// entries; stored titles ("Article 1", "Chapter 3: Of ...") pass through.
public func tocRowTitle(_ entry: ConfessionEntry) -> String {
    if let match = questionPrefixMatch(entry.title) {
        return "Q. \(match.number) — \(stripQuestionPrefix(entry.title ?? ""))"
    }
    return entry.title ?? entry.id
}

/// Small-caps label above the entry text: "Q. 2", "Chapter 1 · Article 2",
/// "Chapter 3", "Thesis 12", "Rejection 2".
public func entryPageLabel(_ entry: ConfessionEntry, contentById: ContentById? = nil) -> String {
    if let match = questionPrefixMatch(entry.title) {
        return "Q. \(match.number)"
    }
    let head = entry.title?.split(separator: ":").first.map(String.init) ?? entry.id
    let strippedParentId = entry.parent.replacingOccurrences(
        of: "-(articles|rejections)$", with: "", options: .regularExpression
    )
    if let parent = contentById?[strippedParentId], let parentTitle = parent.title,
       head.range(of: "^(Article|Rejection)\\s\\d+$", options: .regularExpression) != nil {
        let parentHead = parentTitle.split(separator: ":").first.map(String.init) ?? parentTitle
        return "\(parentHead) · \(head)"
    }
    return head
}

/// The entry's reading text. Q&A entries render as question + answer lines;
/// footnote markers are stripped for display (proof texts render separately).
public func entryQuoteLines(_ entry: ConfessionEntry) -> [String] {
    let clean = stripFootnoteMarkers(entry.text ?? "")
    if let match = questionPrefixMatch(entry.title) {
        let question = stripQuestionPrefix(entry.title ?? "")
        _ = match
        return ["Q. \(question)", "A. \(clean)"]
    }
    return [clean]
}

/// A run of entry text ending at a footnote marker; the marker's proof texts
/// support exactly this clause, per the source documents' own footnoting.
public struct TextSegment: Equatable, Sendable {
    public let text: String
    public let marker: String?

    public init(text: String, marker: String? = nil) {
        self.text = text
        self.marker = marker
    }
}

private let footnoteSplitRegex = try! NSRegularExpression(pattern: "\\[([a-zA-Z0-9]+)\\]")

private func collapseWhitespace(_ s: String) -> String {
    s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

/// Splits stored text ("...being buried,[1] and continuing...") into clause
/// segments keyed by the marker that closes each one; the tail after the
/// last marker comes through markerless.
public func entryTextSegments(_ text: String = "") -> [TextSegment] {
    let ns = text as NSString
    let matches = footnoteSplitRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    var segments: [TextSegment] = []
    var lastEnd = 0
    for match in matches {
        let segmentText = collapseWhitespace(ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd)))
        let marker = ns.substring(with: match.range(at: 1))
        segments.append(TextSegment(text: segmentText, marker: marker))
        lastEnd = match.range.location + match.range.length
    }
    let tail = collapseWhitespace(ns.substring(from: lastEnd))
    if !tail.isEmpty {
        segments.append(TextSegment(text: tail))
    }
    return segments
}

/// The clause a given footnote marker annotates, for quoting on the scripture
/// canonical page. Leading punctuation belongs to the previous clause (the
/// prior marker sits before the comma), so it is shed along with whitespace.
public func clauseForMarker(_ entry: ConfessionEntry, marker: String) -> String {
    let found = entryTextSegments(entry.text ?? "").first { $0.marker == marker }?.text ?? ""
    let stripped = found.replacingOccurrences(of: "^[\\s,;:.]+", with: "", options: .regularExpression)
    return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// entryQuoteLines with the footnote markers kept in place, as lines of
/// segments — the entry page renders the markers as superscripts anchoring
/// each clause to its proof texts.
public func entryQuoteSegments(_ entry: ConfessionEntry) -> [[TextSegment]] {
    let answer = entryTextSegments(entry.text ?? "")
    if let match = questionPrefixMatch(entry.title) {
        let question = stripQuestionPrefix(entry.title ?? "")
        _ = match
        return [[TextSegment(text: "Q. \(question)")], [TextSegment(text: "A. ")] + answer]
    }
    return [answer]
}

public struct ProofTextRef: Equatable, Sendable {
    public let osis: String
    public let citation: String
}

public struct ProofTextGroup: Equatable, Sendable {
    public let marker: String
    public let refs: [ProofTextRef]
}

/// Proof texts grouped by footnote marker, in the order the markers appear
/// in the text (falling back to the stored key order for any marker that
/// never appears — a data quirk, not the norm).
public func proofTextGroups(_ entry: ConfessionEntry) -> [ProofTextGroup] {
    guard let verses = entry.verses else { return [] }
    let stored = Array(verses.keys)
    let inTextOrder = entryTextSegments(entry.text ?? "")
        .compactMap { $0.marker }
        .filter { stored.contains($0) }
    var seen = Set<String>()
    let markers = (inTextOrder + stored).filter { seen.insert($0).inserted }
    return markers.map { marker in
        ProofTextGroup(
            marker: marker,
            refs: (verses[marker] ?? []).map { osis in
                ProofTextRef(osis: osis, citation: parseOsisBibleReference(osis))
            }
        )
    }
}
