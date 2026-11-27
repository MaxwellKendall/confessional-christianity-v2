// The sermon journal, pass 1 (TKL-944; approved design TKL-951 revision 2,
// TKL-971). Every kept Lord's Day, read from the local store only: swipe
// between the Time and Scripture lenses, drill in to set a filter the other
// lens keeps, search every stored word, and open one sermon. The Topic lens,
// fair copy and Insights are TKL-1058.
import SwiftUI
import SwiftData
import DomainKit
import os

/// Pushed from the Lord's Day tab's header.
enum JournalRoute: Hashable { case journal }

enum JournalTimeZoom: String, CaseIterable {
    case years, months, sundays
    var label: String { rawValue.capitalized }
}

@MainActor @Observable final class JournalModel {
    let journal: LordsDayJournal
    var query = "" { didSet { if query != oldValue { recompute() } } }
    var filter = JournalFilter() { didSet { if filter != oldValue { recompute() } } }
    var lens: JournalLens = .time
    var timeZoom: JournalTimeZoom = .years
    private(set) var hits: [JournalHit] = []
    /// What the time lens lights: the search and the Scripture filter, any year.
    private(set) var timeHits: [JournalHit] = []
    /// What the canon lights: the search and the time filter, any book.
    private(set) var scriptureHits: [JournalHit] = []
    private(set) var yearRows: [JournalYearRow] = []
    private(set) var chapterCounts = JournalChapterCounts(preached: [:], cited: [:])

    init(journal: LordsDayJournal) {
        self.journal = journal
        recompute()
    }

    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var isFiltered: Bool { !filter.isEmpty || hasQuery }

    private func recompute() {
        hits = journal.search(query, filter: filter)
        timeHits = journal.search(query, filter: filter, ignoring: .time)
        scriptureHits = journal.search(query, filter: filter, ignoring: .scripture)
        yearRows = journal.yearRows(hits: Set(timeHits.map(\.id)))
        chapterCounts = journal.chapterCounts(scriptureHits)
    }

    func pickYear(_ year: Int) {
        filter.year = year; filter.month = nil; timeZoom = .months
    }
    func pickMonth(_ month: Int) {
        filter.month = month; timeZoom = .sundays
    }
    func zoom(_ zoom: JournalTimeZoom) {
        if zoom != .sundays { filter.month = nil }
        if zoom == .years { filter.year = nil }
        timeZoom = zoom
    }
    func clearTime() { filter.year = nil; filter.month = nil; timeZoom = .years }
    func pickBook(_ book: Int) { filter.book = book; filter.chapter = nil }
    func pickChapter(_ chapter: Int) { filter.chapter = filter.chapter == chapter ? nil : chapter }
    func clearScripture() { filter.book = nil; filter.chapter = nil }
    func clearAll() { filter = JournalFilter(); query = ""; timeZoom = .years }

    /// "2026 × Revelation × “grace”", for the one-sermon bar.
    var whereLabel: String {
        var parts: [String] = []
        if filter.hasTime { parts.append(filter.timeLabel) }
        if filter.hasScripture { parts.append(filter.scriptureLabel) }
        if hasQuery { parts.append("“\(query.trimmingCharacters(in: .whitespaces))”") }
        return parts.isEmpty ? "All Lord's Days" : parts.joined(separator: " × ")
    }
}

/// One sermon opened from the journal, with the list prev and next walk.
struct JournalOpenedSermon: Identifiable, Hashable {
    let id: UUID
    let list: [UUID]
    let whereLabel: String
}

struct JournalView: View {
    var onCapture: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: JournalModel?
    @State private var opened: JournalOpenedSermon?
    @State private var loadStarted = Date()
    private static let log = Logger(subsystem: "com.confessionalchristianity.app", category: "journal")

    var body: some View {
        Group {
            if let model {
                if model.journal.isEmpty {
                    JournalEmptyView(onBack: { dismiss() }, onCapture: onCapture)
                } else {
                    JournalContent(model: model, onBack: { dismiss() }, open: open, onGridReady: gridReady)
                }
            } else {
                Color.ccPaper.ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $opened) { sermon in
            if let model {
                JournalSermonView(journal: model.journal, list: sermon.list, whereLabel: sermon.whereLabel,
                                  query: model.query, current: sermon.id)
            }
        }
        .task {
            guard model == nil else { return }
            loadStarted = Date()
            let journal = Self.load(context: context)
            model = JournalModel(journal: journal)
            #if DEBUG
            applyScreenshotHooks()
            #endif
        }
    }

    private func open(_ id: UUID) {
        guard let model else { return }
        var list = model.hits.map(\.id)
        if !list.contains(id) { list = model.journal.entries.map(\.id) }
        opened = JournalOpenedSermon(id: id, list: list, whereLabel: model.whereLabel)
    }

    private func gridReady() {
        let ms = Int(Date().timeIntervalSince(loadStarted) * 1000)
        let count = model?.journal.entries.count ?? 0
        Self.log.notice("year grid ready: \(count, privacy: .public) Lord's Days in \(ms, privacy: .public) ms")
    }

    private static func load(context: ModelContext) -> LordsDayJournal {
        #if DEBUG
        // Screenshot hook: `-JournalFixture empty|1|50|500` shows that many synthetic Lord's Days.
        if let spec = UserDefaults.standard.string(forKey: "JournalFixture") {
            let count = Int(spec) ?? 0
            return LordsDayJournal(entries: JournalFixture.synthetic(count: count, endingOn: Date()))
        }
        #endif
        return (try? LordsDayJournal(store: LordsDayStore(context: context))) ?? LordsDayJournal(entries: [])
    }

    #if DEBUG
    /// Screenshot hooks: `-JournalLens scripture`, `-JournalQuery grace`, `-JournalYear 2026`,
    /// `-JournalMonth 3`, `-JournalBook Rev`, `-JournalChapter 2`, `-JournalZoom months|sundays`,
    /// `-JournalOpenSermon first`.
    private func applyScreenshotHooks() {
        guard let model else { return }
        let d = UserDefaults.standard
        if let q = d.string(forKey: "JournalQuery") { model.query = q }
        if d.integer(forKey: "JournalYear") > 0 { model.pickYear(d.integer(forKey: "JournalYear")) }
        if d.integer(forKey: "JournalMonth") > 0 { model.pickMonth(d.integer(forKey: "JournalMonth")) }
        if let osis = d.string(forKey: "JournalBook"), let book = BIBLE_BOOKS.firstIndex(where: { $0.osis == osis }) {
            model.pickBook(book)
            if d.integer(forKey: "JournalChapter") > 0 { model.pickChapter(d.integer(forKey: "JournalChapter")) }
        }
        if let zoom = d.string(forKey: "JournalZoom").flatMap(JournalTimeZoom.init(rawValue:)) { model.timeZoom = zoom }
        if let lens = d.string(forKey: "JournalLens").flatMap(JournalLens.init(rawValue:)) { model.lens = lens }
        if d.string(forKey: "JournalOpenSermon") == "first", let first = model.hits.first { open(first.id) }
    }
    #endif
}

// MARK: - The journal

private struct JournalContent: View {
    @Bindable var model: JournalModel
    let onBack: () -> Void
    let open: (UUID) -> Void
    let onGridReady: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            chips
            lensTabs
            TabView(selection: $model.lens) {
                ScrollView {
                    JournalTimeLens(model: model, open: open, onGridReady: onGridReady)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                }
                .tag(JournalLens.time)
                ScrollView {
                    JournalScriptureLens(model: model, open: open)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                }
                .tag(JournalLens.scripture)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color.ccPaper.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ccChapel)
                    .frame(width: 32, height: 44, alignment: .leading)
            }
            .accessibilityLabel("This week")
            .accessibilityIdentifier("journal.back")
            VStack(alignment: .leading, spacing: 2) {
                Text("The Lord's Day").chapelCaps()
                Text("Journal").font(.ccTitle).foregroundStyle(Color.ccInk)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                let all = model.journal.entries.count
                if model.isFiltered {
                    Text("**\(model.hits.count)** of \(all) Lord's Days")
                } else {
                    Text("**\(all)** Lord's Day\(all == 1 ? "" : "s")")
                }
                Text("\(model.hits.reduce(0) { $0 + $1.entry.cards.count }.formatted()) cards")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Color.ccInk2)
            .accessibilityIdentifier("journal.count")
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ccInk3)
            TextField("Search every word you've captured", text: $model.query)
                .font(.system(size: 15.5))
                .foregroundStyle(Color.ccInk)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("journal.search")
            if model.hasQuery {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ccInk3)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.ccFill, in: RoundedRectangle(cornerRadius: ChapelRadius.control, style: .continuous))
        .padding(.horizontal, ChapelSpace.gutter)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(model.filter.timeLabel, on: model.filter.hasTime, id: "time", lens: .time, clear: model.clearTime)
                chip(model.filter.scriptureLabel, on: model.filter.hasScripture, id: "scripture", lens: .scripture, clear: model.clearScripture)
                if model.isFiltered {
                    Button("Clear all") { withAnimation(.snappy) { model.clearAll() } }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.ccInk2)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Color.ccFill, in: Capsule())
                        .accessibilityIdentifier("journal.clearAll")
                }
            }
            .padding(.horizontal, ChapelSpace.gutter)
        }
        .padding(.top, 10)
    }

    private func chip(_ label: String, on: Bool, id: String, lens: JournalLens, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button { withAnimation(.snappy) { model.lens = lens } } label: {
                Text(label).font(.system(size: 13.5, weight: .semibold))
            }
            if on {
                Button { withAnimation(.snappy) { clear() } } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).opacity(0.85)
                }
                .accessibilityLabel("Clear \(label)")
                .accessibilityIdentifier("journal.chip.\(id).clear")
            }
        }
        .foregroundStyle(on ? Color.ccOnChapel : Color.ccInk)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(on ? Color.ccChapel : Color.ccFill, in: Capsule())
        .accessibilityIdentifier("journal.chip.\(id)")
    }

    private var lensTabs: some View {
        HStack(spacing: 0) {
            ForEach(JournalLens.allCases, id: \.self) { lens in
                Button { withAnimation(.snappy) { model.lens = lens } } label: {
                    Text(lens.label)
                        .font(.ccDisplay(12))
                        .tracking(12 * 0.08)
                        .textCase(.uppercase)
                        .foregroundStyle(model.lens == lens ? Color.ccInk : Color.ccInk3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .overlay(alignment: .bottom) {
                            if model.lens == lens {
                                Capsule().fill(Color.ccChapel).frame(height: 2).padding(.horizontal, 40).offset(y: 1)
                            }
                        }
                }
                .accessibilityIdentifier("journal.lens.\(lens.rawValue)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.ccLine).frame(height: 1) }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 10)
    }
}

// MARK: - Time lens

private struct JournalTimeLens: View {
    let model: JournalModel
    let open: (UUID) -> Void
    let onGridReady: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            crumbs
            switch model.timeZoom {
            case .years: years
            case .months: months
            case .sundays: JournalCoverGrid(hits: model.hits, grouped: true, query: model.query, open: open, clear: model.clearAll)
            }
        }
    }

    private var crumbs: some View {
        HStack(spacing: 6) {
            Button("All") { withAnimation(.snappy) { model.zoom(.years) } }.foregroundStyle(Color.ccChapel).fontWeight(.semibold)
            if let year = model.filter.year {
                Text("›")
                Button("\(String(year))") { withAnimation(.snappy) { model.zoom(.months) } }.foregroundStyle(Color.ccChapel).fontWeight(.semibold)
            }
            if let month = model.filter.month { Text("› \(JournalFilter.monthNames[month - 1])") }
            Spacer()
            HStack(spacing: 0) {
                ForEach(JournalTimeZoom.allCases, id: \.self) { zoom in
                    Button(zoom.label) { withAnimation(.snappy) { model.zoom(zoom) } }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.timeZoom == zoom ? Color.ccInk : Color.ccInk2)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background {
                            if model.timeZoom == zoom {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.ccSurface).shadow(color: .ccShadow, radius: 1.5, y: 1)
                            }
                        }
                        .accessibilityIdentifier("journal.zoom.\(zoom.rawValue)")
                }
            }
            .padding(2)
            .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.ccInk2)
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var years: some View {
        Text("Each square is a Lord's Day; filled where you kept notes\(model.isFiltered ? ", dark where it matches" : ""). Tap a year.")
            .font(.system(size: 12)).foregroundStyle(Color.ccInk3)
            .padding(.horizontal, ChapelSpace.gutter).padding(.bottom, 8)
        JournalMonthAxis(labels: ["Jan", "Apr", "Jul", "Oct", "Dec"])
        LazyVStack(spacing: 0) {
            ForEach(model.yearRows) { row in
                Button { withAnimation(.snappy) { model.pickYear(row.year) } } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(row.year)).font(.ccDisplay(13, semibold: true)).foregroundStyle(Color.ccInk)
                            Text("\(row.hitCount)").font(.system(size: 10.5)).foregroundStyle(Color.ccInk3)
                        }
                        .frame(width: 38, alignment: .leading)
                        JournalYearCells(cells: row.cells)
                    }
                    .padding(.horizontal, ChapelSpace.gutter)
                    .padding(.vertical, 5)
                    .background(model.filter.year == row.year ? Color.ccFill : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.year): \(row.hitCount) Lord's Days")
                .accessibilityIdentifier("journal.year.\(row.year)")
            }
        }
        .onAppear(perform: onGridReady)
        if model.journal.entries.count == 1 {
            Text("One Lord's Day so far. Every Sunday you keep lights a square; ten years of notes fit on this screen.")
                .font(.system(size: 12)).foregroundStyle(Color.ccInk3)
                .padding(.horizontal, ChapelSpace.gutter).padding(.top, 12)
        }
    }

    @ViewBuilder private var months: some View {
        if let year = model.filter.year {
            let hitIds = Set(model.timeHits.map(\.id))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(1...12, id: \.self) { month in
                    let sundays = model.journal.entries.filter { $0.year == year && $0.month == month }.reversed()
                    let matching = sundays.filter { hitIds.contains($0.id) }.count
                    Button { withAnimation(.snappy) { model.pickMonth(month) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(JournalFilter.monthNames[month - 1].prefix(3)).font(.ccDisplay(12, semibold: true)).foregroundStyle(Color.ccInk)
                                Spacer()
                                if matching > 0 { Text("\(matching)").font(.system(size: 11)).foregroundStyle(Color.ccInk3) }
                            }
                            HStack(spacing: 3) {
                                ForEach(Array(sundays)) { entry in
                                    JournalSundayTile(entry: entry, dimmed: !hitIds.contains(entry.id))
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.ccLine))
                        .opacity(sundays.isEmpty ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(sundays.isEmpty)
                    .accessibilityIdentifier("journal.month.\(month)")
                }
            }
            .padding(.horizontal, ChapelSpace.gutter)
            JournalSection(title: "\(String(year)) · \(model.hits.count) Lord's Day\(model.hits.count == 1 ? "" : "s")")
            JournalCoverGrid(hits: model.hits, grouped: true, query: model.query, open: open, clear: model.clearAll)
        } else {
            Text("Lord's Days kept each month, one row per year. Tap a year.")
                .font(.system(size: 12)).foregroundStyle(Color.ccInk3)
                .padding(.horizontal, ChapelSpace.gutter).padding(.bottom, 8)
            let hitIds = Set(model.timeHits.map(\.id))
            ForEach(model.journal.years, id: \.self) { year in
                Button { withAnimation(.snappy) { model.pickYear(year) } } label: {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text(String(year)).font(.ccDisplay(12.5, semibold: true)).foregroundStyle(Color.ccInk).frame(width: 38, alignment: .leading)
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(model.journal.monthCounts(year: year, hits: hitIds).enumerated()), id: \.offset) { _, n in
                                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                                    .fill(n > 0 ? Color.ccChapel : Color.ccLine)
                                    .frame(height: n > 0 ? CGFloat(min(n, 5)) * 6 : 1)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 30, alignment: .bottom)
                    }
                    .padding(.horizontal, ChapelSpace.gutter).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            JournalMonthAxis(labels: ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"])
        }
    }
}

/// A year's 53 weeks, drawn in one pass so ten years of rows stay cheap.
private struct JournalYearCells: View {
    let cells: [JournalCell]
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 1
            let width = (size.width - gap * CGFloat(cells.count - 1)) / CGFloat(cells.count)
            for (i, cell) in cells.enumerated() {
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: 0, width: width, height: size.height)
                let color: Color = switch cell {
                case .none: .ccFill
                case .kept: .ccLine
                case .hit: .ccChapel
                }
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
            }
        }
        .frame(height: 13)
        .accessibilityHidden(true)
    }
}

private struct JournalMonthAxis: View {
    let labels: [String]
    var body: some View {
        HStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Text(label)
                if i < labels.count - 1 { Spacer(minLength: 0) }
            }
        }
        .font(.ccDisplay(9.5))
        .tracking(0.6)
        .foregroundStyle(Color.ccInk3)
        .padding(.leading, ChapelSpace.gutter + 46)
        .padding(.trailing, ChapelSpace.gutter)
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }
}

/// A Sunday in a month box: the week's first card colour, the book's initial.
private struct JournalSundayTile: View {
    let entry: JournalEntry
    let dimmed: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = LordsDayFeed.palette(entry.cards.first?.palette(at: 0) ?? LordsDayFeed.rotation[0], dark: scheme == .dark)
        Text(entry.bookIndex.map { String(BIBLE_BOOKS[$0].name.first { $0.isLetter } ?? " ") } ?? "·")
            .font(.ccDisplay(9))
            .foregroundStyle(Color(hex: palette.ink))
            .frame(width: 18, height: 24)
            .background(Color(hex: palette.field), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .opacity(dimmed ? 0.18 : 1)
    }
}

// MARK: - Scripture lens

private struct JournalScriptureLens: View {
    let model: JournalModel
    let open: (UUID) -> Void

    var body: some View {
        if let book = model.filter.book {
            bookView(book)
        } else {
            canon
        }
    }

    @ViewBuilder private var canon: some View {
        let counts = model.chapterCounts
        HStack {
            Text("The canon, chapter by chapter")
            Spacer()
            Text("\(counts.preached.count) of 1,189 preached").font(.system(size: 12)).foregroundStyle(Color.ccInk3)
        }
        .font(.system(size: 13)).foregroundStyle(Color.ccInk2)
        .padding(.horizontal, ChapelSpace.gutter).padding(.bottom, 10)
        HStack(spacing: 12) {
            legend(Color.ccFill, "never")
            legend(Color.ccChapel.opacity(0.28), "cited")
            legend(Color.ccChapel.opacity(0.55), "preached")
            legend(Color.ccChapel, "often")
        }
        .font(.system(size: 11)).foregroundStyle(Color.ccInk3)
        .padding(.horizontal, ChapelSpace.gutter).padding(.bottom, 10)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(BIBLE_BOOKS.enumerated()), id: \.offset) { index, book in
                if index == 0 || index == 39 {
                    Text(index == 0 ? "Old Testament" : "New Testament")
                        .font(.ccDisplay(10)).tracking(1.6).textCase(.uppercase).foregroundStyle(Color.ccInk3)
                        .padding(.top, 10).padding(.bottom, 4)
                }
                let levels = (1...book.chapters).map { level(ChapterKey(book: index, chapter: $0), counts) }
                let any = levels.contains { $0 > 0 }
                Button { withAnimation(.snappy) { model.pickBook(index) } } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.shortName(book))
                            .font(.system(size: 11))
                            .foregroundStyle(any ? Color.ccInk2 : Color.ccInk3)
                            .frame(width: 44, alignment: .leading)
                        JournalChapterCells(levels: levels)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(book.name)\(any ? "" : ", never preached")")
                .accessibilityIdentifier("journal.book.\(book.osis)")
            }
        }
        .padding(.horizontal, ChapelSpace.gutter)
    }

    @ViewBuilder private func bookView(_ index: Int) -> some View {
        let book = BIBLE_BOOKS[index]
        let counts = model.chapterCounts
        HStack(spacing: 6) {
            Button("Canon") { withAnimation(.snappy) { model.clearScripture() } }.foregroundStyle(Color.ccChapel).fontWeight(.semibold)
            Text("›")
            if let chapter = model.filter.chapter {
                Button(book.name) { withAnimation(.snappy) { model.filter.chapter = nil } }.foregroundStyle(Color.ccChapel).fontWeight(.semibold)
                Text("› \(chapter)")
            } else {
                Text(book.name)
            }
            Spacer()
        }
        .font(.system(size: 13)).foregroundStyle(Color.ccInk2)
        .padding(.horizontal, ChapelSpace.gutter).padding(.bottom, 10)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 8), spacing: 5) {
            ForEach(1...book.chapters, id: \.self) { chapter in
                let key = ChapterKey(book: index, chapter: chapter)
                let preached = counts.preached[key] ?? 0
                let lvl = level(key, counts)
                Button { withAnimation(.snappy) { model.pickChapter(chapter) } } label: {
                    VStack(spacing: 0) {
                        Text("\(chapter)").font(.system(size: 12.5, weight: .semibold))
                        if preached > 0 { Text("\(preached)×").font(.system(size: 9.5)).opacity(0.85) }
                    }
                    .foregroundStyle(lvl >= 3 ? Color.ccOnChapel : lvl > 0 ? Color.ccInk : Color.ccInk3)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(chapterFill(lvl), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if model.filter.chapter == chapter {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.ccGilt, lineWidth: 2).padding(-2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journal.chapter.\(chapter)")
            }
        }
        .padding(.horizontal, ChapelSpace.gutter)
        let shown = model.hits
        JournalSection(title: "Preached from \(model.filter.scriptureLabel) · \(shown.count)")
        JournalCoverGrid(hits: shown, grouped: false, query: model.query, open: open, clear: model.clearAll)
        let cited = model.scriptureHits.filter { hit in
            hit.entry.bookIndex != index && hit.entry.citedChapters.contains { $0.book == index && (model.filter.chapter == nil || $0.chapter == model.filter.chapter) }
        }
        if !cited.isEmpty {
            JournalSection(title: "Cited in \(cited.count) other sermon\(cited.count == 1 ? "" : "s")")
            JournalCoverGrid(hits: Array(cited.prefix(40)), grouped: false, query: model.query, open: open, clear: model.clearAll)
        }
    }

    /// 0 never, 1 cited, 2 preached once, 3 twice, 4 three times or more.
    private func level(_ key: ChapterKey, _ counts: JournalChapterCounts) -> Int {
        if let n = counts.preached[key] { return min(n, 3) + 1 }
        return counts.cited[key] != nil ? 1 : 0
    }

    private func chapterFill(_ level: Int) -> Color {
        switch level {
        case 0: .ccFill
        case 1: .ccChapel.opacity(0.22)
        case 2: .ccChapel.opacity(0.5)
        default: .ccChapel
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }

    /// "1Sam" reads "1 Sam".
    static func shortName(_ book: BibleBook) -> String {
        guard let first = book.osis.first, first.isNumber else { return book.osis }
        return "\(first) \(book.osis.dropFirst())"
    }
}

/// A book's chapters as small cells, wrapping, drawn in one pass.
private struct JournalChapterCells: View {
    let levels: [Int]
    private static let perLine = 40
    var body: some View {
        let lines = (levels.count + Self.perLine - 1) / Self.perLine
        Canvas { context, size in
            let gap: CGFloat = 1
            let width = min(6, (size.width - gap * CGFloat(Self.perLine - 1)) / CGFloat(Self.perLine))
            for (i, level) in levels.enumerated() {
                let rect = CGRect(x: CGFloat(i % Self.perLine) * (width + gap), y: CGFloat(i / Self.perLine) * 10, width: width, height: 9)
                let color: Color = switch level {
                case 0: .ccFill
                case 1: .ccChapel.opacity(0.28)
                case 2: .ccChapel.opacity(0.55)
                case 3: .ccChapel.opacity(0.8)
                default: .ccChapel
                }
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .frame(height: CGFloat(lines) * 10 - 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Covers

private struct JournalSection: View {
    let title: String
    var body: some View {
        Text(title).chapelCaps()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ChapelSpace.gutter)
            .padding(.top, 18).padding(.bottom, 8)
    }
}

/// Lord's Days as small summary covers, two across, newest first.
private struct JournalCoverGrid: View {
    let hits: [JournalHit]
    let grouped: Bool
    let query: String
    let open: (UUID) -> Void
    let clear: () -> Void

    var body: some View {
        if hits.isEmpty {
            HStack(spacing: 4) {
                Text("Nothing matches.")
                Button("Clear filters", action: clear).fontWeight(.semibold).foregroundStyle(Color.ccChapel)
                    .accessibilityIdentifier("journal.clearFilters")
            }
            .font(.system(size: 12)).foregroundStyle(Color.ccInk3)
            .padding(.horizontal, ChapelSpace.gutter).padding(.top, 8)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
                if grouped {
                    ForEach(groups, id: \.key) { group in
                        Section {
                            ForEach(group.hits) { cover($0) }
                        } header: {
                            Text(group.key).chapelCaps()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 10).padding(.bottom, 2)
                        }
                    }
                } else {
                    ForEach(hits) { cover($0) }
                }
            }
            .padding(.horizontal, ChapelSpace.gutter)
        }
    }

    private var groups: [(key: String, hits: [JournalHit])] {
        var out: [(key: String, hits: [JournalHit])] = []
        for hit in hits {
            let key = "\(JournalFilter.monthNames[hit.entry.month - 1]) \(hit.entry.year)"
            if out.last?.key == key { out[out.count - 1].hits.append(hit) } else { out.append((key, [hit])) }
        }
        return out
    }

    private func cover(_ hit: JournalHit) -> some View {
        JournalCover(hit: hit, query: query) { open(hit.id) }
    }
}

private struct JournalCover: View {
    let hit: JournalHit
    let query: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let entry = hit.entry
        let palette = LordsDayFeed.palette(entry.cards.first?.palette(at: 0) ?? LordsDayFeed.rotation[0], dark: scheme == .dark)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.serviceDate.journalDate).font(.ccDisplay(9.5)).tracking(1.1).textCase(.uppercase).foregroundStyle(Color.ccInk3)
                // Named by the sermon (TKL-1061): title, else passage, else the date.
                let heading = SermonHeading(title: entry.title, passage: entry.passage, preacher: entry.preacher, date: entry.serviceDate.journalDate)
                Text(highlighted(heading.headline)).font(.ccDisplay(13.5, semibold: true)).foregroundStyle(Color.ccInk).lineLimit(2)
                if let byline = heading.byline {
                    Text(highlighted(byline)).font(.ccBody(13.5)).foregroundStyle(Color.ccInk2).lineLimit(2)
                }
                if let snippet = hit.snippet {
                    Text(snippetText(snippet)).font(.ccBody(12)).foregroundStyle(Color.ccInk2).lineLimit(3)
                }
                Spacer(minLength: 0)
                Text("\(entry.cards.count) card\(entry.cards.count == 1 ? "" : "s")").font(.system(size: 10.5)).foregroundStyle(Color.ccInk3)
            }
            .multilineTextAlignment(.leading)
            .padding(.leading, 15).padding(.trailing, 11).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(Color.ccSurface)
            .overlay(alignment: .leading) { Rectangle().fill(Color(hex: palette.field)).frame(width: 4) }
            .clipShape(RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous).strokeBorder(Color.ccLine))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journal.cover")
    }

    private func highlighted(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        for word in query.split(whereSeparator: \.isWhitespace) {
            var start = out.startIndex
            while start < out.endIndex, let range = out[start...].range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive]) {
                out[range].backgroundColor = Color.ccGilt.opacity(0.25)
                start = range.upperBound
            }
        }
        return out
    }

    private func snippetText(_ s: JournalSnippet) -> AttributedString {
        var match = AttributedString(s.match)
        match.backgroundColor = Color.ccGilt.opacity(0.25)
        return AttributedString((s.leadingEllipsis ? "…" : "") + s.before) + match + AttributedString(s.after + (s.trailingEllipsis ? "…" : ""))
    }
}

extension Date {
    /// "22 Nov 2026", as the prototype writes dates.
    var journalDate: String {
        formatted(.dateTime.day().month(.abbreviated).year())
    }
}

// MARK: - Empty

private struct JournalEmptyView: View {
    let onBack: () -> Void
    let onCapture: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ccChapel)
                            .frame(width: 32, height: 44, alignment: .leading)
                    }
                    .accessibilityLabel("This week")
                    .accessibilityIdentifier("journal.back")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Lord's Day").chapelCaps()
                        Text("Journal").font(.ccTitle).foregroundStyle(Color.ccInk)
                    }
                }
                Text("Every Lord's Day you keep is kept here, in one journal. Ten years of notes fit on one screen.")
                    .chapelReading()
                    .foregroundStyle(Color.ccInk2)
                VStack(spacing: 0) {
                    ForEach([2026, 2025, 2024], id: \.self) { year in
                        HStack(spacing: 8) {
                            Text(String(year)).font(.ccDisplay(13, semibold: true)).foregroundStyle(Color.ccInk).frame(width: 38, alignment: .leading)
                            JournalYearCells(cells: Array(repeating: .none, count: 53))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .opacity(0.5)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("What it will show you").chapelCaps()
                    Text("Browse by **time** and by **Scripture**: every Sunday on a year grid, and the canon lit where you've heard it preached. Search every word you've kept, and open any sermon again.")
                        .font(.system(size: 13)).lineSpacing(3).foregroundStyle(Color.ccInk2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: ChapelRadius.sheet, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ChapelRadius.sheet, style: .continuous).strokeBorder(Color.ccLine))
                Button(action: onCapture) {
                    Label("Photograph Sunday's notes", systemImage: "camera")
                        .font(.system(size: 15.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: ChapelRadius.control, style: .continuous))
                        .foregroundStyle(Color.ccOnChapel)
                }
                .accessibilityIdentifier("journal.capture")
            }
            .padding(.horizontal, ChapelSpace.gutter)
            .padding(.bottom, 120)
        }
        .background(Color.ccPaper.ignoresSafeArea())
    }
}
