// Push target for a scripture cross-reference page (mirrors
// /scripture/[osis]) — reached by tapping a proof-text citation, either in
// Library's entry view or in a catechism session's QuestionCardView. The
// session flow is itself reachable from more than one tab's own
// NavigationStack (Catechisms, Library), so this route is registered in
// each of them, same as LibraryRoute.session.
import Foundation
import DomainKit

enum ScriptureRoute: Hashable {
    case detail(osis: String)
    /// The verse-by-verse reader. A catechism session's proof text opens it
    /// (TKL-878); Library and Search keep `.detail` (spec decision R7).
    case reader(ReaderSource)
}
