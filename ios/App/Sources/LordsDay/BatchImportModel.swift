// Importing many sermons' photos at once (TKL-1107, skeleton). Up to 30 photos
// are read in chunks of six through the same cards call a single capture uses
// (no title, preacher or passage sent), grouped into sermons from what each page
// names and when it was photographed, corrected on a plain grouping screen, then
// each group becomes its own LordsDayNote whose pending review the existing review
// screen opens. The batch lives in DomainKit's BatchImportDraft, written as it
// goes, so a killed app reopens the import where it stopped.
import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import DomainKit

@MainActor @Observable
final class BatchImportModel {
    enum Step: Equatable { case picking, reading, grouping, done }

    private(set) var step: Step = .picking
    private(set) var pages: [BatchPage] = []
    private(set) var thumbnails: [UUID: UIImage] = [:]
    private(set) var grouping: SermonGrouping?
    private(set) var edits: [UUID: SermonDetailsEdit] = [:]
    private(set) var retryingPage: UUID?
    private(set) var failure: CardsGeneratorError?
    private(set) var saveFailed = false
    /// The notes made from the groups, in order.
    private(set) var noteIds: [UUID] = []

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let root: URL
    @ObservationIgnored private let draft: BatchImportDraft
    @ObservationIgnored private let storeProvider: @MainActor () -> LordsDayStore
    @ObservationIgnored private let generator: CardsGenerator
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var task: Task<Void, Never>?

    var canAddPhotos: Bool { step == .picking && draft.canAddPage }
    var remainingPhotos: Int { BatchImportDraft.maxPhotos - pages.count }
    var readCount: Int { draft.readCount }

    /// Resumes the batch in progress, if there is one.
    init(
        context: ModelContext,
        storeProvider: (@MainActor () -> LordsDayStore)? = nil,
        generator: CardsGenerator,
        root: URL = CaptureDraft.defaultRoot,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.context = context
        self.root = root
        draft = try BatchImportDraft(root: root)
        self.storeProvider = storeProvider ?? { LordsDayStore(context: context) }
        self.generator = generator
        self.now = now
        pages = draft.pages
        for page in pages { loadThumbnail(page.id) }
        if let saved = draft.grouping {
            for group in saved.groups { edits[group.id] = draft.editedDetails(for: group.id) }
            grouping = saved
            step = .grouping
        }
    }

    // MARK: Photos

    func add(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard draft.canAddPage, let data = try? await item.loadTransferable(type: Data.self) else { continue }
            add(data)
        }
    }

    /// One photo: its EXIF time is kept for grouping and dating; the upload copy is resized.
    func add(_ original: Data, takenAt: Date? = nil) {
        guard let image = UIImage(data: original), let jpeg = CaptureModel.jpegForUpload(image) else { saveFailed = true; return }
        do {
            let id = try draft.addPage(jpeg, takenAt: takenAt ?? photoTakenAt(original))
            thumbnails[id] = CaptureModel.thumbnail(image)
            pages = draft.pages
        } catch {
            saveFailed = true
        }
    }

    func removePage(_ id: UUID) {
        guard retryingPage == nil else { return }
        do {
            try draft.removePage(id)
            thumbnails[id] = nil
            pages = draft.pages
            grouping = draft.grouping
            if pages.isEmpty { step = .picking }
        } catch { saveFailed = true }
    }

    // MARK: Reading

    /// Reads every chunk not yet read, one cards call each, then proposes the sermons.
    func read() {
        guard step != .reading, !pages.isEmpty else { return }
        task?.cancel()
        failure = nil
        step = .reading
        task = Task { [weak self] in
            guard let self else { return }
            for chunk in self.draft.pendingChunks {
                do {
                    var reader = BatchChunkReader(chunk: chunk)
                    for try await event in self.generator.draft(try self.draft.request(for: chunk)) {
                        reader.apply(event)
                    }
                    try self.draft.record(reader)
                    self.pages = self.draft.pages
                } catch {
                    if Task.isCancelled { return }
                    self.failure = (error as? CardsGeneratorError) ?? .failed
                    self.step = .picking
                    return
                }
            }
            do {
                self.grouping = try self.draft.proposeGroups()
                self.step = .grouping
            } catch {
                self.saveFailed = true
                self.step = .picking
            }
        }
    }

    func retry(_ page: UUID) {
        guard step == .grouping, retryingPage == nil,
              let index = pages.firstIndex(where: { $0.id == page && $0.read?.failed == true }) else { return }
        retryingPage = page
        task = Task { [weak self] in
            guard let self else { return }
            defer { retryingPage = nil }
            do {
                let chunk = index..<(index + 1)
                var reader = BatchChunkReader(chunk: chunk)
                for try await event in generator.draft(try draft.request(for: chunk)) {
                    reader.apply(event)
                }
                try Task.checkCancellation()
                try draft.record(reader)
                pages = draft.pages
            } catch {
                // The original failed page stays visible and can be retried again.
            }
        }
    }

    // MARK: Grouping

    func sermon(of group: SermonGroup) -> SermonDetails? { draft.sermon(of: group) }
    func date(of group: SermonGroup) -> ServiceDateResolution { draft.date(of: group, now: now()) }

    func details(of group: SermonGroup) -> SermonDetailsEdit {
        if let edit = edits[group.id] { return edit }
        let read = sermon(of: group)
        return SermonDetailsEdit(title: read?.title, preacher: read?.preacher, passage: read?.passage,
                                 church: read?.church, serviceDate: date(of: group).date)
    }

    func edit(_ group: SermonGroup, details: SermonDetailsEdit) throws {
        try draft.setDetails(details, for: group.id)
        edits[group.id] = details
    }

    func move(_ page: UUID, to group: UUID) { change { $0.move(page, to: group) } }
    func moveToNewGroup(_ page: UUID) { change { $0.moveToNewGroup(page) } }
    func split(_ group: UUID, at page: UUID) { change { $0.split(group, at: page) } }
    func merge(_ group: UUID, into target: UUID) { change { $0.merge(group, into: target) } }

    private func change(_ body: (inout SermonGrouping) -> Void) {
        guard var grouping else { return }
        body(&grouping)
        self.grouping = grouping
        do { try draft.setGrouping(grouping) } catch { saveFailed = true }
    }

    // MARK: Finishing

    /// Each group becomes its own note with its own pending review. A group already made
    /// (the app was killed part way) is not made twice.
    func finish() throws {
        guard let grouping, grouping.canContinue else { return }
        let store = storeProvider()
        for group in draft.pendingGroups {
            let made = try draft.materialize(group, now: now())
            if try store.note(id: made.noteId) == nil {
                let note = LordsDayNote(id: made.noteId, serviceDate: made.date.date)
                note.sermonTitle = made.sermon?.title
                note.preacher = made.sermon?.preacher
                note.passageRef = made.sermon?.passage
                note.church = made.sermon?.church
                try store.save(note)
            }
            try draft.markMaterialized(group.id)
        }
        noteIds = grouping.groups.map(\.id)
        try draft.discard()
        step = .done
    }

    func note(for id: UUID) -> LordsDayNote? {
        try? storeProvider().note(id: id)
    }

    func details(for id: UUID) -> LordsDayReview? {
        try? LordsDayReview.load(noteId: id, root: root)
    }

    func review(for id: UUID) -> ReviewModel? {
        guard let note = note(for: id) else { return nil }
        return ReviewModel.session(for: note, context: context, storeProvider: storeProvider, generator: generator, root: root)
    }

    /// Throws the batch away (the photos and what was read); notes already made stay.
    func discard() {
        task?.cancel()
        try? draft.discard()
    }

    private func loadThumbnail(_ id: UUID) {
        if let data = try? draft.data(for: id), let image = UIImage(data: data) { thumbnails[id] = CaptureModel.thumbnail(image) }
    }
}

extension BatchImportModel: Identifiable {}
