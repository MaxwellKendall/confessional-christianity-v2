// The Catechism tab (pillar one): the "Your Catechism" continue card for the
// active child's program, a grid to the other catechisms, and a closing link
// into the Library, which TKL-825 made a lookup instead of a tab.
import SwiftUI
import SwiftData
import DomainKit

struct CatechismTabView: View {
    private let defaultProgram = PROGRAMS[0]

    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    // Observed only so the card re-renders when a session, Today or Settings
    // changes the active child or their place; the store answers the question.
    @Query private var observedTracks: [ChildCatechismTrack]
    @Query private var observedSettings: [ProgressSettings]

    private var track: ChildCatechismTrack? {
        store.activeChildId.flatMap { store.activeTrack(childId: $0) }
    }

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }

    private var trackProgram: ProgramDefinition? {
        guard let track else { return nil }
        return PROGRAMS.first { $0.contentId.rawValue == track.catechismId }
    }

    private var program: ProgramDefinition { trackProgram ?? defaultProgram }

    private var activeTrack: ChildCatechismTrack? { trackProgram != nil ? track : nil }

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
        // Reading the queries registers them as dependencies of this body.
        let _ = observedTracks.map(\.updatedAt)
        let _ = observedSettings.first?.activeChildId
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SiteHeaderView(path: $path)
                homeScrollView
            }
            .background(Color.ccCard)
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
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

                    Button {
                        path.append(LibraryRoute.index)
                    } label: {
                        HStack(spacing: 4) {
                            Spacer()
                            Text("Or explore the confessions in the")
                                .font(.ccBody(13))
                                .italic()
                                .foregroundStyle(.ccInk2)
                            Text("Library")
                                .font(.ccBody(13))
                                .italic()
                                .foregroundStyle(.ccInk)
                                .dottedUnderline(.ccInk)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
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
