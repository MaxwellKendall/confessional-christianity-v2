// Push targets shared by HomeView's NavigationStack for the devotions
// surface (mirrors the /devotions/[slug] and /devotions/[slug]/worship
// web routes) plus the one program-session push that can originate from
// inside a devotion (the Professing Faith step's hand-off).
import Foundation

enum DevotionRoute: Hashable {
    case series(String)
    case devotion(String)
    case worship(slug: String, startStep: Int)
    /// The Professing Faith hand-off: push into the shared SessionView, but
    /// remembering where to return — mirrors SessionClient's `?devotion=`
    /// query param, since this app has no URL layer to carry it.
    case catechismHandoff(programSlug: String, devotionSlug: String, returnStep: Int)
}

/// What SessionView needs to know when it was reached via a devotion's
/// Professing Faith step, so "Next" becomes "Continue Worship" and advancing
/// returns to the worship stepper instead of staying on the question.
struct DevotionHandoff: Hashable {
    let devotionSlug: String
    let returnStep: Int
}
