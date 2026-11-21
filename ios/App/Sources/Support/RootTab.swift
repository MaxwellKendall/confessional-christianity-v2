// The three tabs (TKL-825, approved prototype TKL-885): Today (the one thing
// to do now), Catechism (pillar one) and The Lord's Day (pillar two). The
// Library, search and reflections are lookups pushed from inside a tab, and
// Settings sits behind Today's avatar.
import Foundation

enum RootTab: String, CaseIterable, Hashable {
    case today
    case catechism
    case lordsDay

    var label: String {
        switch self {
        case .today: return "Today"
        case .catechism: return "Catechism"
        case .lordsDay: return "Lord's Day"
        }
    }
}
