// The reel (TKL-1063, design TKL-1062): one endless vertical pager of every
// card from every kept sermon, newest first, each sermon a cover then its
// cards. Earlier sermons join the pager as you near its end (all from the
// local store, so never a spinner). The top bar names the current sermon and
// "date · N OF M"; the dot rail inside the card shows the current sermon's
// cards, with faint marks for the sermons either side. Dragging on the rail
// scrubs card by card across sermons, and only then a bubble names the sermon.
import SwiftUI
import SwiftData
import DomainKit

struct LordsDayReelView: View {
    let reel: LordsDayReel
    let start: ReelPosition
    var allowsNetwork = true
    var onPage: (ReelSermon, Int) -> Void = { _, _ in }
    var onDetailsUpdated: () -> Void = {}
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(SyncService.self) private var sync
    @State private var loaded: Int
    @State private var current: Int?
    @State private var path = NavigationPath()
    @State private var editingNote: LordsDayNote?
    @State private var scrubStart: Int?
    @State private var bubbleVisible = false
    @State private var bubbleHide: Task<Void, Never>?
    @State private var safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @Environment(\.colorScheme) private var colorScheme

    init(reel: LordsDayReel, start: ReelPosition, allowsNetwork: Bool = true,
         onPage: @escaping (ReelSermon, Int) -> Void = { _, _ in },
         onDetailsUpdated: @escaping () -> Void = {},
         onClose: @escaping () -> Void) {
        self.reel = reel
        self.start = start
        self.allowsNetwork = allowsNetwork
        self.onPage = onPage
        self.onDetailsUpdated = onDetailsUpdated
        self.onClose = onClose
        let loaded = reel.sermonsToLoad(loaded: min(LordsDayReel.initialSermons, reel.sermons.count), through: start.sermon)
        _loaded = State(initialValue: loaded)
        _current = State(initialValue: reel.flatIndex(of: start))
        #if DEBUG
        // Screenshot hook: `-LordsDayReelBubble YES` shows the scrub bubble as if dragging.
        _bubbleVisible = State(initialValue: UserDefaults.standard.bool(forKey: "LordsDayReelBubble"))
        #endif
    }

    private var window: LordsDayReel { reel.window(sermons: loaded) }
    private var flat: Int { current ?? reel.flatIndex(of: start) }
    private var position: ReelPosition { window.position(at: flat) }
    private var sermon: ReelSermon? { window.sermons.indices.contains(position.sermon) ? window.sermons[position.sermon] : nil }
    private var ink: Color {
        guard let sermon else { return .white }
        return Color(hex: LordsDayFeed.palette(sermon.palette(atPage: position.page), dark: colorScheme == .dark).ink)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                pager
                topBar
            }
            .overlay(alignment: .trailing) { railWithBubble.padding(.trailing, 14 + 12) }
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { safeInsets = geo.safeAreaInsets }
                        .onChange(of: geo.safeAreaInsets) { _, insets in safeInsets = insets }
                }
            }
        }
        .onChange(of: current) { _, new in
            guard let new else { return }
            let more = reel.sermonsToLoad(loaded: loaded, atFlat: new)
            if more > loaded { loaded = more }
            let pos = window.position(at: new)
            if let sermon = window.sermons[safe: pos.sermon] { onPage(sermon, pos.page) }
        }
        .onChange(of: allowsNetwork, initial: true) { _, onScreen in
            if onScreen { LoopCounter.dayOpened() }
        }
        .sheet(item: $editingNote) { note in
            EditSermonDetailsSheet(initial: SermonDetailsEdit(note: note)) { edit in
                try sync.lordsDayStore(in: context).updateDetails(edit, for: note)
                onDetailsUpdated()
            }
        }
    }

    // MARK: pager

    private var pager: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<window.pageCount, id: \.self) { index in
                        page(index)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .ignoresSafeArea()
            .onAppear {
                // A paging LazyVStack drops its first scroll position (TKL-1020): scroll after layout.
                let target = reel.flatIndex(of: start)
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .top)
                    current = target
                }
            }
            .background(ScrubScroller(target: scrubStart == nil ? nil : current, proxy: proxy))
            // Saving a sermon's details rebuilds the reel, which can reorder it (a date edit moves the
            // sermon): stay on the same sermon and page, found by id, not on the same flat index (TKL-1115).
            .onChange(of: reel) { old, new in
                let anchored = new.reanchor(old.position(at: flat), from: old)
                let more = new.sermonsToLoad(loaded: min(loaded, new.sermons.count), through: anchored.sermon)
                if more != loaded { loaded = more }
                let target = new.flatIndex(of: anchored)
                guard target != current else { return }
                current = target
                DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
            }
        }
    }

    private func page(_ index: Int) -> some View {
        let pos = window.position(at: index)
        let sermon = window.sermons[pos.sermon]
        return SermonCardView(
            sermon: sermon,
            page: pos.page,
            large: true,
            allowsNetwork: allowsNetwork && index == flat,
            onEditDetails: pos.page == 0 ? {
                if let note = try? sync.lordsDayStore(in: context).note(id: sermon.id) {
                    editingNote = note
                }
            } : nil
        )
        .padding(EdgeInsets(top: safeInsets.top + 58, leading: 14, bottom: max(safeInsets.bottom, 18), trailing: 14))
        .accessibilityIdentifier("lordsDay.reel.page.\(index)")
    }

    // MARK: top bar

    private var topBar: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sermon?.title ?? "")
                    .font(.ccDisplay(14, semibold: true))
                    .lineLimit(1)
                    .id(sermon?.id)
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    .accessibilityIdentifier("lordsDay.reel.title")
                Text(window.topBarSubtitle(position))
                    .font(.ccDisplay(12)).tracking(12 * 0.16).opacity(0.85)
                    .accessibilityIdentifier("lordsDay.reel.subtitle")
            }
            .animation(.easeOut(duration: 0.45), value: sermon?.id)
            Spacer(minLength: 12)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("lordsDay.reel.close")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 50, alignment: .bottom)
    }

    // MARK: the dot rail

    private var railWithBubble: some View {
        let rail = window.rail(at: position)
        return ReelDotRail(rail: rail, ink: ink)
            .overlay(alignment: .trailing) {
                if bubbleVisible, let sermon {
                    ReelBubble(date: position.sermon == 0 ? "THIS WEEK" : sermon.dateCaps, title: sermon.title)
                        .fixedSize()
                        .offset(x: -30, y: ReelDotRail.offset(of: rail))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .gesture(scrub)
            .accessibilityElement()
            .accessibilityLabel("Card \(position.page + 1) of \(rail.dots)")
            .accessibilityIdentifier("lordsDay.reel.rail")
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let from = scrubStart ?? flat
                if scrubStart == nil {
                    scrubStart = from
                    bubbleHide?.cancel()
                    withAnimation(.easeOut(duration: 0.2)) { bubbleVisible = true }
                }
                // Load ahead so the scrub can run past what's on screen.
                var target = ReelScrub.target(from: from, dragOffset: value.translation.height, pageCount: reel.pageCount)
                let more = reel.sermonsToLoad(loaded: loaded, atFlat: target)
                if more > loaded { loaded = more }
                target = min(target, window.pageCount - 1)
                if target != current { current = target }
            }
            .onEnded { _ in
                scrubStart = nil
                bubbleHide?.cancel()
                bubbleHide = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) { bubbleVisible = false }
                }
            }
    }
}

/// Keeps the pager on the scrubbed card while the rail is dragged.
private struct ScrubScroller: View {
    let target: Int?
    let proxy: ScrollViewProxy
    var body: some View {
        Color.clear.onChange(of: target) { _, new in
            guard let new else { return }
            proxy.scrollTo(new, anchor: .top)
        }
    }
}

/// The app's DotRail (TKL-862) for the reel: a dot per page of the current sermon, the
/// current one a longer pill, with two faint marks for the sermon before and after.
struct ReelDotRail: View {
    let rail: ReelRail
    let ink: Color

    static let spacing: CGFloat = 7
    static let dot: CGFloat = 6
    static let on: CGFloat = 20
    static let near: CGFloat = 4
    static let gap: CGFloat = 6

    var body: some View {
        VStack(spacing: Self.spacing) {
            if rail.hasPrevious { nearMarks; Color.clear.frame(width: 1, height: Self.gap) }
            ForEach(0..<rail.dots, id: \.self) { k in
                RoundedRectangle(cornerRadius: 3)
                    .fill(ink.opacity(k == rail.current ? 1 : 0.35))
                    .frame(width: Self.dot, height: k == rail.current ? Self.on : Self.dot)
            }
            if rail.hasNext { Color.clear.frame(width: 1, height: Self.gap); nearMarks }
        }
        .padding(.vertical, 10)
        .frame(width: 24)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: rail)
    }

    private var nearMarks: some View {
        VStack(spacing: Self.spacing) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.18)).frame(width: Self.near, height: Self.near)
            }
        }
    }

    /// The current dot's centre relative to the rail's centre, for the bubble.
    static func offset(of rail: ReelRail) -> CGFloat {
        var items: [CGFloat] = []
        if rail.hasPrevious { items += [near * 2 + spacing, gap] }
        let first = items.count
        items += (0..<rail.dots).map { $0 == rail.current ? on : dot }
        if rail.hasNext { items += [gap, near * 2 + spacing] }
        let total = items.reduce(0, +) + spacing * CGFloat(max(items.count - 1, 0))
        var y: CGFloat = 0
        for (i, h) in items.enumerated() {
            if i == first + rail.current { return y + h / 2 - total / 2 }
            y += h + spacing
        }
        return 0
    }
}

/// While scrubbing: the sermon's date and title on a light Chapel card.
private struct ReelBubble: View {
    let date: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date).font(.ccDisplay(10)).tracking(10 * 0.16).foregroundStyle(.ccGilt)
            Text(title).font(.ccDisplay(14, semibold: true)).foregroundStyle(.ccInk).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ccLine, lineWidth: 1))
        // Always the light card, over any palette.
        .environment(\.colorScheme, .light)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
        .frame(maxWidth: 240, alignment: .trailing)
        .accessibilityIdentifier("lordsDay.reel.bubble")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
