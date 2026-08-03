// App shell: four tabs (Catechisms/Devotions/Reflections/Library) behind a
// native TabView — kept mounted so each tab's own navigation state survives
// switching — with the system tab bar hidden and the design handoff's
// floating pill (FloatingTabBarView) overlaid instead. The floating bar
// only shows at each tab's root: it hides once a tab has pushed anything,
// so it doesn't sit on top of the session/worship flows' own immersive,
// chrome-free screens.
import SwiftUI

struct RootView: View {
    @State private var selected: RootTab = .catechisms
    @State private var catechismsPath = NavigationPath()
    @State private var devotionsPath = NavigationPath()
    @State private var libraryPath = NavigationPath()

    // Library's own screens (document TOC, entry reading page) are plain
    // browsing, not the immersive/chrome-free Session and Worship flows —
    // the tab bar stays up throughout, same as it already did as a
    // placeholder before Library had real content.
    private var isTabBarVisible: Bool {
        switch selected {
        case .catechisms: return catechismsPath.isEmpty
        case .devotions: return devotionsPath.isEmpty
        case .reflections, .library: return true
        }
    }

    var body: some View {
        TabView(selection: $selected) {
            HomeView(path: $catechismsPath).tag(RootTab.catechisms)
            DevotionsTabView(path: $devotionsPath).tag(RootTab.devotions)
            ReflectionsTabView().tag(RootTab.reflections)
            LibraryTabView(path: $libraryPath).tag(RootTab.library)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            if isTabBarVisible {
                FloatingTabBarView(selected: $selected)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTabBarVisible)
    }
}
