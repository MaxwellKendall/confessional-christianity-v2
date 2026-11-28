import Foundation

// The Lord's Day landing page and its reel (TKL-1063, design TKL-1062). A kept
// sermon is a stack: a cover, then its cards in order, not tied to days. The
// reel is one vertical pager of every kept sermon's stack, newest first. Pure
// values built from the local store, so it all renders offline.

/// A place in the reel: which sermon (0 = newest), and which page of its stack (0 = the cover).
public struct ReelPosition: Hashable, Sendable {
    public let sermon: Int
    public let page: Int
    public init(sermon: Int, page: Int) { self.sermon = sermon; self.page = page }
}

/// One kept sermon as a stack.
public struct ReelSermon: Identifiable, Equatable, Sendable {
    /// The note's id.
    public let id: UUID
    public let serviceDate: Date
    /// The sermon's title, else its passage, else its date ("Sunday, November 8").
    public let title: String
    /// "passage · preacher", the parts the notes gave (the passage only when it isn't the title).
    public let meta: String?
    public let passage: String?
    public let preacher: String?
    public let church: String?
    /// "Nov 22", with the year when it isn't the current one ("Nov 23, 2025").
    public let shortDate: String
    /// "NOV 22", the binding's and top bar's date.
    public let dateCaps: String
    /// "Sunday, November 22".
    public let longDate: String
    /// The kept cards, in order, each in its palette.
    public let cards: [LordsDayFeedCard]
    /// The cover's palette (light), which also colours the sermon's tile on the landing page.
    public let coverPalette: QuoteCardPalette
    /// The sermon's passage as OSIS, when it parses.
    public let passageOsis: String?
    /// For verse cards' Read button.
    let feed: LordsDayFeed?
    let testPageCount: Int?

    /// A cover, then the cards.
    public var pageCount: Int { testPageCount ?? (cards.count + 1) }

    /// Page `page`'s card, or nil for the cover.
    public func card(atPage page: Int) -> LordsDayFeedCard? {
        page >= 1 && page <= cards.count ? cards[page - 1] : nil
    }

    /// Page `page`'s light palette: the cover's, or that card's.
    public func palette(atPage page: Int) -> QuoteCardPalette { card(atPage: page)?.palette ?? coverPalette }

    /// A verse card opens the reader on its own reference.
    public func readerSource(for card: LordsDayFeedCard) -> ReaderSource? { feed?.readerSource(for: card) }

    @MainActor init(note: LordsDayNote, cards noteCards: [NoteCard], today: Date, calendar: Calendar) {
        id = note.id
        serviceDate = note.serviceDate
        let title = normalizedNoteField(note.sermonTitle)
        let passage = normalizedNoteField(note.passageRef)
        let preacher = normalizedNoteField(note.preacher)
        self.passage = passage
        self.preacher = preacher
        church = normalizedNoteField(note.church)
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: note.serviceDate)
        let month = parts.month ?? 1, day = parts.day ?? 1, year = parts.year ?? 0
        let month3 = ReelSermon.months[month - 1].prefix(3)
        let sameYear = calendar.component(.year, from: today) == year
        shortDate = "\(month3) \(day)" + (sameYear ? "" : ", \(year)")
        dateCaps = shortDate.uppercased()
        longDate = "\(LordsDayFeed.weekdays[(parts.weekday ?? 1) - 1]), \(ReelSermon.months[month - 1]) \(day)"
        self.title = title ?? passage ?? longDate
        let beneath = [title == nil ? nil : passage, preacher].compactMap { $0 }
        meta = beneath.isEmpty ? nil : beneath.joined(separator: " · ")
        let feed = LordsDayFeed(note: note, cards: noteCards, today: today, calendar: calendar)
        self.feed = feed
        passageOsis = feed.passageOsis
        // Each week gets its own cover colour; the cards follow it round the rotation.
        let rotation = LordsDayFeed.rotation
        let week = Int((calendar.startOfDay(for: note.serviceDate).timeIntervalSince1970 / 86_400 / 7).rounded(.down))
        let start = ((week % rotation.count) + rotation.count) % rotation.count
        coverPalette = rotation[start]
        self.cards = zip(feed.cards, noteCards).enumerated().map { index, pair in
            let palette = pair.1.palette.flatMap(QuoteCardPalette.named) ?? rotation[(start + index + 1) % rotation.count]
            return pair.0.withPalette(palette)
        }
        testPageCount = nil
    }

    init(testPageCount: Int, index: Int) {
        id = UUID(); serviceDate = Date(timeIntervalSince1970: Double(-index) * 7 * 86_400)
        title = "Sermon \(index)"; meta = nil; passage = nil; preacher = nil; church = nil
        shortDate = "Nov \(index + 1)"; dateCaps = shortDate.uppercased(); longDate = shortDate
        cards = []; coverPalette = .psalter; passageOsis = nil; feed = nil
        self.testPageCount = testPageCount
    }

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                         "October", "November", "December"]
}

extension LordsDayFeedCard {
    func withPalette(_ palette: QuoteCardPalette) -> LordsDayFeedCard {
        LordsDayFeedCard(id: id, kind: kind, body: body, reference: reference, verseOsis: verseOsis, palette: palette,
                         dayLabel: nil, isToday: false, attributionLine: attributionLine, passage: passage, speaker: speaker)
    }
}

/// The dot rail's state at a position: one dot per page of the current sermon, and
/// whether faint marks stand for a newer (above) and an older (below) sermon.
public struct ReelRail: Equatable, Sendable {
    public let dots: Int
    public let current: Int
    public let hasPrevious: Bool
    public let hasNext: Bool
    public init(dots: Int, current: Int, hasPrevious: Bool, hasNext: Bool) {
        self.dots = dots; self.current = current; self.hasPrevious = hasPrevious; self.hasNext = hasNext
    }
}

/// Dragging on the dot rail: one card per dot spacing, across sermons.
public enum ReelScrub {
    /// Points of drag per card (the rail's dot pitch).
    public static let spacing: Double = 14
    public static func target(from start: Int, dragOffset: Double, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let steps = Int((dragOffset / spacing).rounded())
        return min(max(start + steps, 0), pageCount - 1)
    }
}

public struct LordsDayReel: Equatable, Sendable {
    /// Newest first.
    public let sermons: [ReelSermon]
    /// More (older) sermons exist beyond these.
    public let hasMore: Bool
    private let starts: [Int]

    /// Sermons the reel opens with; earlier ones load as you near the end.
    public static let initialSermons = 3
    /// Pages from the loaded end at which two more sermons load.
    public static let lookahead = 6

    @MainActor public init(store: LordsDayStore, today: Date = Date(), calendar: Calendar = .current) throws {
        var built: [ReelSermon] = []
        let notes = try store.allNotes().sorted { ($0.serviceDate, $0.updatedAt) > ($1.serviceDate, $1.updatedAt) }
        for note in notes {
            let cards = try store.cards(for: note)
            if !cards.isEmpty { built.append(ReelSermon(note: note, cards: cards, today: today, calendar: calendar)) }
        }
        self.init(sermons: built, hasMore: false)
    }

    init(sermons: [ReelSermon], hasMore: Bool) {
        self.sermons = sermons
        self.hasMore = hasMore
        var starts: [Int] = [], total = 0
        for sermon in sermons { starts.append(total); total += sermon.pageCount }
        self.starts = starts
    }

    /// For tests: sermons with these page counts.
    public init(testSermonPageCounts counts: [Int], hasMore: Bool = false) {
        self.init(sermons: counts.enumerated().map { ReelSermon(testPageCount: $1, index: $0) }, hasMore: hasMore)
    }

    public var pageCount: Int { (starts.last ?? 0) + (sermons.last?.pageCount ?? 0) }

    /// The first `count` sermons, marked as having more when some were left out.
    public func window(sermons count: Int) -> LordsDayReel {
        let n = min(max(count, 0), sermons.count)
        return LordsDayReel(sermons: Array(sermons.prefix(n)), hasMore: n < sermons.count)
    }

    /// How many sermons should be loaded with `loaded` loaded and the reel at `flat`:
    /// two more once within `lookahead` pages of the loaded end.
    public func sermonsToLoad(loaded: Int, atFlat flat: Int) -> Int {
        let loadedPages = sermons.prefix(loaded).reduce(0) { $0 + $1.pageCount }
        guard flat >= loadedPages - Self.lookahead else { return min(loaded, sermons.count) }
        return min(loaded + 2, sermons.count)
    }

    /// Opening the reel at sermon `index`: load through it and one past.
    public func sermonsToLoad(loaded: Int, through index: Int) -> Int {
        min(max(loaded, index + 2), sermons.count)
    }

    /// Where the reel opens for a sermon picked in the journal (TKL-1085): at that
    /// sermon, on the card last read there (its cover if never read), or nil when
    /// the note has no kept cards and so isn't in the reel.
    public func opening(sermon id: UUID, memory: LordsDayStackMemory) -> ReelPosition? {
        guard let index = sermons.firstIndex(where: { $0.id == id }) else { return nil }
        return ReelPosition(sermon: index, page: memory.page(for: sermons[index]))
    }

    public func flatIndex(of position: ReelPosition) -> Int {
        guard !sermons.isEmpty else { return 0 }
        let s = min(max(position.sermon, 0), sermons.count - 1)
        return starts[s] + min(max(position.page, 0), sermons[s].pageCount - 1)
    }

    public func position(at flat: Int) -> ReelPosition {
        guard !sermons.isEmpty else { return ReelPosition(sermon: 0, page: 0) }
        let f = min(max(flat, 0), pageCount - 1)
        let s = (starts.lastIndex { $0 <= f }) ?? 0
        return ReelPosition(sermon: s, page: f - starts[s])
    }

    /// The binding's count: "7 cards" on the cover, "5 of 7" on a card.
    public func countLabel(_ position: ReelPosition) -> String {
        guard sermons.indices.contains(position.sermon) else { return "" }
        let n = sermons[position.sermon].pageCount
        return position.page == 0 ? "\(n) cards" : "\(position.page + 1) of \(n)"
    }

    /// The reel's top bar under the title: "NOV 22 · 5 OF 7".
    public func topBarSubtitle(_ position: ReelPosition) -> String {
        guard sermons.indices.contains(position.sermon) else { return "" }
        let sermon = sermons[position.sermon]
        return "\(sermon.dateCaps) · \(position.page + 1) OF \(sermon.pageCount)"
    }

    public func rail(at position: ReelPosition) -> ReelRail {
        guard sermons.indices.contains(position.sermon) else { return ReelRail(dots: 0, current: 0, hasPrevious: false, hasNext: false) }
        return ReelRail(dots: sermons[position.sermon].pageCount, current: position.page,
                        hasPrevious: position.sermon > 0, hasNext: position.sermon < sermons.count - 1 || hasMore)
    }

    /// The sermon kept for the week `today` falls in (its Sunday on or before today).
    public func thisWeek(today: Date, calendar: Calendar = .current) -> ReelSermon? {
        sermons.first { inWeek($0.serviceDate, of: today, calendar) }
    }

    /// Every sermon before this week's, newest first.
    public func earlier(today: Date, calendar: Calendar = .current) -> [ReelSermon] {
        let sunday = lastSunday(onOrBefore: today, calendar: calendar)
        return sermons.filter { calendar.startOfDay(for: $0.serviceDate) < sunday }
    }

    /// The sermon kept in this week a year ago.
    public func yearAgo(today: Date, calendar: Calendar = .current) -> ReelSermon? {
        guard let then = calendar.date(byAdding: .year, value: -1, to: today) else { return nil }
        return sermons.first { inWeek($0.serviceDate, of: then, calendar) }
    }

    /// The sermon's index, for opening the reel at its cover.
    public func index(of id: UUID) -> Int? { sermons.firstIndex { $0.id == id } }

    private func inWeek(_ date: Date, of day: Date, _ calendar: Calendar) -> Bool {
        let sunday = lastSunday(onOrBefore: day, calendar: calendar)
        let days = calendar.dateComponents([.day], from: sunday, to: calendar.startOfDay(for: date)).day ?? -1
        return (0..<7).contains(days)
    }

    public static func == (a: Self, b: Self) -> Bool { a.sermons == b.sermons && a.hasMore == b.hasMore }
}

/// Which page each sermon's stack was last on, so the stack reopens there.
public struct LordsDayStackMemory: Equatable, Sendable {
    private var pages: [UUID: Int] = [:]
    public init() {}

    /// From its stored form (note id → page); bad entries are dropped.
    public init(stored: [String: Int]) {
        for (key, page) in stored { if let id = UUID(uuidString: key), page >= 0 { pages[id] = page } }
    }

    public var stored: [String: Int] { Dictionary(uniqueKeysWithValues: pages.map { ($0.key.uuidString, $0.value) }) }

    public mutating func remember(page: Int, for id: UUID) { pages[id] = max(page, 0) }

    public func page(for sermon: ReelSermon) -> Int {
        min(max(pages[sermon.id] ?? 0, 0), max(sermon.pageCount - 1, 0))
    }

    /// The two pages peeking behind the top one: the next two, wrapping to the cover.
    public static func peeking(after page: Int, pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        return [(page + 1) % pageCount, (page + 2) % pageCount]
    }
}

/// What the landing page shows.
public enum LordsDayLanding {
    public enum Kind: Equatable, Sendable {
        /// This week's sermon is kept: its stack.
        case week
        /// Sunday, nothing captured yet, with earlier Lord's Days kept.
        case sundayBeforeNotes
        /// Notes are being read.
        case readingNotes
        /// Drafted cards wait for review.
        case reviewPending
        /// No sermon kept this week (not Sunday).
        case noSermon
        /// Nothing kept ever.
        case firstSunday
        /// Reading a page failed.
        case readFailed
    }

    public static func kind(isSunday: Bool, hasThisWeeksSermon: Bool, hasAnyKeptSermon: Bool, isReadingNotes: Bool,
                            readFailed: Bool, hasPendingReview: Bool, pendingReviewIsEmpty: Bool = false) -> Kind {
        if readFailed { return .readFailed }
        if isReadingNotes { return .readingNotes }
        // A review with nothing to keep doesn't hide the week's kept sermon (TKL-1103).
        if hasPendingReview && !(pendingReviewIsEmpty && hasThisWeeksSermon) { return .reviewPending }
        if hasThisWeeksSermon { return .week }
        if !hasAnyKeptSermon { return .firstSunday }
        return isSunday ? .sundayBeforeNotes : .noSermon
    }

    /// The kept stack shows while a review with nothing to keep waits (TKL-1103): the landing adds a
    /// small note under it that opens that review, so it can still be discarded.
    public static func showsEmptyReviewNote(kind: Kind, hasPendingReview: Bool, pendingReviewIsEmpty: Bool) -> Bool {
        kind == .week && hasPendingReview && pendingReviewIsEmpty
    }

    public static func title(kind: Kind, isSunday: Bool) -> String {
        if kind == .firstSunday { return "Your sermon journal" }
        return isSunday ? "Today" : "This week"
    }
}
