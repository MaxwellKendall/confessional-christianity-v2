// Today (TKL-825, approved prototype TKL-885): the one thing to do now. One
// primary card chosen by DomainKit's planToday, then "Also today", and an
// avatar opening Settings. A new guest gets only the two pillars. Its look is
// the prototype's (TKL-938); check changes with ios/scripts/prototype-shots.
//
// The sermon side comes from the Lord's Day store (TKL-859): this week's
// sermon stack's current card (cards aren't tied to days, TKL-1062/TKL-941),
// or on a Sunday with no notes yet, "photograph your notes", which opens the
// camera (TKL-860) on the Lord's Day tab. The prototype's
// "Share this week's line" strip is not built yet.
import SwiftUI
import SwiftData
import DomainKit

struct TodayView: View {
    @Binding var path: NavigationPath
    let openTab: (RootTab) -> Void
    /// Opens the Lord's Day tab with the notes camera up.
    let startCapture: () -> Void

    @Environment(\.modelContext) private var modelContext
    // Observed only so Today re-renders when children or progress change.
    @Query private var observedChildren: [LocalChild]
    @Query private var observedTracks: [ChildCatechismTrack]
    @Query private var observedSettings: [ProgressSettings]
    @Query private var observedNotes: [LordsDayNote]
    @Query private var observedCards: [NoteCard]
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped when the day may have changed, so the sermon card follows the calendar.
    @State private var clockTick = 0

    @State private var showsSettings = false
    @State private var showsAddChild = false
    @State private var showsSessionError = false

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }

    private var plan: TodayPlan {
        let memory = LordsDayStackMemory(
            stored: UserDefaults.standard.dictionary(forKey: LordsDayTabView.memoryKey) as? [String: Int] ?? [:]
        )
        let sermon = LordsDayStore(context: modelContext).todaySermon(stackMemory: memory)
        return planToday(TodayInput(
            children: store.todayChildren(), activeChildId: store.activeChildId,
            sermonDay: sermon.day, sundayCaptureDue: sermon.sundayCaptureDue
        ))
    }

    var body: some View {
        let _ = observedChildren.map(\.updatedAt)
        let _ = observedTracks.map(\.updatedAt)
        let _ = observedSettings.first?.activeChildId
        let _ = observedNotes.map(\.updatedAt)
        let _ = observedCards.map(\.updatedAt)
        let _ = clockTick
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    switch plan {
                    case .empty:
                        emptyState
                        storageLine.padding(.top, 20)
                    case .plan(let primary, let also):
                        hero(primary)
                        if !also.isEmpty {
                            Text("Also today")
                                .chapelCaps()
                                .padding(.top, ChapelSpace.xl)
                                .padding(.bottom, ChapelSpace.s)
                            TodayList(items: also, row: row)
                        }
                        storageLine.padding(.top, ChapelSpace.l)
                    }
                }
                .padding(.horizontal, ChapelSpace.gutter)
                .padding(.bottom, 100) // clears the floating tab bar
                .frame(maxWidth: 704)
                .frame(maxWidth: .infinity)
            }
            // Scrolled content stops under the status bar, as in the prototype.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(Color.ccPaper)
            }
            .background(Color.ccPaper)
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
        }
        .tint(.ccInk)
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsAddChild) { AddChildView() }
        // Back from the Lord's Day tab, its stack may sit on another card.
        .onAppear { clockTick += 1 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clockTick += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            clockTick += 1
        }
        #if DEBUG
        // Screenshot hook: `-OpenSheet settings|addChild` opens that sheet on Today.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "OpenSheet") {
            case "settings": showsSettings = true
            case "addChild": showsAddChild = true
            default: break
            }
        }
        #endif
        .alert("Couldn’t start practice", isPresented: $showsSessionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The child selection couldn’t be saved. Please try again.")
        }
    }

    // MARK: header

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE · d MMMM" // "Thursday · 21 November"
        return f
    }()

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: ChapelSpace.xs) {
                Text(Self.dateFormatter.string(from: Date()))
                    .chapelCaps()
                Text("Today")
                    .font(.ccTitle)
                    .tracking(0.25)
                    .foregroundStyle(.ccInk)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button { showsSettings = true } label: {
                PersonIcon(color: .ccInk)
                    .frame(width: 18, height: 18)
                    .frame(width: ChapelSize.avatar, height: ChapelSize.avatar)
                    .background(Color.ccFill, in: Circle())
                    .contentShape(Circle().inset(by: -3)) // a 44pt target
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, ChapelSpace.s)
        .padding(.bottom, ChapelSpace.l)
    }

    /// Nothing syncs yet, so this is true for everyone (signed-in is TKL-930).
    private var storageLine: some View {
        Text("On this iPhone")
            .font(.ccUI(13))
            .foregroundStyle(.ccInk3)
    }

    // MARK: empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ChapelSpace.m) {
            Text("Two ways to begin. Do either; the other will wait.")
                .chapelReading()
                .foregroundStyle(.ccInk)
                .padding(.bottom, ChapelSpace.xs)
            PillarCard(
                eyebrow: "Catechism",
                title: "Catechize a child",
                text: "One question a day from the Westminster Shorter Catechism: the question, the answer, the proof texts, a prayer.",
                action: "Add your first child →"
            ) { showsAddChild = true }
            PillarCard(
                eyebrow: "The Lord’s Day",
                title: "Keep Sunday’s sermon",
                text: "Photograph your notes after church. The app turns them into a card for each day of the week.",
                action: "Photograph Sunday’s notes →"
            ) { startCapture() }
        }
    }

    // MARK: primary card

    @ViewBuilder
    private func hero(_ item: TodayItem) -> some View {
        switch item {
        case .catechism(let child):
            ChapelHeroCard(
                eyebrow: "\(child.name) · \(child.programShortTitle) · Q. \(child.questionNumber)",
                text: child.finished ? "All \(child.totalQuestions) questions learned." : (child.question ?? ""),
                progress: Double(child.learned) / Double(max(child.totalQuestions, 1)),
                detail: child.practisedToday
                    ? "Practised today · \(child.learned) of \(child.totalQuestions) learned"
                    : "\(child.learned) of \(child.totalQuestions) learned",
                button: child.finished
                    ? "Review with \(child.name)"
                    : child.practisedToday
                        ? "Keep going at Q. \(child.questionNumber)"
                        : "Begin Q. \(child.questionNumber) with \(child.name)"
            ) { begin(child) }
        case .sermonDay(let day):
            ChapelHeroCard(
                eyebrow: "From Sunday’s sermon · \(day.countLabel)",
                text: day.text,
                progress: nil,
                detail: day.attribution,
                button: "Open the sermon’s cards"
            ) { openTab(.lordsDay) }
        case .captureSunday:
            ChapelHeroCard(
                eyebrow: "The Lord’s Day",
                text: "After church, photograph your sermon notes. Your week builds from them.",
                progress: nil,
                detail: LordsDayStore(context: modelContext).lastSundayLine(),
                button: "Photograph notes"
            ) { startCapture() }
        }
    }

    // MARK: rows

    @ViewBuilder
    private func row(_ item: TodayItem) -> some View {
        switch item {
        case .catechism(let child):
            Button { begin(child) } label: {
                ChapelListRow(
                    title: child.name,
                    detail: child.practisedToday
                        ? "Q. \(child.learned) done today"
                        : "Q. \(child.questionNumber) · \(child.question ?? "")",
                    done: child.practisedToday || child.finished
                ) {
                    Text(String(child.name.prefix(1)))
                }
            }
            .buttonStyle(.plain)
        case .sermonDay(let day):
            Button { openTab(.lordsDay) } label: {
                ChapelListRow(title: day.sermonTitle, detail: "\(day.countLabel) · \(day.kind) · \(day.text)", done: false) {
                    sermonIcon
                }
            }
            .buttonStyle(.plain)
        case .captureSunday:
            Button { startCapture() } label: {
                ChapelListRow(title: "Photograph Sunday’s notes", detail: "Your week builds from them", done: false) {
                    sermonIcon
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var sermonIcon: some View {
        TabIcon(tab: .lordsDay, color: .ccInk2, lineWidth: 1.8)
            .frame(width: 17, height: 17)
    }

    /// Starts this child's session: they become the active child (SessionView
    /// works on the active child), then their catechism is pushed.
    private func begin(_ child: TodayChild) {
        do {
            let slug = try store.selectChildForSession(child)
            path.append(slug)
        } catch {
            showsSessionError = true
        }
    }
}

private struct PillarCard: View {
    let eyebrow: String
    let title: String
    let text: String
    let action: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow).chapelCaps()
                Text(title)
                    .font(.ccH2)
                    .foregroundStyle(.ccInk)
                    .padding(.top, ChapelSpace.s)
                    .padding(.bottom, 6)
                Text(text)
                    .chapelReading(size: 15.5)
                    .foregroundStyle(.ccInk2)
                Text(action)
                    .font(.ccUI(15, weight: .semibold))
                    .foregroundStyle(.ccChapel)
                    .padding(.top, 14)
            }
            .multilineTextAlignment(.leading)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chapelCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TodayList<Row: View>: View {
    let items: [TodayItem]
    let row: (TodayItem) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Rectangle().fill(Color.ccLine).frame(height: 1) }
                row(item)
            }
        }
        .chapelCard()
    }
}
