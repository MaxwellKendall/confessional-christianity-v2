// The four primary sections from the design handoff's floating tab bar
// (design_handoff_confessional_christianity/18c-floating-tab-bar.dc.html),
// mirroring web's SiteHeader nav row (Catechisms/Devotions/Resources/
// Library) with "Resources" relabeled "Reflections" per that handoff.
import Foundation

enum RootTab: Int, CaseIterable, Hashable {
    case catechisms
    case devotions
    case reflections
    case library

    var label: String {
        switch self {
        case .catechisms: return "Catechisms"
        case .devotions: return "Devotions"
        case .reflections: return "Reflections"
        case .library: return "Library"
        }
    }
}
