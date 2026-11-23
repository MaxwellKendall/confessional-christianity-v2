// The Catechism tab (pillar one), as in TKL-885's approved prototype (TKL-939):
// one full card per child, swiped sideways, each with the next question, a
// gilt progress ring and one action into that child's session; a dashed
// "Add a child" card at the end; then quiet links to jump to a question and
// to the Library. With no children it asks for a first child, nothing else.
// DomainKit's orderCatechismCards orders the cards (the child still due
// leads). Check its look with ios/scripts/prototype-shots (catechism-*).
import SwiftUI
import SwiftData
import DomainKit

struct CatechismTabView: View {
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    // Observed only so the cards re-render when children or progress change.
    @Query private var observedChildren: [LocalChild]
    @Query private var observedTracks: [ChildCatechismTrack]
    @Query private var observedSettings: [ProgressSettings]

    @State private var showsAddChild = false
    @State private var showsSessionError = false
    @State private var visibleCard: UUID?

    private static let addCardId = UUID()

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }

    private var cards: [TodayChild] {
        orderCatechismCards(store.todayChildren(), activeChildId: store.activeChildId)
    }

    var body: some View {
        let _ = observedChildren.map(\.updatedAt)
        let _ = observedTracks.map(\.updatedAt)
        let _ = observedSettings.first?.activeChildId
        let cards = self.cards
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.horizontal, ChapelSpace.gutter)
                    if cards.isEmpty {
                        emptyState
                    } else {
                        pager(cards)
                        dots(cards)
                        links
                            .padding(.top, ChapelSpace.s)
                            .padding(.horizontal, ChapelSpace.gutter)
                    }
                }
                .padding(.bottom, 100) // clears the floating tab bar
                .frame(maxWidth: 704)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(Color.ccPaper)
            }
            .background(Color.ccPaper)
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
        }
        .tint(.ccInk)
        .sheet(isPresented: $showsAddChild) { AddChildView() }
        .alert("Couldn’t start practice", isPresented: $showsSessionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The child selection couldn’t be saved. Please try again.")
        }
        // Back from a session, the child now due is at the front: show it.
        .onChange(of: cards.first?.id) { _, first in visibleCard = first }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: ChapelSpace.xs) {
                Text("Westminster Shorter Catechism")
                    .chapelCaps()
                Text("Catechism")
                    .font(.ccTitle)
                    .tracking(0.25)
                    .foregroundStyle(.ccInk)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button { path.append(SearchRoute.results) } label: {
                SearchGlyph(color: .ccInk)
                    .frame(width: 18, height: 18)
                    .frame(width: ChapelSize.avatar, height: ChapelSize.avatar)
                    .background(Color.ccFill, in: Circle())
                    .contentShape(Circle().inset(by: -3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search the confessions")
        }
        .padding(.top, ChapelSpace.s)
        .padding(.bottom, ChapelSpace.l)
    }

    // MARK: empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Who are you catechizing?")
                    .font(.ccH2)
                    .foregroundStyle(.ccInk)
                Text("Add a child to start at Q. 1. Each child keeps their own place.")
                    .chapelReading()
                    .foregroundStyle(.ccInk2)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, ChapelSpace.xl)
            Button("Add a child") { showsAddChild = true }
                .buttonStyle(ChapelPrimaryButtonStyle())
                .padding(.horizontal, ChapelSpace.gutter)
        }
    }

    // MARK: cards

    private func pager(_ cards: [TodayChild]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: ChapelSpace.m) {
                ForEach(cards) { child in
                    ChildCard(child: child) { begin(child) }
                        .id(child.id)
                }
                AddChildCard { showsAddChild = true }
                    .id(Self.addCardId)
            }
            .fixedSize(horizontal: false, vertical: true) // every card as tall as the tallest
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visibleCard, anchor: .center)
        .contentMargins(.horizontal, ChapelSpace.gutter, for: .scrollContent)
    }

    private func dots(_ cards: [TodayChild]) -> some View {
        let ids = cards.map(\.id) + [Self.addCardId]
        let current = visibleCard ?? ids[0]
        return HStack(spacing: 6) {
            ForEach(ids, id: \.self) { id in
                Circle()
                    .fill(id == current ? Color.ccInk2 : Color.ccLine)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ChapelSpace.m)
        .accessibilityHidden(true)
    }

    // MARK: quiet links

    private var links: some View {
        VStack(spacing: 0) {
            Button {
                path.append(LibraryRoute.document(slug: "westminster-shorter-catechism"))
            } label: {
                ChapelListRow(title: "Jump to a question", detail: "Any of the 107, with its proof texts", done: false) {
                    SearchGlyph(color: .ccInk2).frame(width: 17, height: 17)
                }
            }
            .buttonStyle(.plain)
            Rectangle().fill(Color.ccLine).frame(height: 1)
            Button { path.append(LibraryRoute.index) } label: {
                ChapelListRow(title: "The Library", detail: "The confessions and catechisms", done: false) {
                    TabIcon(tab: .catechism, color: .ccInk2, lineWidth: 1.8).frame(width: 17, height: 17)
                }
            }
            .buttonStyle(.plain)
        }
        .chapelCard()
    }

    /// The child becomes the active one (SessionView works on the active
    /// child), then their catechism's session is pushed.
    private func begin(_ child: TodayChild) {
        do {
            path.append(try store.selectChildForSession(child))
        } catch {
            showsSessionError = true
        }
    }
}

private struct ChildCard: View {
    let child: TodayChild
    let action: () -> Void

    private var progress: Double { Double(child.learned) / Double(max(child.totalQuestions, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: ChapelSpace.m) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.name)
                        .font(.ccH2)
                        .foregroundStyle(.ccInk)
                    Text(catechismPracticeLine(lastPractisedAt: child.lastPractisedAt))
                        .font(.ccUI(13))
                        .foregroundStyle(.ccInk2)
                }
                Spacer(minLength: ChapelSpace.m)
                ProgressRing(progress: progress, label: "\(child.learned)")
                    .accessibilityLabel("\(child.learned) of \(child.totalQuestions) learned")
            }
            Text("Next · Q. \(child.questionNumber) of \(child.totalQuestions)")
                .chapelCaps()
            Text(child.finished ? "All \(child.totalQuestions) questions learned." : (child.question ?? ""))
                .chapelReading(size: 19)
                .foregroundStyle(.ccInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if child.isDue {
                Button("Continue at Q. \(child.questionNumber)", action: action)
                    .buttonStyle(ChapelPrimaryButtonStyle())
            } else {
                Button(child.finished ? "Review with \(child.name)" : "Keep going at Q. \(child.questionNumber)", action: action)
                    .buttonStyle(ChapelQuietButtonStyle())
            }
        }
        .padding(20)
        .frame(minHeight: 280, maxHeight: .infinity, alignment: .top)
        .chapelCard()
        .containerRelativeFrame(.horizontal) { width, _ in width - 2 * ChapelSpace.gutter - 16 }
    }
}

private struct AddChildCard: View {
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChapelRadius.card, style: .circular)
        Button(action: action) {
            VStack(spacing: ChapelSpace.s) {
                Text("+").font(.ccUI(28))
                Text("Add a child").font(.ccUI(15.5, weight: .semibold))
            }
            .foregroundStyle(.ccInk2)
            .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
            .background(Color.ccSurface, in: shape)
            .overlay(shape.strokeBorder(Color.ccLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .containerRelativeFrame(.horizontal) { width, _ in width - 2 * ChapelSpace.gutter - 16 }
    }
}

/// The prototype's 84-pt ring: learned so far in gilt over a fill track.
private struct ProgressRing: View {
    let progress: Double
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.ccFill, lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.ccGilt, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.ccUI(15, weight: .semibold))
                .foregroundStyle(.ccInk)
        }
        .padding(3) // the prototype's radius-36 circle inside an 84-pt box
        .frame(width: 84, height: 84)
    }
}

/// The prototype's magnifier: a circle and a handle, stroked like the tab icons.
private struct SearchGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let s = size.width / 24
            var path = Path()
            path.addEllipse(in: CGRect(x: 4 * s, y: 4 * s, width: 12 * s, height: 12 * s))
            path.move(to: CGPoint(x: 14.5 * s, y: 14.5 * s))
            path.addLine(to: CGPoint(x: 20 * s, y: 20 * s))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
