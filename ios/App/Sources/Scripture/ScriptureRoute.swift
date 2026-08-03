// Push target for a scripture cross-reference page (mirrors
// /scripture/[osis]) — reached by tapping a proof-text citation, either in
// Library's entry view or in a catechism session's QuestionCardView. The
// session flow is itself reachable from three different tabs' own
// NavigationStacks (Catechisms, Devotions' handoff, Library's), so this
// route is registered in all of them, same as LibraryRoute.session.
import Foundation

enum ScriptureRoute: Hashable {
    case detail(osis: String)
}
