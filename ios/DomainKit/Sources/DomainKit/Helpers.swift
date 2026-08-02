// Pure domain helpers, ported from src/lib/helpers.ts. Only the subset
// Programs/Library need in this phase — the id/facet alias grammar
// (parseFacets, getConciseDocId, generateSearchLink, etc.) is deferred to
// the Search phase, when it's actually consumed.
import Foundation

private let footnoteMarkerRegex = try! NSRegularExpression(pattern: "\\[[a-zA-Z0-9]+\\]")

/// Strips ESV/proof-text footnote markers (e.g. "[a]", "[12]") out of
/// confession text.
public func stripFootnoteMarkers(_ text: String = "") -> String {
    let range = NSRange(text.startIndex..., in: text)
    let stripped = footnoteMarkerRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    return stripped
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
