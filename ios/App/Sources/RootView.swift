// App shell: three tabs, Today · Catechism · The Lord's Day (TKL-825), behind
// a plain ZStack, kept mounted so each tab's own navigation state survives
// switching, with the prototype's floating bar (FloatingTabBarView)
// overlaid on top. A real TabView was tried first, but even with its system
// tab bar hidden via .toolbar(.hidden, for: .tabBar), the hidden bar kept
// consuming taps in its own screen-edge strip — e.g. a CTA sitting flush against the bottom (ignoresSafeArea) would register on
// whichever hidden native tab item shared its coordinates instead of its own
// action. The ZStack avoids a system tab bar existing at all, so there's
// nothing hidden-but-still-tappable underneath. Visibility is a property of
// whatever screen is on top, not of which tab it's pushed on:
// immersive/chrome-free screens (Session, Prayer, etc.) opt out via
// .hidesFloatingTabBar() so they read the same whether reached from their
// home tab or deep-linked from another tab's navigationDestination(for:).
import SwiftUI
import SwiftData
import DomainKit

struct RootView: View {
    @State private var selected: RootTab = RootView.initialTab
    @State private var todayPath = NavigationPath()
    @State private var catechismPath = NavigationPath()
    @State private var lordsDayPath = NavigationPath()

    // Since all tabs stay mounted, each tracks its own "does my top
    // screen want the bar hidden" independently — a single shared flag would
    // let a hidden request from an inactive tab hide the bar for whichever
    // tab is actually on screen.
    @State private var todayHidesBar = false
    @State private var catechismHidesBar = false
    @State private var lordsDayHidesBar = false

    #if DEBUG
    @Environment(\.modelContext) private var modelContext
    #endif

    private var isTabBarVisible: Bool {
        switch selected {
        case .today: return !todayHidesBar
        case .catechism: return !catechismHidesBar
        case .lordsDay: return !lordsDayHidesBar
        }
    }

    var body: some View {
        ZStack {
            TodayView(path: $todayPath) { selected = $0 }
                .onHidesFloatingTabBarChange { todayHidesBar = $0 }
                .opacity(selected == .today ? 1 : 0)
                .allowsHitTesting(selected == .today)
            CatechismTabView(path: $catechismPath)
                .onHidesFloatingTabBarChange { catechismHidesBar = $0 }
                .opacity(selected == .catechism ? 1 : 0)
                .allowsHitTesting(selected == .catechism)
            LordsDayTabView(path: $lordsDayPath, isActive: selected == .lordsDay)
                .onHidesFloatingTabBarChange { lordsDayHidesBar = $0 }
                .opacity(selected == .lordsDay ? 1 : 0)
                .allowsHitTesting(selected == .lordsDay)
        }
        .overlay {
            if isTabBarVisible {
                // Placed from the screen's edge, as in the prototype, and left
                // under the keyboard like a system tab bar.
                FloatingTabBarView(selected: $selected)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTabBarVisible)
        #if DEBUG
        .task { seedChildrenForScreenshots() }
        #endif
    }

    private static var initialTab: RootTab {
        #if DEBUG
        // Screenshot hook: `-StartTab today|catechism|lordsDay`.
        if let raw = UserDefaults.standard.string(forKey: "StartTab"), let tab = RootTab(rawValue: raw) {
            return tab
        }
        #endif
        return .today
    }

    #if DEBUG
    /// Screenshot hook: `-SeedChildren "Samuel:9,Thomas:4"` adds those children
    /// on the Shorter Catechism at those questions, only when there are none.
    private func seedChildrenForScreenshots() {
        guard let spec = UserDefaults.standard.string(forKey: "SeedChildren") else { return }
        let store = LocalProgressStore(context: modelContext)
        guard store.todayChildren().isEmpty else { return }
        for part in spec.split(separator: ",") {
            let bits = part.split(separator: ":").map(String.init)
            guard let name = bits.first, let child = try? store.addChild(name: name) else { continue }
            store.startTrack(childId: child.id, catechismId: "WSC", startingQuestion: Int(bits.dropFirst().first ?? "1") ?? 1)
        }
    }
    #endif
}
