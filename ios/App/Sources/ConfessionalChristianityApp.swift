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
    private let showsOpening = DailyOpening.claim(in: .standard)

    // Account session (guest by default); restored locally from the Keychain at launch.
    @State private var auth: AuthService

    init() {
        #if DEBUG
        NetworkAudit.installIfConfigured()
        #endif
        _auth = State(initialValue: AuthService())
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            Group {
                if let passage = UserDefaults.standard.string(forKey: "ReaderChapterReference"),
                   let chapter = ReaderChapter.chapterOSIS(for: passage) {
                    NavigationStack {
                        ReaderChapterView(chapterOSIS: chapter, passageOSIS: passage, settings: .load())
                    }
                } else if let session = UserDefaults.standard.string(forKey: "ProofTextSession") {
                    ProofTextSessionFixture(spec: session)
                } else if let scene = UserDefaults.standard.string(forKey: "VerseReaderFixture") {
                    let appearances: [String: ColorScheme] = ["light": .light, "dark": .dark]
                    let appearance = UserDefaults.standard.string(forKey: "VerseReaderFixtureAppearance") ?? ""
                    NavigationStack {
                        VerseReaderView.fixture(scene)
                    }
                    .preferredColorScheme(appearances[appearance])
                } else if let scene = UserDefaults.standard.string(forKey: "LordsDayCaptureFixture") {
                    CaptureFixture(scene: scene)
                } else if let scene = UserDefaults.standard.string(forKey: "LordsDayReviewFixture") {
                    LordsDayReviewFixture(scene: scene)
                } else if let scene = UserDefaults.standard.string(forKey: "LordsDayLandingFixture") {
                    LordsDayLandingFixture(scene: scene)
                } else if let scene = UserDefaults.standard.string(forKey: "LordsDayFeedFixture") {
                    LordsDayFeedFixture(scene: scene)
                } else if let spec = UserDefaults.standard.string(forKey: "LibraryEntry"),
                          let colon = spec.firstIndex(of: ":") {
                    LibraryEntryFixture(slug: String(spec[..<colon]), entryId: String(spec[spec.index(after: colon)...]))
                } else {
                    root
                }
            }
            .environment(auth)
            #else
            root
                .environment(auth)
            #endif
        }
        .modelContainer(container)
    }

    private var root: some View {
        RootView()
            .modifier(LaunchOpening(showing: showsOpening))
    }
}

#if DEBUG
/// Screenshot hook (TKL-878): `-ProofTextSession catechizing-shorter-catechism:32[:Rom.8.30]`
/// opens the session at that question and, with an osis, pushes the proof-text
/// reader on top, so a back tap returns to the same session.
/// `-ProofTextReaderCard verse|notes|end` starts the reader at that card.
private struct ProofTextSessionFixture: View {
    let spec: String
    @State private var path = NavigationPath()

    var body: some View {
        let parts = spec.split(separator: ":").map(String.init)
        if parts.count >= 2, let program = getProgram(parts[0]), let number = Int(parts[1]) {
            NavigationStack(path: $path) {
                SessionView(program: program, path: $path, startQuestion: number)
                    .navigationDestination(for: ScriptureRoute.self) { route in
                        switch route {
                        case .detail(let osis): ScriptureView(osis: osis, path: $path)
                        case .reader(let source): VerseReaderView(source: source)
                        }
                    }
            }
            .task {
                if parts.count >= 3, let question = getQuestion(program, number) {
                    path.append(ScriptureRoute.reader(proofTextReaderSource(program: program, question: question, osis: parts[2])))
                }
            }
        } else {
            Text("Bad ProofTextSession: \(spec)")
        }
    }
}
#endif
