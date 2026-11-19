// The primary sections of the floating tab bar, from the design handoff
// (design_handoff_confessional_christianity/18c-floating-tab-bar.dc.html).
// Devotions was cut in TKL-856; TKL-825 rebuilds the bar around three tabs.
import Foundation

enum RootTab: Int, CaseIterable, Hashable {
    case catechisms
    case reflections
    case library

    var label: String {
        switch self {
        case .catechisms: return "Catechisms"
        case .reflections: return "Reflections"
        case .library: return "Library"
        }
    }
}
