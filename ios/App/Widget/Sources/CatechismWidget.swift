// A Home Screen widget previewing the visitor's active catechism session —
// same "Your Catechism" data HomeView shows, read straight from the shared
// App Group SwiftData store (see DomainKit's makeSharedModelContainer) and
// DomainKit's bundled question text, so this renders with no network and no
// dependency on the app being foregrounded.
import WidgetKit
import SwiftUI
import SwiftData
import DomainKit

struct CatechismEntry: TimelineEntry {
    let date: Date
    let kind: String
    let title: String
    let questionNumber: Int
    let totalQuestions: Int
    let question: String
    let answer: String
    // Nil when the question's first proof text isn't in the bundled ESV set
    // yet (bible-text.json is a partial, append-only cache) — the widget
    // never makes a network call, so it just omits the scripture block.
    let scriptureQuote: String?
    let scriptureRef: String?

    var progress: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(questionNumber - 1) / Double(totalQuestions)
    }

    // The same WSC Q1 a fresh install's HomeView shows before any track
    // exists — a real, honest default rather than placeholder-looking copy.
    // Used only for WidgetKit's `placeholder(in:)`, which must return
    // instantly with no store access.
    static let placeholder = CatechismEntry(
        date: Date(),
        kind: "Family Catechesis",
        title: "Westminster Shorter Catechism",
        questionNumber: 1,
        totalQuestions: 107,
        question: "What is the chief end of man?",
        answer: "Man's chief end is to glorify God, and to enjoy him forever.",
        scriptureQuote: "So, whether you eat or drink, or whatever you do, do all to the glory of God.",
        scriptureRef: "1 Corinthians 10:31"
    )
}

struct CatechismProvider: TimelineProvider {
    func placeholder(in context: Context) -> CatechismEntry {
        .placeholder
    }

    // WidgetKit invokes TimelineProvider's completion-handler methods on the
    // main thread, so `assumeIsolated` (rather than `Task { @MainActor in }`,
    // which would make the escaping `completion` closure cross an isolation
    // boundary — a Swift 6 data-race error) lets this call MainActor-bound
    // DomainKit store methods synchronously with no thread hop.
    func getSnapshot(in context: Context, completion: @escaping (CatechismEntry) -> Void) {
        completion(MainActor.assumeIsolated { Self.loadEntry() })
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatechismEntry>) -> Void) {
        let entry = MainActor.assumeIsolated { Self.loadEntry() }
        // Progress only changes from inside a session, which isn't running
        // while this widget is visible, so an hourly refresh (rather than a
        // tighter one) is plenty to catch up next time the visitor studies
        // and returns to the Home Screen.
        let nextRefresh = Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    @MainActor
    private static func loadEntry() -> CatechismEntry {
        let context = ModelContext(makeSharedModelContainer())
        let store = LocalProgressStore(context: context)
        let track = store.activeTrack()
        let program = track
            .flatMap { t in PROGRAMS.first { $0.contentId.rawValue == t.catechismId } }
            ?? PROGRAMS[0]
        let questionNumber = track.map { min($0.currentQuestion, program.totalQuestions) } ?? 1
        let q = getQuestion(program, questionNumber)
        let firstProofText = q?.proofTexts.first
        let scriptureQuote = firstProofText.flatMap(bundledEsvText(for:))
        return CatechismEntry(
            date: Date(),
            kind: program.kind,
            title: program.title,
            questionNumber: questionNumber,
            totalQuestions: program.totalQuestions,
            question: q?.question ?? "",
            answer: q?.answer ?? "",
            scriptureQuote: scriptureQuote,
            scriptureRef: scriptureQuote != nil ? firstProofText.map(parseOsisBibleReference) : nil
        )
    }
}

struct CatechismWidget: Widget {
    let kind = "CatechismWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CatechismProvider()) { entry in
            CatechismWidgetView(entry: entry)
        }
        .configurationDisplayName("Continue Your Catechism")
        .description("See your current question and pick up where you left off — fully offline.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.ccHairline)
                Rectangle().fill(Color.ccOchre).frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}

struct CatechismWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CatechismEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallCatechismView(entry: entry)
            case .systemMedium:
                MediumCatechismView(entry: entry)
            default:
                LargeCatechismView(entry: entry)
            }
        }
        .containerBackground(Color.ccCard, for: .widget)
    }
}

private struct SmallCatechismView: View {
    let entry: CatechismEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .labelCaps(size: 8.5, tracking: 0.1)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text("Q. \(entry.questionNumber)")
                .font(.ccDisplay(22, semibold: true))
                .foregroundStyle(.ccInk)
            Text("of \(entry.totalQuestions)")
                .labelCaps(size: 8, tracking: 0.1)
            ProgressBar(progress: entry.progress)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// Centered, stacked layout rather than the two-column one this replaced —
// there isn't room at this size for the question, the answer, and the
// scripture together, so the answer is the one dropped (it's a tap away in
// the app; the proof text is the detail a preview widget can't get anywhere
// else).
private struct MediumCatechismView: View {
    let entry: CatechismEntry

    var body: some View {
        VStack(spacing: 6) {
            Text("Question \(entry.questionNumber) of \(entry.totalQuestions)")
                .labelCaps(size: 8, tracking: 0.1)
            ProgressBar(progress: entry.progress)

            VStack(spacing: 3) {
                Text(entry.question)
                    .font(.ccDisplay(13, semibold: true))
                    .foregroundStyle(.ccInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let quote = entry.scriptureQuote, let ref = entry.scriptureRef {
                    Text(quote)
                        .font(.ccBody(10.5))
                        .italic()
                        .foregroundStyle(.ccInk2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(ref)
                        .labelCaps(size: 8, tracking: 0.06, color: .ccOchre)
                }
            }
            .padding(.top, 2)
            .frame(maxHeight: .infinity)

            ContinueRow()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LargeCatechismView: View {
    let entry: CatechismEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(entry.title)
                .labelCaps(size: 9, tracking: 0.12)
            Text("Q. \(entry.questionNumber) of \(entry.totalQuestions)")
                .font(.ccDisplay(16, semibold: true))
                .foregroundStyle(.ccInk)
            ProgressBar(progress: entry.progress)
                .padding(.bottom, 4)

            Text(entry.question)
                .font(.ccDisplay(15, semibold: true))
                .foregroundStyle(.ccInk)
                .lineLimit(2)

            Text(entry.answer)
                .font(.ccBody(13.5))
                .foregroundStyle(.ccInk2)
                .lineLimit(4)

            if let quote = entry.scriptureQuote, let ref = entry.scriptureRef {
                VStack(alignment: .leading, spacing: 3) {
                    Text("The Scripture Behind It")
                        .labelCaps(size: 7.5, tracking: 0.1)
                    Text(quote)
                        .font(.ccBody(11.5))
                        .italic()
                        .foregroundStyle(.ccInk2)
                        .lineLimit(3)
                    Text(ref)
                        .labelCaps(size: 8, tracking: 0.06, color: .ccOchre)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            ContinueRow()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// Shared footer link row for the medium/large layouts — the design doc's
// bottom CTA, separated from the content above by a hairline rule.
private struct ContinueRow: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
            HStack {
                Text("Continue")
                    .font(.ccDisplay(12, semibold: true))
                    .foregroundStyle(.ccInk)
                Spacer()
                Text("\u{2192}")
                    .font(.ccBody(14))
                    .foregroundStyle(.ccOchre)
            }
            .padding(.top, 10)
        }
    }
}
