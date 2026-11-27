// The Lord's Day tab's landing page (TKL-1063, design TKL-1062): "The Lord's
// Day" with this week's title and two round buttons (Journal, Camera); this
// week's sermon as a stack that reopens on the card you were last on; and a
// swipe row of earlier Lord's Days ending in the journal. Each state of the
// week (Sunday before notes, reading notes, review pending, no sermon, before
// a first Sunday, offline, read failed) is drawn here from plain inputs, so
// the tab and the screenshot fixture share it.
import SwiftUI
import SwiftData
import DomainKit

/// Notes being read, or read and waiting for review, as the landing page shows them.
struct LandingDraft {
    var title: String?
    var passage: String?
    var preacher: String?
    var dateCaps: String
    var pageCount: Int
    var pagesRead: Int
    var progress: Double
    /// The drafted cards' words, as they arrive.
    var arrived: [String]
    var cardCount: Int
    /// The first page that couldn't be read (0-based).
    var failedPage: Int?

    var meta: String? {
        let parts = [passage, preacher].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct LordsDayLandingView: View {
    let reel: LordsDayReel
    let kind: LordsDayLanding.Kind
    let today: Date
    var isSunday: Bool
    var offline = false
    /// This week's sermon's stack page (where it reopens).
    var stackPage: Int = 0
    var draft: LandingDraft?
    var calendar: Calendar = .current
    var onOpenReel: (ReelPosition) -> Void = { _ in }
    var onEditSermon: ((UUID) -> Void)? = nil
    var onJournal: () -> Void = {}
    var onCapture: () -> Void = {}
    var onType: () -> Void = {}
    var onOpenReview: () -> Void = {}
    var onRetry: () -> Void = {}
    var onRefresh: (@MainActor () async -> Void)? = nil

    private var thisWeek: ReelSermon? { reel.thisWeek(today: today, calendar: calendar) }
    private var earlier: [ReelSermon] { reel.earlier(today: today, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if offline && kind != .firstSunday { offlineNote.padding(.top, 10) }
                content
            }
            .padding(.bottom, 120)
            .frame(maxWidth: 704)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await onRefresh?()
        }
        .scrollIndicators(.hidden)
        .background(Color.ccPaper)
        .accessibilityIdentifier("lordsDay.landing")
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THE LORD'S DAY").font(.ccDisplay(12)).tracking(12 * 0.18).foregroundStyle(.ccInk3)
                Text(LordsDayLanding.title(kind: kind, isSunday: isSunday))
                    .font(.ccDisplay(25, semibold: true)).foregroundStyle(.ccInk)
                    .accessibilityIdentifier("lordsDay.title")
            }
            Spacer()
            if kind != .firstSunday {
                HStack(spacing: 8) {
                    roundButton("book.closed", label: "Journal", id: "lordsDay.journal", action: onJournal)
                    roundButton("camera", label: "Photograph Sunday's notes", id: "lordsDay.capture", action: onCapture)
                }
            }
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func roundButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .regular))
                .foregroundStyle(.ccInk)
                .frame(width: 40, height: 40)
                .background(Color.ccFill, in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: states

    @ViewBuilder private var content: some View {
        switch kind {
        case .week:
            if let thisWeek { weekStack(thisWeek) }
            shelf
        case .sundayBeforeNotes:
            sundayCapture
            if let last = earlier.first { lastWeekNote(last) }
            shelf
        case .readingNotes:
            reading
            shelf
        case .reviewPending:
            reviewStack
            shelf
        case .noSermon:
            noSermon
            if let ago = reel.yearAgo(today: today, calendar: calendar) { yearAgo(ago) }
            shelf
        case .firstSunday:
            firstSunday
        case .readFailed:
            readFailed
            shelf
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, ChapelSpace.gutter)
            .padding(.top, 18)
    }

    private func sectionHeader(_ title: String, action: String? = nil, id: String? = nil, perform: @escaping () -> Void = {},
                               trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.ccDisplay(12)).tracking(12 * 0.16).foregroundStyle(.ccInk3)
            Spacer()
            if let action {
                Button(action, action: perform).font(.system(size: 14, weight: .semibold)).foregroundStyle(.ccChapel)
                    .accessibilityIdentifier(id ?? "")
            } else if let trailing {
                Text(trailing).font(.system(size: 13)).foregroundStyle(.ccInk3)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: the week's stack

    private func weekStack(_ sermon: ReelSermon) -> some View {
        let index = reel.index(of: sermon.id) ?? 0
        let page = min(stackPage, sermon.pageCount - 1)
        let peeking = LordsDayStackMemory.peeking(after: page, pageCount: sermon.pageCount)
        return section {
            sectionHeader("THIS WEEK'S SERMON", action: "All cards", id: "lordsDay.allCards") {
                onOpenReel(ReelPosition(sermon: index, page: 0))
            }
            StackFrame(under: peeking.map { sermon.palette(atPage: $0) }) {
                SermonCardView(
                    sermon: sermon,
                    page: page,
                    hint: "Tap to open the stack",
                    onEditDetails: onEditSermon.map { edit in { edit(sermon.id) } }
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenReel(ReelPosition(sermon: index, page: page)) }
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("lordsDay.stack")
        }
    }

    private var reviewStack: some View {
        let draft = draft ?? LandingDraft(dateCaps: "", pageCount: 1, pagesRead: 0, progress: 0, arrived: [], cardCount: 0)
        let rotation = LordsDayFeed.rotation
        return section {
            sectionHeader("READY TO REVIEW", trailing: "\(draft.cardCount) card\(draft.cardCount == 1 ? "" : "s")")
            StackFrame(under: [rotation[2], rotation[1]]) {
                SermonCardView(
                    page: .cover(SermonCover(dateCaps: "SUNDAY · \(draft.dateCaps)", title: draft.title ?? "This week's sermon",
                                             passage: draft.passage, who: draft.preacher)),
                    binding: SermonCardBinding(title: nil, meta: nil, count: "Draft"),
                    palette: rotation[0],
                    hint: "\(draft.cardCount) cards drafted from \(draft.pageCount) page\(draft.pageCount == 1 ? "" : "s")"
                ) {
                    Button(action: onOpenReview) {
                        SermonPill(title: "Review", systemImage: "rectangle.stack", ink: Color(hex: rotation[0].ink))
                    }
                    .accessibilityIdentifier("lordsDay.review")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenReview)
            Text("Check the title and the cards, then keep them. Nothing shows in your stack until you do.")
                .font(.system(size: 13)).foregroundStyle(.ccInk3).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, 12)
        }
    }

    // MARK: capture states

    private var sundayCapture: some View {
        section {
            EmptyStackArt(top: "SUNDAY · \(dateCaps(today))", title: "This week's sermon", line: "From your notes")
            leadCopy("Photograph this morning's notes. They become a stack of cards to carry through the week.")
            captureButtons(primary: "Photograph notes").padding(.top, 20)
        }
    }

    private func lastWeekNote(_ sermon: ReelSermon) -> some View {
        section {
            NotePanel(icon: "rectangle.stack") {
                Text("Last week: \(sermon.title)").fontWeight(.semibold).foregroundStyle(.ccInk)
                    + Text("\n\([sermon.passage, "\(sermon.cards.count) cards, kept in the journal."].compactMap { $0 }.joined(separator: " · "))")
            }
            .onTapGesture { onOpenReel(ReelPosition(sermon: reel.index(of: sermon.id) ?? 0, page: 0)) }
        }
    }

    private var noSermon: some View {
        section {
            VStack(alignment: .leading, spacing: 0) {
                Text("NO SERMON THIS WEEK").font(.ccDisplay(11)).tracking(11 * 0.18).foregroundStyle(.ccInk3)
                Text("Missed Sunday's notes? You can still add them.")
                    .font(.ccBody(19)).foregroundStyle(.ccInk).padding(.top, 8)
                Button(action: onCapture) { Label("Add notes", systemImage: "camera") }
                    .buttonStyle(ChapelPrimaryButtonStyle())
                    .accessibilityIdentifier("lordsDay.addNotes")
                    .padding(.top, 16)
            }
            .panel()
        }
    }

    private func yearAgo(_ sermon: ReelSermon) -> some View {
        section {
            sectionHeader("A YEAR AGO THIS WEEK")
            SermonTile(sermon: sermon, detail: [sermon.passage, "\(sermon.cards.count) cards"].compactMap { $0 }.joined(separator: " · "))
                .frame(height: 120)
                .onTapGesture { onOpenReel(ReelPosition(sermon: reel.index(of: sermon.id) ?? 0, page: 0)) }
                .accessibilityIdentifier("lordsDay.yearAgo")
        }
    }

    private var firstSunday: some View {
        VStack(spacing: 0) {
            EmptyStackArt(top: "SUNDAY", title: "Your notes, kept", line: "A stack of cards")
            leadCopy("Photograph your sermon notes on Sunday. Through the week, its cards bring it back to mind.")
            Text("Every Lord's Day you keep is saved in your journal, by date, passage and title.")
                .font(.system(size: 13)).foregroundStyle(.ccInk3).multilineTextAlignment(.center).padding(.top, 12)
            captureButtons(primary: "Photograph notes").padding(.top, 20)
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 26)
    }

    private func captureButtons(primary: String) -> some View {
        VStack(spacing: 8) {
            Button(action: onCapture) { Label(primary, systemImage: "camera") }
                .buttonStyle(ChapelPrimaryButtonStyle())
                .accessibilityIdentifier("lordsDay.photograph")
            Button("Type them instead", action: onType)
                .buttonStyle(ChapelQuietButtonStyle())
                .accessibilityIdentifier("lordsDay.type")
        }
    }

    private func leadCopy(_ text: String) -> some View {
        Text(text).font(.ccBody(19)).lineSpacing(4).foregroundStyle(.ccInk).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.top, 6)
    }

    // MARK: reading notes

    private var reading: some View {
        let draft = draft ?? LandingDraft(dateCaps: "", pageCount: 1, pagesRead: 0, progress: 0, arrived: [], cardCount: 0)
        return section {
            sectionHeader("READING YOUR NOTES",
                          trailing: draft.pagesRead >= draft.pageCount ? "Done" : "Page \(min(draft.pagesRead + 1, draft.pageCount)) of \(draft.pageCount)")
            VStack(alignment: .leading, spacing: 0) {
                PageThumbs(count: draft.pageCount, done: draft.pagesRead)
                Text("SERMON").font(.system(size: 11)).tracking(11 * 0.08).foregroundStyle(.ccInk3)
                if let title = draft.title {
                    Text(title).font(.ccDisplay(20, semibold: true)).foregroundStyle(.ccInk).transition(.opacity)
                } else {
                    Shimmer(widthFraction: 0.7)
                }
                if let meta = draft.meta {
                    Text(meta).font(.system(size: 13)).foregroundStyle(.ccInk3).padding(.top, 8)
                } else {
                    Shimmer(widthFraction: 0.5)
                }
                ProgressTrack(value: draft.progress).padding(.top, 10).padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(draft.arrived.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.ccBody(14)).foregroundStyle(.ccInk2).lineLimit(2)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
                .padding(.top, 10)
                Text("You can leave; the cards wait here for review.")
                    .font(.system(size: 13)).foregroundStyle(.ccInk3).padding(.top, 12)
            }
            .animation(.easeOut(duration: 0.4), value: draft.arrived.count)
            .panel()
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenReview)
            .accessibilityIdentifier("lordsDay.reading")
        }
    }

    private var readFailed: some View {
        let draft = draft ?? LandingDraft(dateCaps: "", pageCount: 1, pagesRead: 0, progress: 0, arrived: [], cardCount: 0)
        let failed = (draft.failedPage ?? draft.pagesRead) + 1
        let readOnly = draft.pagesRead == 1 ? "Review page 1 only" : "Review the pages read"
        return section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 16)).padding(.top, 1)
                VStack(alignment: .leading, spacing: 0) {
                    (Text("Couldn't read page \(failed).").fontWeight(.semibold)
                        + Text(draft.pagesRead > 0 ? " Page\(draft.pagesRead == 1 ? " 1 is" : "s read are") safe and \(draft.cardCount == 1 ? "its card is" : "its \(draft.cardCount) cards are") drafted." : ""))
                        .font(.system(size: 14))
                    HStack(spacing: 8) {
                        Button(action: onRetry) {
                            Text("Try again").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ccSurface)
                                .padding(.horizontal, 12).frame(height: 34).background(Color.ccDanger, in: Capsule())
                        }
                        .accessibilityIdentifier("lordsDay.retry")
                        if draft.pagesRead > 0 {
                            Button(action: onOpenReview) {
                                Text(readOnly).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 34)
                            }
                            .accessibilityIdentifier("lordsDay.reviewRead")
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .foregroundStyle(.ccDanger)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ccDangerFill, in: RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                PageThumbs(count: draft.pageCount, done: draft.pagesRead)
                if let title = draft.title { Text(title).font(.ccDisplay(20, semibold: true)).foregroundStyle(.ccInk) }
                if let meta = draft.meta { Text(meta).font(.system(size: 13)).foregroundStyle(.ccInk3).padding(.top, 8) }
            }
            .panel()
            .padding(.top, 12)
        }
    }

    private var offlineNote: some View {
        NotePanel(icon: "wifi.slash") {
            Text("Offline.").fontWeight(.semibold).foregroundStyle(.ccInk)
                + Text(" Your week is on this phone. New notes are read when you're back online.")
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .accessibilityIdentifier("lordsDay.offline")
    }

    // MARK: earlier Lord's Days

    @ViewBuilder private var shelf: some View {
        section {
            sectionHeader("EARLIER LORD'S DAYS", action: "Journal", id: "lordsDay.shelfJournal", perform: onJournal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(earlier) { sermon in
                        SermonTile(sermon: sermon, detail: sermon.passage == sermon.title ? nil : sermon.passage)
                            .frame(width: 150, height: 186)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenReel(ReelPosition(sermon: reel.index(of: sermon.id) ?? 0, page: 0)) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("lordsDay.earlier.\(sermon.shortDate)")
                    }
                    JournalTile()
                        .frame(width: 150, height: 186)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onJournal)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("lordsDay.journalTile")
                }
                .padding(.horizontal, ChapelSpace.gutter)
                .padding(.bottom, 4)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -ChapelSpace.gutter)
        }
    }

    private func dateCaps(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }
}

// MARK: pieces

/// The stack: the top card with two cards peeking behind it.
private struct StackFrame<Card: View>: View {
    /// The light palettes of the two pages behind (next, then the one after).
    let under: [QuoteCardPalette]
    @ViewBuilder let card: () -> Card
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            if under.count > 1 { underCard(under[1]).scaleEffect(0.9, anchor: .top) }
            if under.count > 0 { underCard(under[0]).scaleEffect(0.95, anchor: .top).offset(y: 9) }
            card()
                .frame(height: 380)
                .shadow(color: .ccShadow, radius: 15, y: 10)
                .offset(y: 18)
        }
        .frame(height: 398, alignment: .top)
    }

    private func underCard(_ palette: QuoteCardPalette) -> some View {
        RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous)
            .fill(Color(hex: LordsDayFeed.palette(palette, dark: colorScheme == .dark).field))
            .overlay(RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous).strokeBorder(.black.opacity(0.08)))
            .frame(height: 380)
    }
}

/// A past sermon on the landing page, in its week's colour.
private struct SermonTile: View {
    let sermon: ReelSermon
    var detail: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = LordsDayFeed.palette(sermon.coverPalette, dark: colorScheme == .dark)
        VStack(alignment: .leading, spacing: 0) {
            Text(sermon.dateCaps).font(.ccDisplay(10)).tracking(10 * 0.18).foregroundStyle(Color(hex: p.accent))
            Spacer(minLength: 8)
            Text(sermon.title).font(.ccDisplay(15, semibold: true)).lineSpacing(1).foregroundStyle(Color(hex: p.ink))
                .lineLimit(4).minimumScaleFactor(0.8)
            if let detail {
                Text(detail).font(.ccBody(13)).foregroundStyle(Color(hex: p.muted)).lineLimit(2).padding(.top, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: p.field))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: p.frame).opacity(0.5))
                .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct JournalTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE JOURNAL").font(.ccDisplay(10)).tracking(10 * 0.18).foregroundStyle(.ccGilt)
            Spacer(minLength: 8)
            Text("Every Lord's Day").font(.ccDisplay(15, semibold: true)).foregroundStyle(.ccInk)
            Text("By year, by Scripture, or search").font(.system(size: 12)).foregroundStyle(.ccInk3).padding(.top, 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ccLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// Three blank cards fanned, the top one captioned: the empty stack.
private struct EmptyStackArt: View {
    let top: String
    let title: String
    let line: String

    var body: some View {
        ZStack(alignment: .top) {
            blank.rotationEffect(.degrees(-7)).offset(x: -34, y: 18)
            blank.rotationEffect(.degrees(6)).offset(x: 34, y: 18)
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text(top).font(.ccDisplay(10)).tracking(10 * 0.2).foregroundStyle(.ccGilt)
                Text(title).font(.ccDisplay(17, semibold: true)).foregroundStyle(.ccInk).padding(.top, 6)
                Text(line).font(.ccBody(13)).foregroundStyle(.ccInk3).padding(.top, 4)
            }
            .padding(16)
            .frame(width: 170, height: 220, alignment: .leading)
            .background(card)
            .offset(y: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .padding(.top, 6).padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ccSurface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ccLine))
            .shadow(color: .ccShadow, radius: 9, y: 6)
    }

    private var blank: some View { card.frame(width: 170, height: 220) }
}

private struct NotePanel: View {
    let icon: String
    let text: () -> Text

    init(icon: String, @ViewBuilder text: @escaping () -> Text) { self.icon = icon; self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.ccInk3).padding(.top, 1)
            text().font(.system(size: 14)).foregroundStyle(.ccInk2).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panel()
    }
}

private struct PageThumbs: View {
    let count: Int
    let done: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(count, 1), id: \.self) { k in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.ccFill)
                    .overlay {
                        VStack(spacing: 8) { ForEach(0..<6, id: \.self) { _ in Rectangle().fill(Color.ccLine).frame(height: 1) } }
                            .padding(.horizontal, 6)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.ccLine))
                    .frame(width: 54, height: 70)
                    .overlay(alignment: .topTrailing) {
                        if k < done {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.ccOnGilt)
                                .frame(width: 18, height: 18).background(Color.ccGilt, in: Circle()).offset(x: 6, y: -6)
                        }
                    }
            }
        }
        .padding(.bottom, 12)
    }
}

private struct ProgressTrack: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ccFill)
                Capsule().fill(Color.ccGilt).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.6), value: value)
    }
}

private struct Shimmer: View {
    let widthFraction: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(LinearGradient(colors: [.ccFill, .ccLine, .ccFill], startPoint: UnitPoint(x: phase, y: 0.5),
                                     endPoint: UnitPoint(x: phase + 1, y: 0.5)))
                .frame(width: geo.size.width * widthFraction)
        }
        .frame(height: 14)
        .padding(.vertical, 8)
        .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

private extension View {
    func panel() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous).strokeBorder(Color.ccLine))
    }
}

#if DEBUG

/// Screenshot hook (TKL-1063): `-LordsDayLandingFixture week|sunday|drafting|review|none|first|offline|error`
/// draws the landing page in that state from an in-memory store (this week's sermon is the
/// Revelation 2:8-11 note; earlier ones are samples). `-LordsDayStackPage 4` puts the stack on that
/// page; `-LordsDayReelAt 0:4` opens the reel at sermon 0, page 4; `-LordsDayReelBubble YES`
/// shows the scrub bubble as if the rail were being dragged.
struct LordsDayLandingFixture: View {
    let scene: String
    @State private var reel = LordsDayReel(testSermonPageCounts: [])
    @State private var today = Date()
    @State private var opening: ReelPosition?
    @State private var path = NavigationPath()

    private var defaults: UserDefaults { .standard }

    var body: some View {
        let calendar = Calendar.current
        let isSunday = calendar.component(.weekday, from: today) == 1
        let kind: LordsDayLanding.Kind = switch scene {
        case "sunday": .sundayBeforeNotes
        case "drafting": .readingNotes
        case "review": .reviewPending
        case "none": .noSermon
        case "first": .firstSunday
        case "error": .readFailed
        default: .week
        }
        NavigationStack(path: $path) {
            LordsDayLandingView(
                reel: reel, kind: kind, today: today, isSunday: isSunday, offline: scene == "offline",
                stackPage: defaults.object(forKey: "LordsDayStackPage") == nil ? 4 : defaults.integer(forKey: "LordsDayStackPage"),
                draft: Self.draft(scene), onOpenReel: { opening = $0 }
            )
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
        }
        .overlay { FloatingTabBarView(selected: .constant(.lordsDay)) }
        .fullScreenCover(item: Binding(get: { opening.map(FixtureOpening.init) }, set: { opening = $0?.position })) { o in
            LordsDayReelView(reel: reel, start: o.position, allowsNetwork: false, onClose: { opening = nil })
        }
        .task {
            let (reel, today) = Self.make(scene)
            self.reel = reel
            self.today = today
            if let spec = defaults.string(forKey: "LordsDayReelAt") {
                let parts = spec.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2 { opening = ReelPosition(sermon: parts[0], page: parts[1]) }
            }
        }
    }

    private struct FixtureOpening: Identifiable {
        let position: ReelPosition
        var id: ReelPosition { position }
    }

    static func draft(_ scene: String) -> LandingDraft? {
        let sunday = lastSunday(onOrBefore: Date())
        let caps = sunday.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        switch scene {
        case "drafting":
            return LandingDraft(title: "To the Church at Smyrna", passage: "Revelation 2:8–11", preacher: nil, dateCaps: caps,
                                pageCount: 2, pagesRead: 1, progress: 0.55,
                                arrived: ["“Do not fear”: Christ walks among his lampstands.", "I see Christ wrestling there. — Margaret Wilson"],
                                cardCount: 2)
        case "review":
            return LandingDraft(title: "To the Church at Smyrna", passage: "Revelation 2:8–11", preacher: "Rev. [Preacher]",
                                dateCaps: caps, pageCount: 2, pagesRead: 2, progress: 1, arrived: [], cardCount: 7)
        case "error":
            return LandingDraft(title: "To the Church at Smyrna", passage: "Revelation 2:8–11", preacher: "Rev. [Preacher]",
                                dateCaps: caps, pageCount: 2, pagesRead: 1, progress: 1, arrived: [], cardCount: 4, failedPage: 1)
        default: return nil
        }
    }

    @MainActor static func make(_ scene: String) -> (LordsDayReel, Date) {
        let calendar = Calendar.current
        let container = try! ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let thisSunday = lastSunday(onOrBefore: Date(), calendar: calendar)
        // The kept Smyrna sermon is "this week" except where the state needs it gone or a week back.
        let smyrnaWeek: Int? = switch scene {
        case "first", "none": nil
        case "sunday", "drafting", "review", "error": -1
        default: 0
        }
        let today: Date = switch scene {
        case "sunday", "drafting", "review", "error": thisSunday
        default: calendar.date(byAdding: .day, value: 4, to: thisSunday)!
        }
        func sunday(_ weeks: Int) -> Date { calendar.date(byAdding: .day, value: 7 * weeks, to: thisSunday)! }
        guard scene != "first" else { return (LordsDayReel(testSermonPageCounts: []), today) }
        if let week = smyrnaWeek {
            let note = LordsDayNote(serviceDate: sunday(week), passageRef: "Revelation 2:8-11", sermonTitle: "To the Church at Smyrna",
                                    preacher: "Rev. [Preacher]", church: "[Church]")
            try! store.save(note)
            try! store.appendCard(to: note, kind: .keyPoint, body: "The hatred of the world is part of our heritage with Christ.")
            try! store.appendCard(to: note, kind: .verse, body: "", verseRef: "Revelation 2:10")
            try! store.appendCard(to: note, kind: .keyPoint, body: "True union with Christ is a matter of the heart, by the Spirit.")
            let quote = try! store.appendCard(to: note, kind: .quote, body: "I see Christ wrestling there.")
            quote.attribution = "Margaret Wilson"
            try! store.appendCard(to: note, kind: .keyPoint, body: "“Do not fear”: Christ walks among his lampstands; he is with us in his Church.")
            try! store.appendCard(to: note, kind: .verse, body: "", verseRef: "Matthew 16:24")
        }
        let earlier: [(String, String)] = [
            ("Grace upon Grace", "John 1:14-18"), ("The Golden Chain", "Romans 8:28-30"),
            ("Kept by His Power", "1 Peter 1:3-5"), ("The Bread of Life", "John 6:35-40"),
        ]
        let offset = smyrnaWeek == -1 ? -2 : -1
        for (k, item) in earlier.enumerated() {
            let note = LordsDayNote(serviceDate: sunday(offset - k), passageRef: item.1, sermonTitle: item.0, preacher: "Rev. [Preacher]")
            try! store.save(note)
            try! store.appendCard(to: note, kind: .keyPoint, body: "God's purpose, not my circumstances, decides what is good.")
            try! store.appendCard(to: note, kind: .quote, body: "Your worst day is not outside his purpose.")
            try! store.appendCard(to: note, kind: .keyPoint, body: "Union with Christ is the root of every benefit.")
        }
        if scene == "none" {
            let ago = calendar.date(byAdding: .year, value: -1, to: today)!
            let note = LordsDayNote(serviceDate: lastSunday(onOrBefore: ago, calendar: calendar), passageRef: "Acts 2:42-47",
                                    sermonTitle: "The Means of Grace", preacher: "Rev. [Preacher]")
            try! store.save(note)
            for body in ["The Word preached is a means of grace.", "Prayer is the chief exercise of faith."] {
                try! store.appendCard(to: note, kind: .keyPoint, body: body)
            }
        }
        return ((try? LordsDayReel(store: store, today: today, calendar: calendar)) ?? LordsDayReel(testSermonPageCounts: []), today)
    }
}
#endif
