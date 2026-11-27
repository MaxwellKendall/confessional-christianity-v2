// The week as a full-screen card feed (TKL-862, the approved TKL-836 v2
// prototype): one card per screen, swipe up for the next, opening at today's
// card. Everything comes from the local store (DomainKit's LordsDayFeed), so
// nothing waits on the network; a verse card's text is looked up by reference
// as it appears, bundled text first, and the card reads fine without it.
// A verse card opens the verse-by-verse reader on its reference (TKL-879).
// The Sunday cover, Saturday card, archive and empty state are TKL-864/865/868.
import SwiftUI
import SwiftData
import DomainKit
import UniformTypeIdentifiers

struct LordsDayFeedView<HeaderControls: View>: View {
    let feed: LordsDayFeed
    /// False while the tab is mounted but hidden (at launch): verse text then comes from the bundle only.
    var allowsNetwork = true
    let headerControls: (QuoteCardPalette) -> HeaderControls
    @State private var current: UUID?
    @State private var safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @Environment(\.colorScheme) private var colorScheme

    init(
        feed: LordsDayFeed,
        allowsNetwork: Bool = true,
        @ViewBuilder headerControls: @escaping (QuoteCardPalette) -> HeaderControls
    ) {
        self.feed = feed
        self.allowsNetwork = allowsNetwork
        self.headerControls = headerControls
        _current = State(initialValue: feed.todayIndex.map { feed.cards[$0].id })
    }

    private var dark: Bool { colorScheme == .dark }

    private var activeCardId: UUID? {
        current ?? feed.todayIndex.map { feed.cards[$0].id } ?? feed.cards.first?.id
    }

    private var currentPalette: QuoteCardPalette {
        let card = feed.cards.first { $0.id == activeCardId } ?? feed.cards.first
        return LordsDayFeed.palette(card?.palette ?? .vellum, dark: dark)
    }

    private var layout: LordsDayCardLayout {
        LordsDayCardLayout(safeAreaTop: Double(safeInsets.top), safeAreaBottom: Double(safeInsets.bottom))
    }

    var body: some View {
        // `.scrollPosition(id:)` ignores its initial value on first layout of a
        // paging LazyVStack inside a NavigationStack, so the feed opened on
        // Monday's card with the rail on today's (TKL-1020). Scroll there explicitly.
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(feed.cards) { card in
                            let cardPalette = LordsDayFeed.palette(card.palette, dark: dark)
                            let isActiveCard = card.id == activeCardId
                            FeedCardView(
                                card: card,
                                palette: cardPalette,
                                layout: layout,
                                allowsNetwork: allowsNetwork && isActiveCard,
                                readerSource: feed.readerSource(for: card),
                                headerControls: headerControls(cardPalette)
                            )
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(card.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $current)
                .onAppear {
                    guard let today = feed.todayIndex.map({ feed.cards[$0].id }) else { return }
                    // After the first layout pass: scrolling during it is dropped too.
                    DispatchQueue.main.async {
                        proxy.scrollTo(today, anchor: .top)
                        current = today
                    }
                }
            }
            .ignoresSafeArea()
            .overlay(alignment: .trailing) {
                DotRail(ids: feed.cards.map(\.id), current: activeCardId, ink: Color(hex: currentPalette.ink))
                    .padding(.trailing, CGFloat(LordsDayCardLayout.dotRailTrailing))
            }
            .background(Color(hex: currentPalette.field).ignoresSafeArea())
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { safeInsets = geo.safeAreaInsets }
                    .onChange(of: geo.safeAreaInsets) { _, insets in safeInsets = insets }
            }
        }
        // On screen and in the foreground: count the day (once per local day, TKL-947).
        .onChange(of: allowsNetwork, initial: true) { _, onScreen in
            if onScreen { LoopCounter.dayOpened() }
        }
    }
}

extension LordsDayFeedView where HeaderControls == EmptyView {
    init(feed: LordsDayFeed, allowsNetwork: Bool = true) {
        self.init(feed: feed, allowsNetwork: allowsNetwork) { _ in EmptyView() }
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

private struct FeedCardView<HeaderControls: View>: View {
    let card: LordsDayFeedCard
    let palette: QuoteCardPalette
    let layout: LordsDayCardLayout
    let allowsNetwork: Bool
    /// Where the verse card's reader opens; nil for other cards and unparsed references.
    let readerSource: ReaderSource?
    let headerControls: HeaderControls
    @State private var verseText: String?
    @State private var shareImage: ShareImage?
    @Environment(\.colorScheme) private var colorScheme

    private struct ShareImage {
        let png: Data
        let preview: UIImage
    }

    private struct ShareRequest: Equatable {
        let verseText: String?
        let dark: Bool
    }

    private struct VerseRequest: Equatable {
        let reference: String?
        let isActive: Bool
    }

    init(
        card: LordsDayFeedCard,
        palette: QuoteCardPalette,
        layout: LordsDayCardLayout,
        allowsNetwork: Bool,
        readerSource: ReaderSource?,
        headerControls: HeaderControls
    ) {
        self.card = card
        self.palette = palette
        self.layout = layout
        self.allowsNetwork = allowsNetwork
        self.readerSource = readerSource
        self.headerControls = headerControls
        _verseText = State(initialValue: card.verseOsis.flatMap(bundledEsvText).flatMap(Self.nonEmpty))
    }

    private var field: Color { Color(hex: palette.field) }
    private var ink: Color { Color(hex: palette.ink) }
    private var accent: Color { Color(hex: palette.accent) }
    private var muted: Color { Color(hex: palette.muted) }

    var body: some View {
        let border = RoundedRectangle(cornerRadius: 4)
        ZStack {
            field
            FeedCardStackLayout(
                bandSpacing: CGFloat(LordsDayCardLayout.bandSpacing),
                topFraction: CGFloat(LordsDayCardLayout.bodyTopFraction)
            ) {
                headerRow
                bodyBlock
                footerRow
            }
            .padding(CGFloat(LordsDayCardLayout.innerPadding))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                border.strokeBorder(Color(hex: palette.frame).opacity(0.8), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .padding(EdgeInsets(
                top: CGFloat(layout.outerTop),
                leading: CGFloat(LordsDayCardLayout.outerHorizontal),
                bottom: CGFloat(layout.outerBottomInset),
                trailing: CGFloat(LordsDayCardLayout.outerHorizontal)
            ))
        }
        .foregroundStyle(ink)
        .task(id: VerseRequest(reference: card.verseOsis, isActive: allowsNetwork)) {
            guard allowsNetwork, verseText == nil, let osis = card.verseOsis else { return }
            let text = Self.nonEmpty(await EsvClient.shared.text(for: osis))
            guard !Task.isCancelled else { return }
            verseText = text
        }
        .task(id: ShareRequest(verseText: verseText, dark: colorScheme == .dark)) {
            let card = card, verseText = verseText, dark = colorScheme == .dark
            let image = await Task.detached(priority: .userInitiated) { () -> ShareImage? in
                guard let png = card.sharePNG(verseText: verseText, dark: dark),
                      let preview = UIImage(data: png) else { return nil }
                return ShareImage(png: png, preview: preview)
            }.value
            guard !Task.isCancelled else { return }
            shareImage = image
        }
        .onChange(of: card.verseOsis) { _, reference in
            verseText = reference.flatMap(bundledEsvText).flatMap(Self.nonEmpty)
        }
    }

    @ViewBuilder private var headerRow: some View {
        let controls = headerControls
        if let day = card.dayLabel {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    dayLabel(day)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    controls
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        controls
                    }
                    dayLabel(day)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                controls
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func dayLabel(_ day: String) -> some View {
        Text(day)
            .font(.ccDisplay(11))
            .tracking(11 * 0.18)
            .textCase(.uppercase)
            .foregroundStyle(card.isToday ? accent : muted)
            .lineLimit(1)
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            kindLabel.padding(.bottom, 26)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .lineLimit(9)
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
                    .padding(.top, 18)
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

    /// Single footer row inside the card's inner padding: contextual per-card
    /// action on the leading side and Share anchored on the trailing side.
    private var footerRow: some View {
        ViewThatFits(in: .horizontal) {
            footerContent(compact: false)
            footerContent(compact: true)
        }
    }

    private func footerContent(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let readerSource {
                NavigationLink(value: ScriptureRoute.reader(readerSource)) {
                    HStack(spacing: 6) {
                        if !compact {
                            Image(systemName: "book")
                                .font(.subheadline.weight(.medium))
                        }
                        Text("Read full passage")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(compact ? 0.8 : 1)
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, compact ? 12 : 14)
                    .frame(minHeight: 44)
                    .background(ink.opacity(0.10), in: Capsule())
                }
                .fixedSize(horizontal: !compact, vertical: false)
                .accessibilityIdentifier("lordsDay.readFullPassage")
            }
            Spacer(minLength: 0)
            shareButton(compact: compact)
                .fixedSize(horizontal: !compact, vertical: false)
                .accessibilityLabel("Share this card")
                .simultaneousGesture(TapGesture().onEnded { LoopCounter.record(.cardShared(kind: card.kind)) })
        }
        .frame(maxWidth: .infinity)
    }

    /// Share sends the card as a square PNG with its words as the message
    /// (TKL-1060). The image is pre-rendered off the main thread, so the sheet
    /// opens at once; until it's ready, Share sends the words alone.
    @ViewBuilder private func shareButton(compact: Bool) -> some View {
        let text = card.shareText(verseText: verseText)
        if let shareImage {
            ShareLink(
                item: SharedCardImage(png: shareImage.png),
                message: Text(text),
                preview: SharePreview(card.kind.label, image: Image(uiImage: shareImage.preview))
            ) { shareLabel(compact: compact) }
        } else {
            ShareLink(item: text) { shareLabel(compact: compact) }
        }
    }

    private func shareLabel(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
            Text("Share")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.85 : 1)
        }
        .foregroundStyle(field)
        .padding(.horizontal, compact ? 14 : 16)
        .frame(minHeight: 44)
        .background(accent, in: Capsule())
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

/// The card's PNG for the share sheet: Save Image, Messages and the rest get an image.
private struct SharedCardImage: Transferable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("Confessional Christianity.png")
    }
}

/// Three-band card layout (header, optically placed body, footer) inside the
/// hairline border. Anchors header to top and footer to bottom while placing
/// the body optically above the vertical midpoint.
private struct FeedCardStackLayout: Layout {
    let bandSpacing: CGFloat
    let topFraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let widthProposal = ProposedViewSize(width: bounds.width, height: nil)
        let headerSize = subviews[0].sizeThatFits(widthProposal)
        let footerSize = subviews[2].sizeThatFits(widthProposal)

        let topGap: CGFloat = headerSize.height > 0 ? bandSpacing : 0
        let bottomGap: CGFloat = footerSize.height > 0 ? bandSpacing : 0
        let bandTop = bounds.minY + headerSize.height + topGap
        let bandBottom = bounds.maxY - footerSize.height - bottomGap
        let bandHeight = max(0, bandBottom - bandTop)

        let bodyProposal = ProposedViewSize(width: bounds.width, height: bandHeight)
        let bodySize = subviews[1].sizeThatFits(bodyProposal)
        let clampedBodyHeight = min(bodySize.height, bandHeight)
        let bodyY = CGFloat(LordsDayCardLayout.bodyOriginY(
            bandTop: Double(bandTop),
            bandHeight: Double(bandHeight),
            contentHeight: Double(clampedBodyHeight)
        ))

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: headerSize.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bodyY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: clampedBodyHeight)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - footerSize.height),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: footerSize.height)
        )
    }
}

/// Shared visual treatment for the feed header pills so `LordsDayTabView` and
/// `LordsDayFeedFixture` render identical controls inside the card border.
struct LordsDayHeaderPillLabel: View {
    let title: String
    let systemImage: String
    let ink: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(ink.opacity(0.12), in: Capsule())
    }
}

struct LordsDayHeaderCameraLabel: View {
    let ink: Color
    var systemImage = "camera"

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(ink)
            .frame(width: 40, height: 40)
            .background(ink.opacity(0.12), in: Circle())
    }
}

#if DEBUG
/// Screenshot hook: `-LordsDayFeedFixture key_point|quote|verse|verse_offline|smyrna`
/// shows a sample week from an in-memory store whose card for today is that
/// kind. `verse_offline` is a verse whose text isn't bundled (pair it with
/// `-EsvOffline YES`); `sermon` is a verse card on the sermon text, Romans 8:28–30
/// (add `-LordsDayFeedOpensReader YES` to open the reader on it, TKL-879). Add `-SaveLordsDayFeedFixture YES` to seed a
/// separate disk store, then launch with `-LordsDayFeedFixture saved` to reopen it.
struct LordsDayFeedFixture: View {
    let scene: String
    @State private var feed: LordsDayFeed?
    @State private var path = NavigationPath()
    /// Pushed screens such as the reader hide the bar, as in RootView.
    @State private var hidesBar = false

    var body: some View {
        ZStack {
            if scene == "saved" {
                LordsDayTabView(path: $path, startsCapture: .constant(false), reminder: .constant(nil))
                    .modelContainer(Self.savedContainer)
            } else if let feed {
                let showHeader = UserDefaults.standard.bool(forKey: "LordsDayFeedShowHeader")
                let pendingReviews = UserDefaults.standard.integer(forKey: "LordsDayFeedPendingReviews")
                NavigationStack(path: $path) {
                    LordsDayFeedView(feed: feed) { palette in
                        if showHeader || pendingReviews > 0 {
                            let ink = Color(hex: palette.ink)
                            HStack(spacing: 8) {
                                if pendingReviews > 0 {
                                    Button {} label: {
                                        LordsDayHeaderPillLabel(
                                            title: pendingReviews == 1 ? "Review cards" : "Review cards (\(pendingReviews))",
                                            systemImage: "rectangle.stack",
                                            ink: ink
                                        )
                                    }
                                    .accessibilityIdentifier("lordsDay.review")
                                }
                                Button {} label: {
                                    LordsDayHeaderCameraLabel(ink: ink, systemImage: "book.closed")
                                }
                                .accessibilityLabel("Journal")
                                .accessibilityIdentifier("lordsDay.journal")
                                Button {} label: {
                                    LordsDayHeaderCameraLabel(ink: ink)
                                }
                                .accessibilityLabel("Photograph Sunday's notes")
                                .accessibilityIdentifier("lordsDay.capture")
                            }
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .appDestinations(path: $path)
                }
                .onHidesFloatingTabBarChange { hidesBar = $0 }
                .task {
                    // `-LordsDayFeedFixture sermon -LordsDayFeedOpensReader YES`: push the reader for today's card.
                    if UserDefaults.standard.bool(forKey: "LordsDayFeedOpensReader"),
                       let index = feed.todayIndex, let source = feed.readerSource(for: feed.cards[index]) {
                        path.append(ScriptureRoute.reader(source))
                    }
                }
            }
        }
        .overlay { if !hidesBar { FloatingTabBarView(selected: .constant(.lordsDay)) } }
        .task {
            guard scene != "saved" else { return }
            if UserDefaults.standard.bool(forKey: "SaveLordsDayFeedFixture") {
                let store = LordsDayStore(context: Self.savedContainer.mainContext)
                feed = (try? LordsDayFeed(store: store, today: Date(), calendar: .current))
                    ?? Self.makeFeed(scene, container: Self.savedContainer)
            } else {
                feed = Self.makeFeed(scene)
            }
        }
    }

    private static let savedContainer = try! ModelContainer(
        for: progressSchema,
        configurations: [ModelConfiguration("LordsDayFeedFixture", schema: progressSchema, cloudKitDatabase: .none)]
    )

    @MainActor static func makeFeed(_ scene: String, today: Date = Date(), container: ModelContainer? = nil) -> LordsDayFeed {
        let container = container ?? (try! ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)]))
        let store = LordsDayStore(context: container.mainContext)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: today))!
        if scene == "smyrna" { return smyrnaFeed(store: store, sunday: sunday, today: today) }
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
        case "verse_long": .verse("Psalm 145")
        case "verse_offline": .verse("Romans 8:28")
        case "sermon": .verse("Romans 8:28–30")
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

    /// `-LordsDayFeedFixture smyrna`: the Revelation 2:8-11 note with its title and a
    /// placeholder preacher (TKL-1061), every card a key point so today's names the sermon.
    @MainActor private static func smyrnaFeed(store: LordsDayStore, sunday: Date, today: Date) -> LordsDayFeed {
        let note = LordsDayNote(serviceDate: sunday, passageRef: "Revelation 2:8-11", sermonTitle: "To the Church at Smyrna",
                                preacher: FixtureCardsGenerator.smyrnaSermon.preacher)
        try! store.save(note)
        for point in [
            "The hatred of the world is part of our heritage with Christ (John 15:18-25).",
            "True union with Christ is a matter of the heart, by the Spirit (Rom 2:28-29).",
            "“Do not fear”: Christ walks among his lampstands; he is with us in his Church.",
            "The Devil is behind these fiery persecutions, but we are called to endure his rage.",
            "God is behind the testing, and Jesus tests our faith.",
            "The crown is our participation in the victory of Christ over sin, death, hell, and the Devil.",
        ] { try! store.appendCard(to: note, kind: .keyPoint, body: point) }
        return LordsDayFeed(note: note, cards: try! store.cards(for: note), today: today)
    }
}
#endif
