import Foundation

// The week as a card feed (TKL-862): one full-screen card per day, opening at
// today's card. Pure values built from the local store, so the feed renders
// with no network. Verse cards carry a reference only; the app resolves the
// text through the scripture path at render time.

extension CardKind {
    public var label: String {
        switch self {
        case .keyPoint: "Key point"
        case .quote: "Quote"
        case .verse: "Verse"
        }
    }
}

public struct LordsDayFeedCard: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: CardKind
    /// The words for key points and quotes; empty for verses.
    public let body: String
    /// A verse's reference as stored ("Romans 8:28"), readable even when it isn't OSIS.
    public let reference: String?
    /// The OSIS id the scripture path fetches by, or nil when the reference doesn't parse.
    public let verseOsis: String?
    /// The light-mode palette; use `LordsDayFeed.palette(_:dark:)` for the one on screen.
    public let palette: QuoteCardPalette
    public let dayLabel: String?
    public let isToday: Bool
    /// The quiet line under the body: who said it, or where the point came from.
    public let attributionLine: String?
    /// The sermon's passage, for the share text.
    public let passage: String?

    /// What the system share sheet gets until TKL-844's share flow lands: the
    /// card's words and its reference.
    public func shareText(verseText: String? = nil) -> String {
        switch kind {
        case .keyPoint:
            return passage.map { "\(body)\n\nFrom notes on \($0)" } ?? body
        case .quote:
            let quoted = "“\(body)”"
            return attributionLine.map { "\(quoted)\n\n— \($0)" } ?? quoted
        case .verse:
            let ref = reference ?? ""
            guard let text = verseText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return ref }
            return "\(text)\n\n— \(ref) (ESV)"
        }
    }
}

public struct LordsDayFeed: Equatable, Sendable {
    public let cards: [LordsDayFeedCard]
    /// The card the feed opens at; nil when there are no cards.
    public let todayIndex: Int?
    /// The sermon's passage as OSIS, or nil when it's missing or doesn't parse.
    public let passageOsis: String?
    /// What the reader's intro and notes cards show (TKL-879).
    private let readerDay: (weekday: String, index: Int)
    private let keyPoint: String?

    /// The six house palettes the feed rotates through, in the approved prototype's order.
    public static let rotation: [QuoteCardPalette] = [.psalter, .vellum, .hymnal, .ironstone, .vespers, .cloister]

    /// Dark mode keeps dark fields and swaps light ones for their dark siblings.
    public static func palette(_ palette: QuoteCardPalette, dark: Bool) -> QuoteCardPalette {
        guard dark else { return palette }
        switch palette.name {
        case QuoteCardPalette.vellum.name: return .vespers
        case QuoteCardPalette.cloister.name: return .hymnal
        case QuoteCardPalette.ironstone.name, QuoteCardPalette.lectern.name: return .psalter
        default: return palette
        }
    }

    @MainActor public init?(store: LordsDayStore, today: Date, calendar: Calendar) throws {
        guard let note = try store.currentWeek(on: today, calendar: calendar) else { return nil }
        let cards = try store.cards(for: note)
        guard !cards.isEmpty else { return nil }
        self.init(note: note, cards: cards, today: today, calendar: calendar)
    }

    @MainActor public init(note: LordsDayNote, cards: [NoteCard], today: Date = Date(), calendar: Calendar = .current) {
        let todayIndex = todayCardIndex(serviceDate: note.serviceDate, today: today, cardCount: cards.count, calendar: calendar)
        self.todayIndex = cards.isEmpty ? nil : (todayIndex ?? 0)
        let passage = normalizedNoteField(note.passageRef)
        self.passageOsis = passage.flatMap(Self.osis(for:))
        // Day dots count Monday through Saturday whatever the card count; Sunday is day 1.
        let readingDays = Self.readerDaysInWeek
        let dayIndex = (readingDayIndex(note.serviceDate, today, readingDays, calendar) ?? 0) + 1
        self.readerDay = (Self.weekdays[calendar.component(.weekday, from: today) - 1], dayIndex)
        self.keyPoint = cards.lazy.filter { $0.kind == .keyPoint }.compactMap { normalizedNoteField($0.body) }.first
        let preacher = normalizedNoteField(note.preacher)
        let todayStart = calendar.startOfDay(for: today)
        self.cards = cards.enumerated().map { index, card in
            // Card 0 is Monday's: the day after the service.
            let date = index < 6 ? calendar.date(byAdding: .day, value: index + 1, to: calendar.startOfDay(for: note.serviceDate)) : nil
            let weekday = date.map { Self.weekdays[calendar.component(.weekday, from: $0) - 1] }
            let isToday = index == todayIndex
            let dayLabel: String? = if isToday {
                date.map { calendar.isDate($0, inSameDayAs: todayStart) } == true ? "Today · \(weekday!)" : "Today"
            } else {
                weekday
            }
            let attribution: String? = switch card.kind {
            case .keyPoint: passage.map { "From your notes on \($0)" } ?? "From your notes"
            case .quote:
                // Nil means "the preacher"; empty means the user cleared it in review (TKL-863).
                [card.attribution == nil ? preacher : normalizedNoteField(card.attribution), passage].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
            case .verse: nil
            }
            let ref = normalizedNoteField(card.verseRef)
            let osis = card.kind == .verse ? ref.flatMap(Self.osis(for:)) : nil
            return LordsDayFeedCard(
                id: card.id,
                kind: card.kind,
                body: card.kind == .verse ? "" : card.body,
                // An OSIS reference reads as a citation; anything else is shown as stored.
                reference: card.kind == .verse ? (osis == ref ? osis.map(parseOsisBibleReference) : ref) : nil,
                verseOsis: osis,
                palette: card.palette.flatMap(QuoteCardPalette.named) ?? Self.rotation[index % Self.rotation.count],
                dayLabel: dayLabel,
                isToday: isToday,
                attributionLine: attribution,
                passage: passage
            )
        }
    }

    /// The reader's day dots: one per day from Monday to Saturday (the TKL-838 design).
    static let readerDaysInWeek = 6

    /// The week's sermon text in the verse-by-verse reader ("Re-read the sermon text").
    public var sermonTextSource: ReaderSource? {
        passageOsis.map(readerSource(osis:))
    }

    /// A verse card opens the reader on that card's own reference; other cards open nothing.
    public func readerSource(for card: LordsDayFeedCard) -> ReaderSource? {
        guard card.kind == .verse else { return nil }
        return card.verseOsis.map(readerSource(osis:))
    }

    private func readerSource(osis: String) -> ReaderSource {
        .sermonText(
            passageOsis: osis, weekday: readerDay.weekday, dayIndex: readerDay.index,
            daysInWeek: Self.readerDaysInWeek, notesKeyPoint: keyPoint
        )
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.cards == b.cards && a.todayIndex == b.todayIndex && a.passageOsis == b.passageOsis
            && a.readerDay == b.readerDay && a.keyPoint == b.keyPoint
    }

    /// The app is English-only; the labels don't follow the calendar's locale.
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Accepts OSIS ("Rom.8.28") or a human citation ("Romans 8:28").
    static func osis(for reference: String) -> String? {
        if let first = reference.split(separator: ".").first, bibleBookByAbbreviation[String(first)] != nil,
           reference.range(of: #"^[1-3]?[A-Za-z]+\.\d+(\.\d+)?(-[1-3]?[A-Za-z]+\.\d+(\.\d+)?)?$"#, options: .regularExpression) != nil {
            return reference
        }
        return citationToOsis(reference)
    }
}

/// The today-card function, reachable from `LordsDayFeed`'s init where a local shadows its name.
private func readingDayIndex(_ serviceDate: Date, _ today: Date, _ count: Int, _ calendar: Calendar) -> Int? {
    todayCardIndex(serviceDate: serviceDate, today: today, cardCount: count, calendar: calendar)
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public struct VerseLead: Equatable, Sendable {
    public let lead: String
    public let rest: String
    public init(lead: String, rest: String) { self.lead = lead; self.rest = rest }
}

/// A verse card opens with a gilt lead-in instead of a drop cap (the TKL-836
/// prototype): its first three words, or fewer when a comma comes sooner.
/// Short verses get no lead-in.
public func verseLead(_ text: String) -> VerseLead {
    let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    guard words.count > 4 else { return VerseLead(lead: "", rest: words.joined(separator: " ")) }
    var count = 3
    if let comma = words.prefix(3).firstIndex(where: { $0.hasSuffix(",") || $0.hasSuffix(";") }) { count = comma + 1 }
    return VerseLead(lead: words.prefix(count).joined(separator: " "), rest: words.dropFirst(count).joined(separator: " "))
}
