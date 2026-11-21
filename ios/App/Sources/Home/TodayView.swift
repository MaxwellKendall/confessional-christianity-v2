// Today (TKL-825, approved prototype TKL-885): the one thing to do now. One
// primary card chosen by DomainKit's planToday, then "Also today", and an
// avatar opening Settings. A new guest gets only the two pillars.
//
// The Lord's Day store doesn't exist yet (TKL-859), so the planner gets no
// sermon day and no Sunday capture; its cards appear here once it does. The
// prototype's "Share this week's line" strip waits on the same store.
import SwiftUI
import SwiftData
import DomainKit

struct TodayView: View {
    @Binding var path: NavigationPath
    let openTab: (RootTab) -> Void

    @Environment(\.modelContext) private var modelContext
    // Observed only so Today re-renders when children or progress change.
    @Query private var observedChildren: [LocalChild]
    @Query private var observedTracks: [ChildCatechismTrack]
    @Query private var observedSettings: [ProgressSettings]

    @State private var showsSettings = false
    @State private var showsAddChild = false

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }

    private var plan: TodayPlan {
        planToday(TodayInput(children: store.todayChildren(), activeChildId: store.activeChildId))
    }

    var body: some View {
        let _ = observedChildren.map(\.updatedAt)
        let _ = observedTracks.map(\.updatedAt)
        let _ = observedSettings.first?.activeChildId
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    switch plan {
                    case .empty:
                        emptyState
                    case .plan(let primary, let also):
                        hero(primary)
                        if !also.isEmpty {
                            Text("Also today")
                                .labelCaps(size: 10.5, tracking: 0.16)
                                .padding(.top, 24)
                                .padding(.bottom, 8)
                            TodayList(items: also, row: row)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .frame(maxWidth: 704)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ccCard)
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
        }
        .tint(.ccInk)
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsAddChild) { AddChildView() }
    }

    // MARK: header

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }()

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateFormatter.string(from: Date()))
                    .labelCaps(size: 10.5, tracking: 0.16)
                Text("Today")
                    .font(.ccDisplay(25, semibold: true))
                    .foregroundStyle(.ccInk)
            }
            Spacer()
            Button { showsSettings = true } label: {
                Image(systemName: "person")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.ccInk)
                    .frame(width: 38, height: 38)
                    .background(Color.ccFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Two ways to begin. Do either; the other will wait.")
                .font(.ccBody(16.5))
                .foregroundStyle(.ccInk)
                .padding(.bottom, 4)
            PillarCard(
                eyebrow: "Catechism",
                title: "Catechize a child",
                text: "One question a day from the Westminster Shorter Catechism: the question, the answer, the proof texts, a prayer.",
                action: "Add your first child →"
            ) { showsAddChild = true }
            PillarCard(
                eyebrow: "The Lord's Day",
                title: "Keep Sunday's sermon",
                text: "Take notes on Sunday's sermon. The app turns them into a card for each day of the week.",
                action: "Take notes on Sunday's sermon →"
            ) { openTab(.lordsDay) }
        }
    }

    // MARK: primary card

    @ViewBuilder
    private func hero(_ item: TodayItem) -> some View {
        switch item {
        case .catechism(let child):
            HeroCard(
                eyebrow: "\(child.name) · \(child.programShortTitle) · Q. \(child.questionNumber)",
                text: child.finished ? "All \(child.totalQuestions) questions learned." : (child.question ?? ""),
                progress: Double(child.learned) / Double(max(child.totalQuestions, 1)),
                sub: child.practisedToday
                    ? "Practised today · \(child.learned) of \(child.totalQuestions) learned"
                    : "\(child.learned) of \(child.totalQuestions) learned",
                button: child.finished
                    ? "Review with \(child.name)"
                    : child.practisedToday
                        ? "Keep going at Q. \(child.questionNumber)"
                        : "Begin Q. \(child.questionNumber) with \(child.name)"
            ) { begin(child) }
        case .sermonDay(let day):
            HeroCard(
                eyebrow: "\(day.dayLabel) · from Sunday's sermon",
                text: day.text,
                progress: nil,
                sub: day.attribution,
                button: "Open today's card"
            ) { openTab(.lordsDay) }
        case .captureSunday:
            HeroCard(
                eyebrow: "The Lord's Day",
                text: "After church, photograph your sermon notes. Your week builds from them.",
                progress: nil,
                sub: nil,
                button: "Photograph notes"
            ) { openTab(.lordsDay) }
        }
    }

    // MARK: rows

    @ViewBuilder
    private func row(_ item: TodayItem) -> some View {
        switch item {
        case .catechism(let child):
            Button { begin(child) } label: {
                TodayRow(
                    lead: AnyView(Text(String(child.name.prefix(1))).font(.ccDisplay(13, semibold: true))),
                    title: child.name,
                    detail: child.practisedToday
                        ? "Q. \(child.learned) done today"
                        : "Q. \(child.questionNumber) · \(child.question ?? "")",
                    done: child.practisedToday || child.finished
                )
            }
            .buttonStyle(.plain)
        case .sermonDay(let day):
            Button { openTab(.lordsDay) } label: {
                TodayRow(
                    lead: AnyView(TabIcon(tab: .lordsDay, color: .ccInk2).frame(width: 17, height: 17)),
                    title: "\(day.dayLabel)'s card",
                    detail: "\(day.kind) · \(day.text)",
                    done: false
                )
            }
            .buttonStyle(.plain)
        case .captureSunday:
            Button { openTab(.lordsDay) } label: {
                TodayRow(
                    lead: AnyView(TabIcon(tab: .lordsDay, color: .ccInk2).frame(width: 17, height: 17)),
                    title: "Photograph Sunday's notes",
                    detail: "Your week builds from them",
                    done: false
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Starts this child's session: they become the active child (SessionView
    /// works on the active child), then their catechism is pushed.
    private func begin(_ child: TodayChild) {
        try? store.selectChild(childId: child.id)
        path.append(child.programSlug)
    }
}

private struct HeroCard: View {
    let eyebrow: String
    let text: String
    let progress: Double?
    let sub: String?
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .labelCaps(size: 10.5, tracking: 0.16, color: .ccOnChapel.opacity(0.75))
            Text(text)
                .font(.ccBody(21))
                .lineSpacing(4)
                .foregroundStyle(.ccOnChapel)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ccOnChapel.opacity(0.18))
                        Capsule().fill(Color.ccGilt).frame(width: geo.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 4)
                .padding(.bottom, 6)
            }
            if let sub {
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundStyle(.ccOnChapel.opacity(0.8))
                    .padding(.bottom, 16)
            }
            Button(action: action) {
                Text(button)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(.ccChapel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.ccOnChapel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Text(eyebrow).labelCaps(size: 10.5, tracking: 0.16)
                Text(title)
                    .font(.ccDisplay(19, semibold: true))
                    .foregroundStyle(.ccInk)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                Text(text)
                    .font(.ccBody(15.5))
                    .lineSpacing(3)
                    .foregroundStyle(.ccInk2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.ccChapel)
                    .padding(.top, 14)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ccHairline, lineWidth: 1))
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
                if index > 0 { Rectangle().fill(Color.ccHairline).frame(height: 1) }
                row(item)
            }
        }
        .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ccHairline, lineWidth: 1))
    }
}

private struct TodayRow: View {
    let lead: AnyView
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            lead
                .foregroundStyle(.ccInk)
                .frame(width: 34, height: 34)
                .background(Color.ccCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5))
                    .foregroundStyle(done ? .ccInk3 : .ccInk)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.ccInk2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(done ? "✓" : "›")
                .font(.system(size: 18))
                .foregroundStyle(done ? Color.ccChapel : Color.ccInk3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
