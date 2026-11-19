// The Catechisms tab's home: the "Your Catechism" continue card for whichever
// program the visitor last worked in, a grid to the other catechisms, and a
// closing line pointing at the Library. Devotions and reading plans led this
// screen until TKL-856 cut them; it is a placeholder until the Today home
// screen (TKL-825) replaces it.
import SwiftUI
import SwiftData
import DomainKit

struct HomeView: View {
    private let defaultProgram = PROGRAMS[0]

    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @State private var track: LocalCatechismTrack?

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }

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

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SiteHeaderView(path: $path)
                homeScrollView
            }
            .background(Color.ccCard)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { slug in
                if let program = getProgram(slug) {
                    SessionView(program: program, path: $path)
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
                case .about:
                    AboutView(path: $path)
                }
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(path: $path)
            }
            .task {
                track = store.activeTrack()
            }
        }
        .tint(.ccInk)
    }

    private var homeScrollView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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

                    // An odd item out left alone in a 2-column grid leaves a
                    // dangling half-empty row; give it the full row's width
                    // instead so every row reads as a complete grid.
                    let oddCount = otherPrograms.count % 2
                    let paired = otherPrograms.dropLast(oddCount)
                    let remainder = otherPrograms.suffix(oddCount)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(paired, id: \.slug) { p in
                            OtherCatechismCard(program: p, path: $path)
                        }
                    }
                    ForEach(remainder, id: \.slug) { p in
                        OtherCatechismCard(program: p, path: $path)
                            .padding(.top, 12)
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

private struct OtherCatechismCard: View {
    let program: ProgramDefinition
    @Binding var path: NavigationPath

    var body: some View {
        Button {
            path.append(program.slug)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(program.shortTitle)
                    .font(.ccDisplay(14, semibold: true))
                    .foregroundStyle(.ccInk)
                    .multilineTextAlignment(.leading)
                Text("\(program.totalQuestions) Q&A")
                    .labelCaps(size: 9, tracking: 0.1)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.ccFill)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}
