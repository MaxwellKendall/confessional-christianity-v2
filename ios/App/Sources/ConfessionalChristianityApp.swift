import SwiftUI
import SwiftData

@main
struct ConfessionalChristianityApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [LocalCatechismTrack.self, ProgressSettings.self, SeriesProgressRecord.self])
    }
}
