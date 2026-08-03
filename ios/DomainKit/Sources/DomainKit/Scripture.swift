// Read-side accessors for the scripture cross-reference page: every
// confession clause that cites a given proof text, mirrored from
// src/lib/scripture.ts. Built once from the same bundled documents Library
// already loads — no separate content file, just an inverted index over
// each document's footnoted proof texts (reusing proofTextGroups' marker
// ordering rather than re-deriving it).
import Foundation

public struct ScriptureCitingEntry: Equatable, Sendable {
    public let entryId: String
    public let documentSlug: String
    public let documentTitle: String
    public let entryLabel: String
    public let clause: String
}

private func buildScriptureIndex() -> [String: [ScriptureCitingEntry]] {
    var index: [String: [ScriptureCitingEntry]] = [:]
    for doc in LIBRARY_DOCUMENTS {
        guard let content = loadConfessionContent(doc.slug) else { continue }
        for entry in getOrderedLeafEntries(doc.slug) {
            for group in proofTextGroups(entry) {
                let citing = ScriptureCitingEntry(
                    entryId: entry.id,
                    documentSlug: doc.slug,
                    documentTitle: doc.name,
                    entryLabel: entryPageLabel(entry, contentById: content.contentById),
                    clause: clauseForMarker(entry, marker: group.marker)
                )
                for ref in group.refs {
                    index[ref.osis, default: []].append(citing)
                }
            }
        }
    }
    return index
}

private let scriptureIndex: [String: [ScriptureCitingEntry]] = buildScriptureIndex()

/// Every confession clause citing the reference, in library document order.
public func getScriptureCitingEntries(_ osis: String) -> [ScriptureCitingEntry] {
    scriptureIndex[osis] ?? []
}
