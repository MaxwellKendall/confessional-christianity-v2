// Push target for the Reflections tab's NavigationStack (mirrors
// /reflections/[slug]). Also registered as a navigationDestination inside
// LibraryTabView's own stack, so a Library entry's "† Commentary" link can
// push the same detail view without a parallel copy — same pattern as
// LibraryRoute.session reusing SessionView across tabs.
import Foundation

enum ReflectionsRoute: Hashable {
    case detail(slug: String)
}
