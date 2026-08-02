// Mirrors the real web home page (src/components/HomeClient.tsx), not the
// /programs index: a "Your Catechism" continue card with a progress bar for
// whichever program the visitor last worked in (WSC by default with no
// saved progress), a grid to the other three catechisms, and a closing line
// pointing at the Library. The devotion-run card that now leads the web
// homepage (WSC_RUN) is deliberately deferred — Devotions hasn't been ported
// to DomainKit yet (that's Phase 3 in the plan) — so this card is the whole
// homepage for now rather than a partial imitation of that layout.
import SwiftUI
import SwiftData
import DomainKit

struct HomeView: View {
    private let defaultProgram = PROGRAMS[0]

    @Environment(\.modelContext) private var modelContext
    @State private var path = NavigationPath()
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
                .padding(.bottom, 32)
                .frame(maxWidth: 704)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ccCanvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { slug in
                if let program = getProgram(slug) {
                    SessionView(program: program)
                }
            }
            .task {
                track = store.activeTrack()
            }
        }
        .tint(.ccInk)
    }
}
