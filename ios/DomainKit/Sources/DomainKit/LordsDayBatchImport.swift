import Foundation
import ImageIO

// Importing many sermons' photos at once (TKL-1107). The photos are read and
// drafted in chunks of up to six through the existing cards call, sent with no
// title, preacher or passage, so each page is read once. What each page's
// `sermon` event names, plus when the photo was taken, proposes which pages
// belong together (SermonGrouping); the person corrects that, then each group
// becomes its own note: its pages copied into that note's CaptureDraft and its
// drafted cards replayed into that note's saved LordsDayReview, so the existing
// review opens it as if it had just been drafted. Regrouping never calls the
// model again. Everything is written as it happens, so a killed app resumes
// with only the unread chunks and the groups not yet made into notes.

// MARK: Grouping

/// What grouping knows about one page: when it was photographed and what it named.
public struct GroupingPage: Equatable, Sendable {
    public let id: UUID
    public let takenAt: Date?
    public let sermon: SermonDetails?
    public init(id: UUID, takenAt: Date?, sermon: SermonDetails?) { self.id = id; self.takenAt = takenAt; self.sermon = sermon }
}

/// One proposed sermon. Its id becomes the note's id.
public struct SermonGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public fileprivate(set) var pageIds: [UUID]
    public init(id: UUID = UUID(), pageIds: [UUID]) { self.id = id; self.pageIds = pageIds }
}

/// Which pages make one sermon, and the person's corrections to that.
/// Pages always stay in batch order within a group.
public struct SermonGrouping: Codable, Equatable, Sendable {
    /// A gap this long between two photos means they were taken on different days.
    public static let defaultGap: TimeInterval = 6 * 3600

    public private(set) var order: [UUID]
    public private(set) var groups: [SermonGroup]

    public init(order: [UUID], groups: [SermonGroup]) {
        self.order = order
        self.groups = groups.filter { !$0.pageIds.isEmpty }
    }

    /// A page starts a new sermon when it names a title, passage or date different from the
    /// sermon so far, or when it was photographed more than `gap` after the page before.
    /// Otherwise (including a page that names nothing) it continues the sermon before it.
    /// Mirrored for the eval by `proposeGroups` in src/lib/lordsDay/grouping.ts.
    public static func propose(_ pages: [GroupingPage], gap: TimeInterval = defaultGap) -> SermonGrouping {
        var groups: [SermonGroup] = []
        var title: String?, passage: String?, date: String?
        var previous: GroupingPage?
        for page in pages {
            let pageTitle = comparable(page.sermon?.title)
            let pagePassage = comparable(page.sermon?.passage)
            let pageDate = normalizedNoteField(page.sermon?.serviceDate)
            func differs(_ a: String?, _ b: String?) -> Bool { a != nil && b != nil && a != b }
            let gapped = previous?.takenAt.flatMap { before in page.takenAt.map { abs($0.timeIntervalSince(before)) > gap } } ?? false
            if groups.isEmpty || gapped || differs(pageTitle, title) || differs(pagePassage, passage) || differs(pageDate, date) {
                groups.append(SermonGroup(pageIds: [page.id]))
                title = pageTitle; passage = pagePassage; date = pageDate
            } else {
                groups[groups.count - 1].pageIds.append(page.id)
                title = title ?? pageTitle; passage = passage ?? pagePassage; date = date ?? pageDate
            }
            previous = page
        }
        return SermonGrouping(order: pages.map(\.id), groups: groups)
    }

    /// Lowercased letters and digits only, so "Benediction." and "benediction" match.
    static func comparable(_ value: String?) -> String? {
        guard let value = normalizedNoteField(value) else { return nil }
        let kept = value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return kept.isEmpty ? nil : String(String.UnicodeScalarView(kept))
    }

    public func groupIndex(of page: UUID) -> Int? { groups.firstIndex { $0.pageIds.contains(page) } }

    /// Moves a page into another sermon, in its batch-order place there.
    public mutating func move(_ page: UUID, to group: UUID) {
        guard let from = groupIndex(of: page), let to = groups.firstIndex(where: { $0.id == group }), from != to else { return }
        groups[from].pageIds.removeAll { $0 == page }
        groups[to].pageIds.append(page)
        sortPages(in: to)
        groups.removeAll { $0.pageIds.isEmpty }
    }

    /// `page` and every page after it in the sermon become a new sermon right after it.
    public mutating func split(_ group: UUID, at page: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == group }),
              let cut = groups[index].pageIds.firstIndex(of: page), cut > 0 else { return }
        let tail = Array(groups[index].pageIds[cut...])
        groups[index].pageIds.removeSubrange(cut...)
        groups.insert(SermonGroup(pageIds: tail), at: index + 1)
    }

    /// `group`'s pages join `target`, which keeps its id; `group` goes away.
    public mutating func merge(_ group: UUID, into target: UUID) {
        guard group != target, let from = groups.firstIndex(where: { $0.id == group }),
              let to = groups.firstIndex(where: { $0.id == target }) else { return }
        groups[to].pageIds += groups[from].pageIds
        sortPages(in: to)
        groups.remove(at: from)
    }

    /// Sermons with more pages than one cards call takes: they must be split first.
    public var oversizedGroups: [UUID] { groups.filter { $0.pageIds.count > CaptureDraft.maxPages }.map(\.id) }
    public var canContinue: Bool { !groups.isEmpty && oversizedGroups.isEmpty }

    private mutating func sortPages(in index: Int) {
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        groups[index].pageIds.sort { (position[$0] ?? .max) < (position[$1] ?? .max) }
    }
}

// MARK: Dates

public struct ServiceDateResolution: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// The notes wrote the date.
        case notes
        /// The Sunday on or before the earliest photo.
        case photo
        /// Nothing said: the Sunday on or before today, shown as a guess.
        case guess
    }
    public let date: Date
    public let source: Source
    public init(date: Date, source: Source) { self.date = date; self.source = source }
    public var isGuess: Bool { source == .guess }
}

/// A sermon's service date: 1) a date read from the notes, 2) the Sunday on or before the
/// earliest photo, 3) the Sunday on or before today, flagged as a guess. A read or photo
/// date after today is a misreading (or a wrong camera clock) and is passed over.
/// Shared by batch import (TKL-1107) and single captures (TKL-1085).
public func resolveServiceDate(readDate: String?, photoDates: [Date?], now: Date, calendar: Calendar = .current) -> ServiceDateResolution {
    let today = calendar.startOfDay(for: now)
    if let raw = normalizedNoteField(readDate), let date = isoServiceDay(raw, calendar: calendar), date <= today {
        return ServiceDateResolution(date: calendar.startOfDay(for: date), source: .notes)
    }
    if let earliest = photoDates.compactMap({ $0 }).filter({ $0 <= now }).min() {
        return ServiceDateResolution(date: lastSunday(onOrBefore: earliest, calendar: calendar), source: .photo)
    }
    return ServiceDateResolution(date: lastSunday(onOrBefore: now, calendar: calendar), source: .guess)
}

/// When a photo was taken, from its EXIF `DateTimeOriginal` (local time, as the camera wrote it).
public func photoTakenAt(_ imageData: Data, calendar: Calendar = .current) -> Date? {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? exif?[kCGImagePropertyExifDateTimeDigitized] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
    return raw.flatMap { parseExifDate($0, calendar: calendar) }
}

/// `YYYY:MM:DD HH:MM:SS` in `calendar`'s time zone.
func parseExifDate(_ raw: String, calendar: Calendar) -> Date? {
    let numbers = raw.split(whereSeparator: { $0 == ":" || $0 == " " }).compactMap { Int($0) }
    guard numbers.count == 6 else { return nil }
    return calendar.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2],
                                              hour: numbers[3], minute: numbers[4], second: numbers[5]))
}

// MARK: Reading the batch

/// What the cards call returned for one page of the batch.
public struct BatchPageRead: Codable, Equatable, Sendable {
    public var extractedText: String?
    public var generationId: String?
    public var sermon: SermonDetails?
    /// The page's cards, `page` 0; renumbered when the page joins a note.
    public var cards: [DraftCardPayload]
    /// The call couldn't read this page; its sermon's review offers to try again.
    public var failed: Bool

    public static let failure = BatchPageRead(extractedText: nil, generationId: nil, sermon: nil, cards: [], failed: true)
}

public struct BatchPage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let takenAt: Date?
    public fileprivate(set) var read: BatchPageRead?
}

public enum BatchImportError: Error, Equatable { case chunkNotDone, unknownGroup }

/// Collects one chunk's stream. It counts only once `done` arrives, so a chunk cut off
/// mid-stream is read again whole.
public struct BatchChunkReader: Sendable {
    public let chunk: Range<Int>
    public private(set) var isDone = false
    private var reads: [Int: BatchPageRead] = [:]
    private var expected: [Int: Int] = [:]
    private var failed: Set<Int> = []

    public init(chunk: Range<Int>) { self.chunk = chunk }

    public mutating func apply(_ event: LordsDayCardsEvent) {
        guard !isDone else { return }
        switch event {
        case .started: break
        case .page(let i, let cardCount, let text, let generationId):
            guard (0..<chunk.count).contains(i) else { return }
            var read = reads[i] ?? BatchPageRead(extractedText: nil, generationId: nil, sermon: nil, cards: [], failed: false)
            read.extractedText = normalizedNoteField(text) ?? read.extractedText
            read.generationId = generationId ?? read.generationId
            reads[i] = read
            if let cardCount { expected[i] = max(0, cardCount) }
        case .sermon(let i, let details):
            guard !details.isEmpty, reads[i] != nil || (0..<chunk.count).contains(i) else { return }
            var read = reads[i] ?? BatchPageRead(extractedText: nil, generationId: nil, sermon: nil, cards: [], failed: false)
            read.sermon = details
            reads[i] = read
        case .card(var card):
            let i = card.page
            guard (0..<chunk.count).contains(i) else { return }
            card.page = 0
            var read = reads[i] ?? BatchPageRead(extractedText: nil, generationId: nil, sermon: nil, cards: [], failed: false)
            read.cards.append(card)
            reads[i] = read
        case .pageFailed(let i), .pageReplayUnavailable(let i):
            failed.insert(i)
        case .done(let failedPages):
            failed.formUnion(failedPages)
            isDone = true
        }
    }

    /// Each batch index's read, once done: a page the call never answered, or answered with
    /// fewer cards than it said, counts as failed.
    public func results() throws -> [Int: BatchPageRead] {
        guard isDone else { throw BatchImportError.chunkNotDone }
        var out: [Int: BatchPageRead] = [:]
        for (i, batchIndex) in chunk.enumerated() {
            if failed.contains(i) { out[batchIndex] = .failure; continue }
            guard let read = reads[i] else { out[batchIndex] = .failure; continue }
            if let want = expected[i], read.cards.count < want { out[batchIndex] = .failure; continue }
            out[batchIndex] = read
        }
        return out
    }
}

/// A group turned into a note's files: what the app's note record needs.
public struct BatchMaterializedGroup: Equatable, Sendable {
    public let noteId: UUID
    public let sermon: SermonDetails?
    public let date: ServiceDateResolution
}

/// The batch in progress: its photos (files, excluded from backup, like CaptureDraft's), what
/// each page read, and the grouping. `<root>/BatchImport/`; one batch at a time.
public final class BatchImportDraft {
    public static let maxPhotos = 30

    private struct State: Codable {
        var pages: [BatchPage] = []
        var grouping: SermonGrouping?
        var materialized: Set<UUID> = []
    }

    public let root: URL
    private let folder: URL
    private var state: State

    public var pages: [BatchPage] { state.pages }
    public var grouping: SermonGrouping? { state.grouping }

    public static func folder(root: URL) -> URL { root.appendingPathComponent("BatchImport", isDirectory: true) }

    /// Whether a batch was started and not finished (it resumes on reopening the import).
    public static func exists(root: URL = CaptureDraft.defaultRoot) -> Bool {
        FileManager.default.fileExists(atPath: folder(root: root).appendingPathComponent("batch.json").path)
    }

    public init(root: URL = CaptureDraft.defaultRoot) throws {
        self.root = root
        folder = Self.folder(root: root)
        try CaptureDraft.makeFolder(root)
        try CaptureDraft.makeFolder(folder)
        if let data = try? Data(contentsOf: folder.appendingPathComponent("batch.json")) {
            let decoder = JSONDecoder()
            state = try decoder.decode(State.self, from: data)
        } else {
            state = State()
        }
    }

    public var canAddPage: Bool { state.pages.count < Self.maxPhotos && state.grouping == nil }

    @discardableResult public func addPage(_ jpeg: Data, takenAt: Date?) throws -> UUID {
        guard canAddPage else { throw CaptureError.pageLimit }
        let page = BatchPage(id: UUID(), takenAt: takenAt, read: nil)
        try jpeg.write(to: url(for: page.id), options: .atomic)
        state.pages.append(page)
        try save()
        return page.id
    }

    public func removePage(_ id: UUID) throws {
        guard state.grouping == nil, let index = state.pages.firstIndex(where: { $0.id == id }) else { throw CaptureError.noSuchPage }
        state.pages.remove(at: index)
        try save()
        try? FileManager.default.removeItem(at: url(for: id))
    }

    public func data(for id: UUID) throws -> Data {
        guard state.pages.contains(where: { $0.id == id }) else { throw CaptureError.noSuchPage }
        return try Data(contentsOf: url(for: id))
    }

    // MARK: Reading

    /// The batch in runs of up to six pages: one cards call each.
    public var chunks: [Range<Int>] {
        stride(from: 0, to: state.pages.count, by: CaptureDraft.maxPages).map { $0..<min($0 + CaptureDraft.maxPages, state.pages.count) }
    }

    /// Chunks with a page not yet read (a chunk is recorded whole, so this is all or none of it).
    public var pendingChunks: [Range<Int>] { chunks.filter { chunk in chunk.contains { state.pages[$0].read == nil } } }
    public var allRead: Bool { !state.pages.isEmpty && pendingChunks.isEmpty }
    public var readCount: Int { state.pages.filter { $0.read != nil }.count }

    /// The chunk's photos with no title, preacher or passage: the notes say those, page by page.
    public func request(for chunk: Range<Int>) throws -> LordsDayCardsRequest {
        LordsDayCardsRequest(pages: try chunk.map { try data(for: state.pages[$0].id) }, typedText: nil, passage: nil, title: nil, preacher: nil)
    }

    public func record(_ reader: BatchChunkReader) throws {
        for (index, read) in try reader.results() where state.pages.indices.contains(index) {
            state.pages[index].read = read
        }
        try save()
    }

    // MARK: Grouping

    /// The proposed grouping, made once every page is read; the saved one after that.
    @discardableResult public func proposeGroups(gap: TimeInterval = SermonGrouping.defaultGap) throws -> SermonGrouping {
        if let grouping = state.grouping { return grouping }
        let grouping = SermonGrouping.propose(state.pages.map { GroupingPage(id: $0.id, takenAt: $0.takenAt, sermon: $0.read?.sermon) }, gap: gap)
        state.grouping = grouping
        try save()
        return grouping
    }

    public func setGrouping(_ grouping: SermonGrouping) throws {
        state.grouping = grouping
        try save()
    }

    /// What a group's pages named, merged in page order (first value per field).
    public func sermon(of group: SermonGroup) -> SermonDetails? {
        let merged = pages(of: group).compactMap { $0.read?.sermon }.reduce(SermonDetails(title: nil, preacher: nil, passage: nil, church: nil, serviceDate: nil)) {
            $0.filling(from: $1)
        }
        return merged.isEmpty ? nil : merged
    }

    public func date(of group: SermonGroup, now: Date, calendar: Calendar = .current) -> ServiceDateResolution {
        resolveServiceDate(readDate: sermon(of: group)?.serviceDate, photoDates: pages(of: group).map(\.takenAt), now: now, calendar: calendar)
    }

    public func pages(of group: SermonGroup) -> [BatchPage] {
        group.pageIds.compactMap { id in state.pages.first { $0.id == id } }
    }

    /// Groups not yet made into notes, in order.
    public var pendingGroups: [SermonGroup] { (state.grouping?.groups ?? []).filter { !state.materialized.contains($0.id) } }

    // MARK: One note per group

    /// Writes the group's pages into its note's CaptureDraft and its cards into the note's saved
    /// review, as a finished draft. Safe to repeat (a resumed batch writes the same files again).
    @discardableResult
    public func materialize(_ group: SermonGroup, now: Date, calendar: Calendar = .current) throws -> BatchMaterializedGroup {
        let pages = pages(of: group)
        let capture = try CaptureDraft(noteId: group.id, root: root)
        for existing in capture.pages { try capture.removePage(existing.id) }
        for page in pages { try capture.addPage(try data(for: page.id)) }

        var review = LordsDayReview(noteId: group.id, pageCount: pages.count)
        _ = review.begin()
        review.apply(.started(pages: pages.count))
        var failed: [Int] = []
        for (i, page) in pages.enumerated() {
            guard let read = page.read, !read.failed else {
                failed.append(i)
                review.apply(.pageFailed(i))
                continue
            }
            review.apply(.page(i, cardCount: read.cards.count, extractedText: read.extractedText, generationId: read.generationId))
            if let sermon = read.sermon { review.apply(.sermon(i, sermon)) }
            for var card in read.cards {
                card.page = i
                review.apply(.card(card))
            }
        }
        review.apply(.done(failedPages: failed))
        let date = date(of: group, now: now, calendar: calendar)
        review.setDateIsGuess(date.isGuess)
        try review.save(root: root)
        return BatchMaterializedGroup(noteId: group.id, sermon: sermon(of: group), date: date)
    }

    /// The group's note is saved: a resumed batch won't make it again.
    public func markMaterialized(_ groupId: UUID) throws {
        guard state.grouping?.groups.contains(where: { $0.id == groupId }) == true else { throw BatchImportError.unknownGroup }
        state.materialized.insert(groupId)
        try save()
    }

    /// Deletes the batch's own photos and state; notes already made keep their copies.
    public func discard() throws {
        state = State()
        try FileManager.default.removeItem(at: folder)
    }

    private func url(for id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).jpg") }

    private func save() throws {
        try JSONEncoder().encode(state).write(to: folder.appendingPathComponent("batch.json"), options: .atomic)
    }
}
