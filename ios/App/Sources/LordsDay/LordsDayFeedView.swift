// The week as a full-screen card feed (TKL-862, the approved TKL-836 v2
// prototype): one card per screen, swipe up for the next, opening at today's
// card. Everything comes from the local store (DomainKit's LordsDayFeed), so
// nothing waits on the network; a verse card's text is looked up by reference
// as it appears, bundled text first, and the card reads fine without it.
// The Sunday cover, Saturday card, archive and empty state are TKL-864/865/868.
import SwiftUI
import SwiftData
import DomainKit

struct LordsDayFeedView: View {
    let feed: LordsDayFeed
    /// False while the tab is mounted but hidden (at launch): verse text then comes from the bundle only.
    var allowsNetwork = true
    @State private var current: UUID?
    @Environment(\.colorScheme) private var colorScheme

    init(feed: LordsDayFeed, allowsNetwork: Bool = true) {
        self.feed = feed
        self.allowsNetwork = allowsNetwork
        _current = State(initialValue: feed.todayIndex.map { feed.cards[$0].id })
    }

    private var dark: Bool { colorScheme == .dark }

    private var currentPalette: QuoteCardPalette {
        let card = feed.cards.first { $0.id == current } ?? feed.cards.first
        return LordsDayFeed.palette(card?.palette ?? .vellum, dark: dark)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(feed.cards) { card in
                    FeedCardView(card: card, palette: LordsDayFeed.palette(card.palette, dark: dark), allowsNetwork: allowsNetwork)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(card.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $current)
        .ignoresSafeArea()
        .overlay(alignment: .trailing) {
            DotRail(ids: feed.cards.map(\.id), current: current ?? feed.cards.first?.id, ink: Color(hex: currentPalette.ink))
                .padding(.trailing, 7)
        }
        .background(Color(hex: currentPalette.field).ignoresSafeArea())
    }
}

/// Position in the week: one dot per card, the current one drawn long.
private struct DotRail: View {
    let ids: [UUID]
    let current: UUID?
    let ink: Color

    var body: some View {
        VStack(spacing: 5) {
            ForEach(ids, id: \.self) { id in
                RoundedRectangle(cornerRadius: 2)
                    .fill(id == current ? ink : ink.opacity(0.27))
                    .frame(width: 4, height: id == current ? 16 : 4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel(ids.firstIndex(of: current ?? UUID()).map { "Card \($0 + 1) of \(ids.count)" } ?? "")
    }
}

private struct FeedCardView: View {
    let card: LordsDayFeedCard
    let palette: QuoteCardPalette
    let allowsNetwork: Bool
    @State private var verseText: String?

    init(card: LordsDayFeedCard, palette: QuoteCardPalette, allowsNetwork: Bool) {
        self.card = card
        self.palette = palette
        self.allowsNetwork = allowsNetwork
        _verseText = State(initialValue: card.verseOsis.flatMap(bundledEsvText).flatMap(Self.nonEmpty))
    }

    private var field: Color { Color(hex: palette.field) }
    private var ink: Color { Color(hex: palette.ink) }
    private var accent: Color { Color(hex: palette.accent) }
    private var muted: Color { Color(hex: palette.muted) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            field
            // The hairline frame.
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(hex: palette.frame).opacity(0.8), lineWidth: 1)
                .padding(EdgeInsets(top: 92, leading: 16, bottom: 104, trailing: 16))

            if let day = card.dayLabel {
                Text(day)
                    .font(.ccDisplay(11))
                    .tracking(11 * 0.18)
                    .textCase(.uppercase)
                    .foregroundStyle(card.isToday ? accent : muted)
                    .padding(.top, 110)
                    .padding(.leading, 34)
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                kindLabel.padding(.bottom, 26)
                content
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 130, leading: 34, bottom: 150, trailing: 64))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            actions
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 12)
                .padding(.bottom, 124)
        }
        .foregroundStyle(ink)
        .task(id: allowsNetwork) {
            guard allowsNetwork, verseText == nil, let osis = card.verseOsis else { return }
            verseText = Self.nonEmpty(await EsvClient.shared.text(for: osis))
        }
    }

    private var kindLabel: some View {
        HStack(spacing: 10) {
            Rectangle().fill(accent).frame(width: 22, height: 1)
            Text(card.kind.label)
                .font(.ccDisplay(11))
                .tracking(11 * 0.22)
                .textCase(.uppercase)
                .foregroundStyle(accent)
            Rectangle().fill(accent).frame(width: 22, height: 1)
        }
    }

    @ViewBuilder private var content: some View {
        switch card.kind {
        case .keyPoint:
            bodyText(card.body, size: 30)
            attribution
        case .quote:
            Text("\u{201C}")
                .font(.ccDisplay(84))
                .foregroundStyle(accent)
                .frame(height: 34, alignment: .top)
                .padding(.leading, -4)
            bodyText(card.body, size: 28)
            attribution
        case .verse:
            if let verseText {
                let parts = verseLead(verseText)
                (Text(parts.lead.isEmpty ? "" : parts.lead + " ").font(.ccDisplay(27)).foregroundColor(accent)
                    + Text(parts.rest).font(.ccBody(27)))
                    .lineSpacing(27 * 0.38 - 8)
                    .lineLimit(14)
                    .minimumScaleFactor(0.5)
            } else {
                // No text yet (offline, or a reference that doesn't parse): the reference carries the card.
                bodyText(card.reference ?? "", size: 34)
                Text(card.verseOsis == nil ? "Open it in your Bible." : "The verse appears when you're online.")
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
                    .padding(.top, 18)
            }
            if verseText != nil, let ref = card.reference {
                Text(ref)
                    .font(.ccDisplay(12))
                    .tracking(12 * 0.18)
                    .textCase(.uppercase)
                    .foregroundStyle(accent)
                    .padding(.top, 24)
            }
        }
    }

    private func bodyText(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.ccBody(size))
            .lineSpacing(size * 0.38 - 8)
            .lineLimit(14)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder private var attribution: some View {
        if let line = card.attributionLine {
            Text(line)
                .font(.system(size: 13))
                .foregroundStyle(muted)
                .padding(.top, 22)
        }
    }

    /// Share comes first on every card. Until TKL-844's share flow lands, it
    /// hands the card's words and reference to the system share sheet.
    private var actions: some View {
        VStack(spacing: 14) {
            ShareLink(item: card.shareText(verseText: verseText)) {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 42, height: 42)
                        .background(accent, in: Circle())
                        .foregroundStyle(field)
                    Text("Share")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ink.opacity(0.9))
                }
                .frame(width: 44)
            }
            .accessibilityLabel("Share this card")
        }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

#if DEBUG
/// Screenshot hook: `-LordsDayFeedFixture key_point|quote|verse|verse_offline`
/// shows a sample week from an in-memory store whose card for today is that
/// kind. `verse_offline` is a verse whose text isn't bundled (pair it with
/// `-EsvOffline YES`).
struct LordsDayFeedFixture: View {
    let scene: String
    @State private var feed: LordsDayFeed?

    var body: some View {
        ZStack {
            if let feed { LordsDayFeedView(feed: feed) }
        }
        .overlay(alignment: .bottom) { FloatingTabBarView(selected: .constant(.lordsDay)) }
        .task { feed = Self.makeFeed(scene) }
    }

    @MainActor static func makeFeed(_ scene: String, today: Date = Date()) -> LordsDayFeed {
        let container = try! ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
        let store = LordsDayStore(context: ModelContext(container))
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: today))!
        let note = LordsDayNote(serviceDate: sunday, passageRef: "Romans 8:28–30", preacher: "Rev. [your pastor]")
        try! store.save(note)
        enum Sample { case point(String), quote(String), verse(String) }
        var week: [Sample] = [
            .verse("Psalm 118:24"),
            .point("God's purpose, not my circumstances, decides what is good."),
            .quote("Your worst day is not outside his purpose. It is inside it, and he is not finished."),
            .verse("John 3:16"),
            .quote("The golden chain has no weak link, because God forged every one."),
            .point("“Glorified” is in the past tense. Tomorrow, worship like it is already settled."),
        ]
        let todayIndex = todayCardIndex(serviceDate: sunday, today: today, cardCount: week.count) ?? 0
        week[todayIndex] = switch scene {
        case "quote": .quote("Your worst day is not outside his purpose. It is inside it, and he is not finished.")
        case "verse": .verse("John 3:16")
        case "verse_offline": .verse("Romans 8:28")
        default: .point("God's purpose, not my circumstances, decides what is good.")
        }
        for sample in week {
            switch sample {
            case .point(let s): try! store.appendCard(to: note, kind: .keyPoint, body: s)
            case .quote(let s): try! store.appendCard(to: note, kind: .quote, body: s)
            case .verse(let r): try! store.appendCard(to: note, kind: .verse, body: "", verseRef: r)
            }
        }
        return LordsDayFeed(note: note, cards: try! store.cards(for: note), today: today)
    }
}
#endif
