// Push targets for the Library tab's NavigationStack (mirrors the
// /library/[confession] and /library/[confession]/[entry] web routes).
// Routes carry the raw ConfessionEntry id (e.g. "WCoF-1-2") rather than a
// URL path segment — there's no URL layer here to keep the two in sync.
import Foundation

enum LibraryRoute: Hashable {
    case document(slug: String)
    case entry(slug: String, entryId: String)
    /// A document row that belongs to a catechism program (WSC/WLC/HC) —
    /// routes into the real, progress-tracked SessionView at that question
    /// instead of a parallel read-only entry page.
    case session(programSlug: String, questionNumber: Int)
}
