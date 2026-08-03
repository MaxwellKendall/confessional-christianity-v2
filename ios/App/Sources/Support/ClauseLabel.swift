// Shared "Now Showing" clause-label truncation for QuestionCardView and
// LibraryEntryView's single-active-proof-text panel — mirrors
// QuestionCard.tsx's MAX_CLAUSE_LABEL_LENGTH/truncateClause. Keeps the pill
// on one line at the session frame's mobile width: chrome plus a clause
// over ~26 characters wraps it, so long clauses get cut at a word boundary.
import Foundation

let maxClauseLabelLength = 26

func truncateClause(_ text: String) -> String {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = trimmed.last, ".,;:".contains(last) {
        trimmed.removeLast()
    }
    if trimmed.count <= maxClauseLabelLength { return trimmed }
    let cut = String(trimmed.prefix(maxClauseLabelLength))
    if let lastSpace = cut.range(of: " ", options: .backwards) {
        return String(cut[..<lastSpace.lowerBound]) + "\u{2026}"
    }
    return cut + "\u{2026}"
}
