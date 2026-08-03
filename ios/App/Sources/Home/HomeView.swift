// Mirrors the real web home page (src/components/HomeClient.tsx), not the
// /programs index: the WSC devotion run card leading, a quiet "Or choose
// today's devotion" link (deferred — it opens the full devotions hub, which
// hasn't been ported), the "Your Catechism" continue card for whichever
// program the visitor last worked in, a grid to the other three catechisms,
// and a closing line pointing at the Library (also deferred — unbuilt).
import SwiftUI
import SwiftData
import DomainKit

struct HomeView: View {
    private let defaultProgram = PROGRAMS[0]
    private let wscRun = seriesForCatechism("WSC")

    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @State private var track: LocalCatechismTrack?
    @State private var runCompletedDays: [Int] = []

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }
    private var seriesStore: LocalSeriesProgressStore { LocalSeriesProgressStore(context: modelContext) }

    private var trackProgram: ProgramDefinition? {
        guard let track else { return nil }
        return PROGRAMS.first { $0.contentId.rawValue == track.catechismId }
    }

    private var program: ProgramDefinition { trackProgram ?? defaultProgram }

    private var activeTrack: LocalCatechismTrack? { trackProgram != nil ? track : nil }

    private var questionNumber: Int {
        guard let activeTrack else { return 1 }
        return min(activeTrack.currentQuestion, program.totalQuestions)
    }

    private var progressPct: Double {
        guard activeTrack != nil else { return 0 }
        return Double(questionNumber - 1) / Double(program.totalQuestions)
    }

    private var otherPrograms: [ProgramDefinition] {
        PROGRAMS.filter { $0.slug != program.slug }
    }

    private var runTotal: Int { wscRun?.parts.count ?? 0 }
    private var runCurrentDay: Int? { wscRun.map { _ in currentPartDay(runCompletedDays, totalParts: runTotal) } ?? nil }
    private var runCurrentPart: SeriesPart? {
        guard let wscRun, let runCurrentDay else { return nil }
        return wscRun.parts.first { $0.day == runCurrentDay }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SiteHeaderView()
                homeScrollView
            }
            .background(Color.ccCanvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { slug in
                if let program = getProgram(slug) {
                    SessionView(program: program, path: $path)
                }
            }
            .navigationDestination(for: DevotionRoute.self) { route in
                switch route {
                case .series(let slug):
                    if let series = getSeries(slug) {
                        DevotionSeriesView(series: series, path: $path)
                    }
                case .devotion(let slug):
                    if let devotion = getDevotion(slug) {
                        DevotionLandingView(devotion: devotion, path: $path)
                    }
                case .worship(let slug, let startStep):
                    if let devotion = getDevotion(slug) {
                        DevotionWorshipView(devotion: devotion, startStep: startStep, path: $path)
                    }
                case .catechismHandoff(let programSlug, let devotionSlug, let returnStep):
                    if let program = getProgram(programSlug) {
                        SessionView(
                            program: program, path: $path,
                            handoff: DevotionHandoff(devotionSlug: devotionSlug, returnStep: returnStep)
                        )
                    }
                }
            }
            .navigationDestination(for: ScriptureRoute.self) { route in
                switch route {
                case .detail(let osis):
                    ScriptureView(osis: osis, path: $path)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .document(let slug):
                    DocumentTocView(slug: slug, path: $path)
                case .entry(let slug, let entryId):
                    LibraryEntryView(slug: slug, entryId: entryId, path: $path)
                case .session(let programSlug, let questionNumber):
                    if let program = getProgram(programSlug) {
                        SessionView(program: program, path: $path, startQuestion: questionNumber)
                    }
                }
            }
            .task {
                track = store.activeTrack()
                if let wscRun {
                    runCompletedDays = seriesStore.getCompletedDays(wscRun.slug)
                }
            }
        }
        .tint(.ccInk)
    }

    private var homeScrollView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let wscRun {
                        Button {
                            path.append(DevotionRoute.series(wscRun.slug))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(runCurrentDay == nil
                                     ? "All \(runTotal) Parts Complete"
                                     : "Part \(runCurrentDay!) of \(runTotal) \u{00B7} Westminster Shorter Catechism")
                                    .labelCaps(size: 9.5, tracking: 0.14, color: .ccOchre)
                                HStack(alignment: .firstTextBaseline) {
                                    Text(runCurrentDay == nil
                                         ? "The Whole Catechism, Professed"
                                         : (runCompletedDays.isEmpty ? "Begin \u{2014} Part 1" : "Continue \u{2014} Part \(runCurrentDay!)"))
                                        .headingPage()
                                    Spacer()
                                    Text("\u{2192}").font(.ccDisplay(18)).foregroundStyle(.ccOchre)
                                }
                                Text(runCurrentPart.map { "\($0.title) (\($0.citation))" } ?? "Beginning to end, in order")
                                    .font(.ccBody(13.5))
                                    .italic()
                                    .foregroundStyle(.ccInk2)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.ccFill)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 32)
                    }

                    Text("Your Catechism")
                        .labelCaps(size: 9.5, tracking: 0.14)
                        .padding(.bottom, 10)

                    Button {
                        path.append(program.slug)
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(program.title)
                                .headingSection()
                            Text("Q. \(questionNumber) of \(program.totalQuestions)")
                                .labelCaps(size: 9.5, tracking: 0.12)
                                .padding(.top, 8)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.ccHairline)
                                    Rectangle().fill(Color.ccOchre).frame(width: geo.size.width * progressPct)
                                }
                            }
                            .frame(height: 3)
                            .padding(.top, 10)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.ccFill)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 32)

                    Text("Explore Other Catechisms")
                        .labelCaps(size: 9.5, tracking: 0.14)
                        .padding(.bottom, 10)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(otherPrograms, id: \.slug) { p in
                            Button {
                                path.append(p.slug)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(p.shortTitle)
                                        .font(.ccDisplay(14, semibold: true))
                                        .foregroundStyle(.ccInk)
                                        .multilineTextAlignment(.leading)
                                    Text("\(p.totalQuestions) Q&A")
                                        .labelCaps(size: 9, tracking: 0.1)
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.ccFill)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Spacer()
                        Text("Or explore the confessions and catechisms directly in the Library.")
                            .font(.ccBody(13))
                            .italic()
                            .foregroundStyle(.ccInk2)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.top, 28)
                    .padding(.top, 20)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.ccHairline).frame(height: 1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 100)
                .frame(maxWidth: 704)
                .frame(maxWidth: .infinity)
            }
    }
}
