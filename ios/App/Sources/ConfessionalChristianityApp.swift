import SwiftUI
import SwiftData
import DomainKit

@main
struct ConfessionalChristianityApp: App {
    // Shared with the widget extension via an App Group container (see
    // DomainKit's makeSharedModelContainer) rather than SwiftData's default
    // app-private store, so a session's progress is visible to the widget's
    // next timeline refresh with no sync step.
    private let container = makeSharedModelContainer()

    // Account session (guest by default); restored from the Keychain at launch.
    @State private var auth = AuthService()

    #if DEBUG
    @State private var showsAuthDebug = UserDefaults.standard.bool(forKey: "AuthDebug")
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let scene = UserDefaults.standard.string(forKey: "VerseReaderFixture") {
                VerseReaderView.fixture(scene)
            } else {
                root
            }
            #else
            root
            #endif
        }
        .modelContainer(container)
    }

    private var root: some View {
        RootView()
            .environment(auth)
            #if DEBUG
            .sheet(isPresented: $showsAuthDebug) {
                AuthDebugView().environment(auth)
            }
            #endif
    }
}
