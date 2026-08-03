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

/// Orders two entry ids in canonical document order, comparing the
/// dash-delimited fragments after the document prefix numerically where
/// both sides are numbers (chapter/question numbers), lexically otherwise
/// (e.g. Canons of Dort's "articles" sorts before "rejections").
public func compareEntryIds(_ aId: String, _ bId: String) -> Bool {
    let a = aId.split(separator: "-").dropFirst().map(String.init)
    let b = bId.split(separator: "-").dropFirst().map(String.init)
    let len = max(a.count, b.count)
    for i in 0..<len {
        guard i < a.count else { return true }
        guard i < b.count else { return false }
        let (av, bv) = (a[i], b[i])
        if let aNum = Int(av), let bNum = Int(bv) {
            if aNum != bNum { return aNum < bNum }
        } else if av != bv {
            return av < bv
        }
    }
    return false
}
