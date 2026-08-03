// Push target for the Search surface (mirrors /search) — reached from the
// search icon in SiteHeaderView, present on every tab, so it's registered
// in all four tab NavigationStacks.
import Foundation

enum SearchRoute: Hashable {
    case results
}
