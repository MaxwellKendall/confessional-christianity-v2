// State for photographing Sunday's notes (TKL-860). Pages go to CaptureDraft
// (files on the device, never the note record); the note's optional fields and
// typed notes go to LordsDayNote through SwiftData. Every change is written at
// once, so killing the app mid-capture loses nothing: reopening the capture
// resumes the note CaptureDraft marks active.
import SwiftUI
import SwiftData
import UIKit
import DomainKit

@MainActor @Observable
final class CaptureModel {
    enum SaveState: Equatable { case idle, saved, failed }

    private(set) var pages: [CapturePage] = []
    private(set) var thumbnails: [UUID: UIImage] = [:]
    private(set) var saveState: SaveState = .idle
    /// The page the next shutter or photo replaces.
    var retakeTarget: UUID?

    var serviceDate: Date { didSet { if oldValue != serviceDate { write { $0.serviceDate = self.serviceDate } } } }
    var passage: String { didSet { if oldValue != passage { write { $0.passageRef = normalizedNoteField(self.passage) } } } }
    var title: String { didSet { if oldValue != title { write { $0.sermonTitle = normalizedNoteField(self.title) } } } }
    var preacher: String { didSet { if oldValue != preacher { write { $0.preacher = normalizedNoteField(self.preacher) } } } }
    var typedText: String { didSet { if oldValue != typedText { write { $0.extractedText = normalizedNoteField(self.typedText) } } } }

    private let context: ModelContext
    private let storeProvider: @MainActor () -> LordsDayStore
    private let root: URL
    private let draft: CaptureDraft
    private let note: LordsDayNote
    /// False until the note has something in it, so an untouched capture leaves no empty note behind.
    private var isPersisted: Bool

    var noteId: UUID { note.id }
    var canFinish: Bool { CaptureContent(pageCount: pages.count, typedText: typedText).canFinish }
    var canAddPage: Bool { retakeTarget != nil || draft.canAddPage }
    var hasContent: Bool { canFinish || isPersisted }

    /// Resumes the capture in progress, if the app was closed during one; otherwise starts a new note.
    init(
        context: ModelContext,
        storeProvider: (@MainActor () -> LordsDayStore)? = nil,
        root: URL = CaptureDraft.defaultRoot,
        now: Date = Date()
    ) {
        self.context = context
        self.storeProvider = storeProvider ?? { LordsDayStore(context: context) }
        self.root = root
        let activeId = try? CaptureDraft.activeNoteId(root: root)
        let resumed = activeId.flatMap { id in
            try? context.fetch(FetchDescriptor<LordsDayNote>(predicate: #Predicate { $0.id == id })).first
        }
        let note = resumed ?? LordsDayNote(serviceDate: Self.lastSunday(onOrBefore: now))
        self.note = note
        isPersisted = resumed != nil
        // Pages written before the note itself was saved still belong to it.
        draft = (try? CaptureDraft(noteId: activeId ?? note.id, root: root)) ?? (try! CaptureDraft(noteId: note.id, root: FileManager.default.temporaryDirectory))
        if resumed == nil, let activeId { note.id = activeId }
        serviceDate = note.serviceDate
        passage = note.passageRef ?? ""
        title = note.sermonTitle ?? ""
        preacher = note.preacher ?? ""
        typedText = note.extractedText ?? ""
        pages = draft.pages
        for page in pages { loadThumbnail(page.id) }
        if !pages.isEmpty { saveState = .saved }
    }

    static func lastSunday(onOrBefore date: Date, calendar: Calendar = .current) -> Date {
        DomainKit.lastSunday(onOrBefore: date, calendar: calendar)
    }

    // MARK: Pages

    func addPhoto(_ image: UIImage) {
        guard let jpeg = Self.jpegForUpload(image) else { saveState = .failed; return }
        do {
            markActive()
            if let target = retakeTarget {
                try draft.retakePage(target, with: jpeg)
                retakeTarget = nil
                thumbnails[target] = Self.thumbnail(image)
            } else {
                let id = try draft.addPage(jpeg)
                thumbnails[id] = Self.thumbnail(image)
            }
            pages = draft.pages
            persistNote()
        } catch {
            saveState = .failed
        }
    }

    func removePage(_ id: UUID) {
        do {
            try draft.removePage(id)
            if retakeTarget == id { retakeTarget = nil }
            thumbnails[id] = nil
            pages = draft.pages
            persistNote()
        } catch {
            saveState = .failed
        }
    }

    // MARK: Finish or cancel

    /// The note is kept with its pages; the pages wait on the device for the generator call (TKL-863).
    func finish() {
        persistNote()
        try? CaptureDraft.setActive(nil, root: root)
    }

    /// Deletes the note and its photos.
    func discard() {
        try? draft.discard()
        try? CaptureDraft.setActive(nil, root: root)
        if isPersisted {
            try? storeProvider().removeNote(note)
        }
    }

    /// What the generator call sends: the photos, or the typed notes when there are none.
    func cardsRequest() throws -> LordsDayCardsRequest {
        LordsDayCardsRequest(pages: try draft.pageData(), typedText: typedText, passage: passage, title: title, preacher: preacher)
    }

    // MARK: Saving

    private func write(_ change: (LordsDayNote) -> Void) {
        markActive()
        persistNote(change)
    }

    private func markActive() {
        try? CaptureDraft.setActive(note.id, root: root)
    }

    private func persistNote(_ change: (LordsDayNote) -> Void = { _ in }) {
        do {
            isPersisted = true
            try storeProvider().update(note, change)
            saveState = .saved
        } catch {
            saveState = .failed
        }
    }

    private func loadThumbnail(_ id: UUID) {
        if let data = try? draft.data(for: id), let image = UIImage(data: data) { thumbnails[id] = Self.thumbnail(image) }
    }

    // MARK: Images

    /// ~1600 px on the long side, as the endpoint asks, capped under 450 KB per page
    /// so even six dense pages stay under the endpoint's 4 MB base64 JSON body limit.
    static func jpegForUpload(_ image: UIImage, longSide: CGFloat = 1600, maxBytes: Int = 450_000) -> Data? {
        let scaled = resized(image, longSide: longSide)
        for quality in [0.72, 0.6, 0.5, 0.4] {
            guard let data = scaled.jpegData(compressionQuality: quality) else { return nil }
            if data.count <= maxBytes || quality == 0.4 { return data }
        }
        return scaled.jpegData(compressionQuality: 0.4)
    }

    static func thumbnail(_ image: UIImage) -> UIImage { resized(image, longSide: 180) }

    private static func resized(_ image: UIImage, longSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, longSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
}

extension CaptureModel: Identifiable {}
