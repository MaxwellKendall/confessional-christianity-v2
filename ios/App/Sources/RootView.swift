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
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Query private var children: [LocalChild]
    @Query private var sermons: [LordsDayNote]
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var showsSignIn = false
    @State private var showsGuestMerge = false
    @State private var startsCapture = false
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

    private var isTabBarVisible: Bool {
        switch selected {
        case .today: return !todayHidesBar
        case .catechism: return !catechismHidesBar
        case .lordsDay: return !lordsDayHidesBar
        }
    }

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingView(
                    existingNames: children.map(\.name),
                    onBegin: beginCatechism,
                    onSermon: beginSermon,
                    onSignIn: auth.isConfigured ? { showsSignIn = true } : nil
                )
            } else {
                tabs
            }
        }
        .sheet(isPresented: $showsSignIn, onDismiss: {
            auth.cancelCode()
            if sync.pendingGuestMerge != nil && !sync.isSettingsPresenting {
                showsGuestMerge = true
            }
        }) {
            OnboardingSignInView()
        }
        .fullScreenCover(isPresented: $showsGuestMerge) {
            GuestDataMergeHostView(onDone: { showsGuestMerge = false })
        }
        .onChange(of: sync.pendingGuestMerge, initial: true) { _, pending in
            if pending == nil {
                showsGuestMerge = false
            } else if !showsSignIn && !sync.isSettingsPresenting {
                showsGuestMerge = true
            }
        }
        .onChange(of: hasLocalHistory, initial: true) { _, hasHistory in
            if hasHistory { didCompleteOnboarding = true }
        }
        .onChange(of: auth.phase.isSignedIn, initial: true) { _, signedIn in
            if signedIn {
                didCompleteOnboarding = true
                showsSignIn = false
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        #if DEBUG
        let args = UserDefaults.standard
        if args.string(forKey: "OnboardingPage") != nil { return !didCompleteOnboarding }
        if ["StartTab", "OpenSheet", "SeedChildren", "SeedSermonWeek"].contains(where: { args.object(forKey: $0) != nil }) {
            return false
        }
        #endif
        return !didCompleteOnboarding && !hasLocalHistory && !auth.phase.isSignedIn
    }

    private var hasLocalHistory: Bool { !children.isEmpty || !sermons.isEmpty }

    private func beginCatechism(name: String) -> Bool {
        guard !didCompleteOnboarding else { return true }
        do {
            try sync.progressStore(in: modelContext).addChild(name: name)
            todayPath.append(LibraryRoute.session(programSlug: PROGRAMS[0].slug, questionNumber: 1))
            selected = .today
            didCompleteOnboarding = true
            return true
        } catch {
            return false
        }
    }

    private func beginSermon() {
        selected = .lordsDay
        startsCapture = true
        didCompleteOnboarding = true
    }

    private var tabs: some View {
        ZStack {
            TodayView(path: $todayPath, openTab: { selected = $0 }, startCapture: beginSermon)
                .onHidesFloatingTabBarChange { todayHidesBar = $0 }
                .opacity(selected == .today ? 1 : 0)
                .allowsHitTesting(selected == .today)
            CatechismTabView(path: $catechismPath)
                .onHidesFloatingTabBarChange { catechismHidesBar = $0 }
                .opacity(selected == .catechism ? 1 : 0)
                .allowsHitTesting(selected == .catechism)
            LordsDayTabView(
                path: $lordsDayPath, isActive: selected == .lordsDay, startsCapture: $startsCapture
            )
                .onHidesFloatingTabBarChange { lordsDayHidesBar = $0 }
                .opacity(selected == .lordsDay ? 1 : 0)
                .allowsHitTesting(selected == .lordsDay)
        }
        .overlay {
            if isTabBarVisible {
                FloatingTabBarView(selected: $selected)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTabBarVisible)
        #if DEBUG
        .task {
            seedChildrenForScreenshots()
            seedSermonWeekForScreenshots()
        }
        .onChange(of: sync.activeSubject, initial: true) { _, subject in
            guard subject != nil else { return }
            runSyncTestActionIfConfigured()
        }
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

    /// Screenshot hook: `-SeedSermonWeek YES` saves the sample week (Sunday's
    /// notes, a card a day) to the app's own store, only when it has no notes.
    private func seedSermonWeekForScreenshots() {
        guard UserDefaults.standard.bool(forKey: "SeedSermonWeek"), sermons.isEmpty else { return }
        _ = LordsDayFeedFixture.makeFeed("key_point", container: modelContext.container)
    }

    /// Two-simulator sync proof hooks (TKL-1068, TKL-1069):
    /// - `-SyncTestAddChild "Samuel:1"` adds that child on WSC and advances N questions once signed in.
    /// - `-SyncTestEditLatestNoteTitle "<title>"` updates the latest live sermon note's title through `sync.lordsDayStore`.
    private func runSyncTestActionIfConfigured() {
        if let spec = UserDefaults.standard.string(forKey: "SyncTestAddChild") {
            let bits = spec.split(separator: ":").map(String.init)
            if let name = bits.first, !name.isEmpty {
                let advances = Int(bits.dropFirst().first ?? "1") ?? 1
                let store = sync.progressStore(in: modelContext)
                if !store.todayChildren().contains(where: { $0.name == name }),
                   let child = try? store.addChild(name: name) {
                    try? store.selectChild(childId: child.id)
                    _ = store.resumeOrStartTrack(childId: child.id, catechismId: "WSC")
                    for _ in 0..<max(0, advances) {
                        _ = store.advanceQuestion(childId: child.id, catechismId: "WSC", totalQuestions: PROGRAMS[0].totalQuestions)
                    }
                }
            }
        }
        if let newTitle = UserDefaults.standard.string(forKey: "SyncTestEditLatestNoteTitle"), !newTitle.isEmpty {
            let store = sync.lordsDayStore(in: modelContext)
            if let latest = try? modelContext.fetch(FetchDescriptor<LordsDayNote>())
                .filter({ $0.deletedAt == nil })
                .max(by: { $0.updatedAt < $1.updatedAt }),
               latest.sermonTitle != newTitle {
                try? store.update(latest) { $0.sermonTitle = newTitle }
            }
        }
    }
    #endif
}
