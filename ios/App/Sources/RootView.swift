// App shell: four tabs (Catechisms/Devotions/Reflections/Library) behind a
// native TabView — kept mounted so each tab's own navigation state survives
// switching — with the system tab bar hidden and the design handoff's
// floating pill (FloatingTabBarView) overlaid instead. Visibility is a
// property of whatever screen is on top, not of which tab it's pushed on:
// immersive/chrome-free screens (Session, Worship, Prayer, etc.) opt out via
// .hidesFloatingTabBar() so they read the same whether reached from their
// home tab or deep-linked from another tab's navigationDestination(for:).
import SwiftUI

struct RootView: View {
    @State private var selected: RootTab = .catechisms
    @State private var catechismsPath = NavigationPath()
    @State private var devotionsPath = NavigationPath()
    @State private var reflectionsPath = NavigationPath()
    @State private var libraryPath = NavigationPath()

    // Since all four tabs stay mounted, each tracks its own "does my top
    // screen want the bar hidden" independently — a single shared flag would
    // let a hidden request from an inactive tab hide the bar for whichever
    // tab is actually on screen.
    @State private var catechismsHidesBar = false
    @State private var devotionsHidesBar = false
    @State private var reflectionsHidesBar = false
    @State private var libraryHidesBar = false

    private var isTabBarVisible: Bool {
        switch selected {
        case .catechisms: return !catechismsHidesBar
        case .devotions: return !devotionsHidesBar
        case .reflections: return !reflectionsHidesBar
        case .library: return !libraryHidesBar
        }
    }

    var body: some View {
        TabView(selection: $selected) {
            HomeView(path: $catechismsPath)
                .onHidesFloatingTabBarChange { catechismsHidesBar = $0 }
                .tag(RootTab.catechisms)
            DevotionsTabView(path: $devotionsPath)
                .onHidesFloatingTabBarChange { devotionsHidesBar = $0 }
                .tag(RootTab.devotions)
            ReflectionsTabView(path: $reflectionsPath)
                .onHidesFloatingTabBarChange { reflectionsHidesBar = $0 }
                .tag(RootTab.reflections)
            LibraryTabView(path: $libraryPath)
                .onHidesFloatingTabBarChange { libraryHidesBar = $0 }
                .tag(RootTab.library)
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
