// Push targets for the Library surface (mirrors the /library/[confession]
// and /library/[confession]/[entry] web routes). Routes carry the raw
// ConfessionEntry id (e.g. "WCoF-1-2") rather than a URL path segment —
// there's no URL layer here to keep the two in sync. Reachable from
// anywhere a citation can link to a confession entry (Library's own
// NavigationStack, plus the Catechisms/Devotions stacks a ScriptureView's
// "Cited in the Confessions" list can be pushed onto), so it's registered
// in all three, same as ScriptureRoute.
import Foundation

enum LibraryRoute: Hashable {
    case document(slug: String)
    case entry(slug: String, entryId: String)
    /// A document row that belongs to a catechism program (WSC/WLC/HC) —
    /// routes into the real, progress-tracked SessionView at that question
    /// instead of a parallel read-only entry page.
    case session(programSlug: String, questionNumber: Int)
    /// Credits/attribution screen — required so the app's use of Crossway's
    /// ESV® text carries the copyright notice their API terms require it
    /// to display somewhere in the app, not just an "ESV" version label.
    case about
}
