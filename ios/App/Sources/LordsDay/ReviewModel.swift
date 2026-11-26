// State for reviewing drafted cards (TKL-863). One model per note lives in
// `ReviewModel.sessions` while the app runs, so closing the review screen
// doesn't stop the cards arriving: reopening it finds the same model, still
// streaming. Every event and every edit is saved at once (LordsDayReview's
// file beside the note's photos), so a relaunch shows what had arrived and
// offers to read the rest. Only `finish()` writes NoteCards.
import Foundation
import SwiftData
import DomainKit

@MainActor @Observable
final class ReviewModel {
    let noteId: UUID
    private(set) var review: LordsDayReview
    private(set) var failure: CardsGeneratorError?
    private(set) var saveFailed = false
    let passage: String?
    let preacher: String?

    @ObservationIgnored private let note: LordsDayNote
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let root: URL
    @ObservationIgnored private let generator: CardsGenerator
    @ObservationIgnored private var task: Task<Void, Never>?

    /// The reviews of this launch, by note: what keeps a stream alive while its screen is closed.
    private static var sessions: [UUID: ReviewModel] = [:]

    static var activeSessionIds: Set<UUID> { Set(sessions.keys) }

    static func session(for note: LordsDayNote, context: ModelContext, generator: CardsGenerator = LiveCardsGenerator(),
                        root: URL = CaptureDraft.defaultRoot) -> ReviewModel {
        if let existing = sessions[note.id] { return existing }
        let model = ReviewModel(note: note, context: context, generator: generator, root: root)
        sessions[note.id] = model
        return model
    }

    /// Whether this note still has drafts to review, or has never been drafted.
    static func isPending(_ note: LordsDayNote, hasCards: Bool, root: URL = CaptureDraft.defaultRoot) -> Bool {
        if sessions[note.id] != nil { return true }
        if (try? LordsDayReview.load(noteId: note.id, root: root)) != nil { return true }
        guard !hasCards else { return false }
        let pages = (try? CaptureDraft(noteId: note.id, root: root))?.pages.count ?? 0
        return pages > 0 || normalizedNoteField(note.extractedText) != nil
    }

    private init(note: LordsDayNote, context: ModelContext, generator: CardsGenerator, root: URL) {
        self.note = note
        self.noteId = note.id
        self.context = context
        self.generator = generator
        self.root = root
        passage = normalizedNoteField(note.passageRef)
        preacher = normalizedNoteField(note.preacher)
        let pages = (try? CaptureDraft(noteId: note.id, root: root))?.pages.count ?? 0
        review = (try? LordsDayReview.load(noteId: note.id, root: root)) ?? LordsDayReview(noteId: note.id, pageCount: pages)
    }

    // MARK: Drafting

    /// Starts drafting the first time the review opens; a saved review waits for Retry.
    func startIfNeeded() {
        if review.phase == .notStarted { run() }
    }

    func retry() {
        guard review.canRetry || review.phase == .notStarted else { return }
        run()
    }

    private func run() {
        task?.cancel()
        failure = nil
        let pages = review.begin()
        guard !pages.isEmpty else {
            review.interrupt()
            save()
            return
        }
        let request: LordsDayCardsRequest
        do {
            request = try makeRequest(pages: pages)
        } catch {
            review.interrupt()
            failure = .failed
            save()
            return
        }
        save()
        let stream = generator.draft(request)
        task = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self else { return }
                    self.review.apply(event)
                    self.save()
                }
            } catch {
                if Task.isCancelled { return }
                self?.failure = (error as? CardsGeneratorError) ?? .failed
            }
            guard let self, !Task.isCancelled else { return }
            self.review.interrupt()
            self.save()
        }
    }

    /// Only the pages still unread: a retry doesn't redraft what's already here, and pages
    /// that already have partial cards request replay-only so they never append fresh wording.
    private func makeRequest(pages: [Int]) throws -> LordsDayCardsRequest {
        let draft = try CaptureDraft(noteId: note.id, root: root)
        let all = try draft.pageData()
        let validPages = all.isEmpty ? (pages.isEmpty ? [] : [pages[0]]) : pages.filter(all.indices.contains)
        let photos = all.isEmpty ? [] : validPages.map { all[$0] }
        return LordsDayCardsRequest(
            pages: photos,
            typedText: photos.isEmpty ? note.extractedText : nil,
            passage: note.passageRef,
            title: note.sermonTitle,
            preacher: note.preacher,
            replayOnlyPages: review.replayOnlyRequestIndices(for: validPages),
            expectedGenerationIds: review.expectedGenerationIds(for: validPages)
        )
    }

    // MARK: Changes

    /// True while that card is being drafted again.
    private(set) var redrafting: String?
    /// Set when a redraft came back with nothing usable, so the card you have stays.
    private(set) var redraftFailure: CardsGeneratorError?

    /// Whether this card can be asked for again: only while the page's transcription
    /// is in memory (it is not persisted, so a resumed review cannot redraft).
    func canRedraft(_ id: String) -> Bool {
        guard let card = review.card(id) else { return false }
        return review.transcription(forPage: card.page) != nil
    }

    /// Asks the model for another card in this one's place. On any failure the
    /// existing card is untouched (TKL-1053).
    func redraft(_ id: String) {
        guard redrafting == nil, let card = review.card(id),
              let text = review.transcription(forPage: card.page) else { return }
        redrafting = id
        redraftFailure = nil
        let request = LordsDayRedraftRequest(
            extractedText: text,
            kind: card.kind,
            avoid: review.cards.compactMap { $0.kind == .verse ? $0.verseRef : $0.words }.filter { !$0.isEmpty },
            passage: passage,
            preacher: preacher
        )
        Task { [weak self, generator] in
            do {
                let replacement = try await generator.redraft(request)
                guard let self else { return }
                try self.review.replace(id, with: replacement)
                self.save()
            } catch {
                self?.redraftFailure = (error as? CardsGeneratorError) ?? .failed
            }
            self?.redrafting = nil
        }
    }

    func dismissRedraftFailure() { redraftFailure = nil }

    func keep(_ id: String) { review.keep(id); save() }
    func remove(_ id: String) { review.remove(id); save() }
    func skipUnreadPages() { review.skipUnreadPages(); save() }
    func setKind(_ id: String, to kind: CardKind) throws { try review.setKind(id, to: kind); save() }
    func chooseVerse(_ id: String, osis: String) throws { try review.chooseVerse(id, osis: osis); save() }
    func edit(_ id: String, words: String, attribution: String?) throws {
        try review.editText(id, to: words)
        if let attribution { try review.editAttribution(id, to: attribution) }
        save()
    }

    /// Keeps the kept cards, in order, as this note's week. The photos stay on the device.
    func finish() throws {
        guard review.unhandledUnreadPages.isEmpty else { throw LordsDayReviewError.unreadPagesRemaining }
        guard review.canFinish else { throw LordsDayReviewError.nothingToKeep }
        let kept = review.keptCards()
        try LordsDayStore(context: context).keepCards(kept, for: note)
        LoopCounter.record(.sermonKept(cardCount: kept.count))
        task?.cancel()
        try? LordsDayReview.delete(noteId: noteId, root: root)
        Self.sessions[noteId] = nil
    }

    private func save() {
        do {
            try review.save(root: root)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }
}

extension ReviewModel: Identifiable {}
