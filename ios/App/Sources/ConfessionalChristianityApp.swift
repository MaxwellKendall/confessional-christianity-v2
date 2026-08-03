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

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
