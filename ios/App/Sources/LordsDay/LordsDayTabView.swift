// The Lord's Day tab (pillar two, TKL-825). Its landing page (TKL-1063, design
// TKL-1062) shows this week's sermon as a stack that opens the reel of every
// kept sermon, the earlier Lord's Days, and each state of the week: Sunday
// before notes, notes being read (drafting carries on while you're away; a
// tap opens the review, TKL-863), drafts waiting for review, no sermon, before
// a first Sunday, offline and a failed read. All of it comes from the local
// store. The header opens the sermon journal (TKL-944) and the camera (TKL-860).
import SwiftUI
import SwiftData
import DomainKit

struct LordsDayTabView: View {
    @Binding var path: NavigationPath
    /// Every tab stays mounted from launch; only an on-screen reel may fetch verse text.
    var isActive = true
    @Binding var startsCapture: Bool
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @State private var capture: CaptureModel?
    @State private var capturesTyping = false
    @State private var status = CaptureStatus()
    @State private var reel = LordsDayReel(testSermonPageCounts: [])
    @State private var review: ReviewModel?
    /// The newest note waiting on drafting or review, observed for the landing page.
    @State private var pending: ReviewModel?
    @State private var reelStart: ReelOpening?
    @State private var memory = LordsDayStackMemory()
    @State private var offline = false
    @State private var now = Date()
    /// Set by the capture's Done, so its cover's dismissal starts reading the notes.
    @State private var draftAfterCapture: UUID?
    @Environment(\.scenePhase) private var scenePhase

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack(path: $path) {
            landing
                .toolbar(.hidden, for: .navigationBar)
                .appDestinations(path: $path)
                .navigationDestination(for: JournalRoute.self) { _ in
                    JournalView(onCapture: {
                        path = NavigationPath()
                        startCapture()
                    })
                }
        }
        .tint(.ccInk)
        .fullScreenCover(item: $capture, onDismiss: afterCapture) { model in
            CaptureView(model: model, onClose: { capture = nil }, onFinish: {
                draftAfterCapture = model.noteId
                capture = nil
            }, startsTyping: capturesTyping)
        }
        .fullScreenCover(item: $review, onDismiss: refresh) { model in
            ReviewView(model: model, onClose: { review = nil }, onFinish: { review = nil })
        }
        .fullScreenCover(item: $reelStart, onDismiss: refresh) { opening in
            LordsDayReelView(reel: reel, start: opening.position, allowsNetwork: scenePhase == .active,
                             onPage: remember, onClose: { reelStart = nil })
        }
        .onAppear(perform: refresh)
        #if DEBUG
        .task {
            // Screenshot hook: `-OpenJournal YES` pushes the journal on launch.
            if UserDefaults.standard.bool(forKey: "OpenJournal"), path.isEmpty { path.append(JournalRoute.journal) }
        }
        #endif
        .onChange(of: startsCapture, initial: true) { _, requested in
            guard requested else { return }
            startCapture()
            startsCapture = false
        }
        .onChange(of: isActive) { _, active in
            if active { refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onChange(of: pending?.review.phase) { _, phase in
            // Drafting finished while the landing page was showing it.
            if phase != .drafting { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refresh()
        }
    }

    private var isSunday: Bool { calendar.component(.weekday, from: now) == 1 }

    private var landing: some View {
        let draft = pending.map(Self.draft(from:))
        let reading = pending?.review.isDrafting ?? false
        let failed = pending.map { model in
            !model.review.isDrafting && (model.failure != nil || !model.review.failedPages.isEmpty)
                && !model.review.unhandledUnreadPages.isEmpty
        } ?? false
        let thisWeek = reel.thisWeek(today: now, calendar: calendar)
        let kind = LordsDayLanding.kind(isSunday: isSunday, hasThisWeeksSermon: thisWeek != nil,
                                        hasAnyKeptSermon: !reel.sermons.isEmpty, isReadingNotes: reading,
                                        readFailed: failed, hasPendingReview: pending != nil || status.reviewable)
        return LordsDayLandingView(
            reel: reel, kind: kind, today: now, isSunday: isSunday, offline: offline,
            stackPage: thisWeek.map(memory.page(for:)) ?? 0, draft: draft, calendar: calendar,
            onOpenReel: { reelStart = ReelOpening(position: $0) },
            onJournal: { path.append(JournalRoute.journal) },
            onCapture: { startCapture() },
            onType: { startCapture(typing: true) },
            onOpenReview: openPendingReview,
            onRetry: { pending?.retry() }
        )
    }

    static func draft(from model: ReviewModel) -> LandingDraft {
        let review = model.review
        let kept = review.cards.filter(\.kept)
        return LandingDraft(
            title: model.title, passage: model.passage, preacher: model.preacher,
            dateCaps: model.serviceDate.formatted(.dateTime.month(.abbreviated).day()).uppercased(),
            pageCount: review.pageCount, pagesRead: review.readPages.count, progress: review.progress,
            arrived: kept.map { $0.kind == .verse ? ($0.verseRef.map(Self.readable) ?? "") : $0.words }.filter { !$0.isEmpty },
            cardCount: kept.count, failedPage: review.failedPages.min() ?? review.unhandledUnreadPages.first
        )
    }

    private static func readable(_ ref: String) -> String {
        ref.contains(".") ? parseOsisBibleReference(ref) : ref
    }

    private func startCapture(typing: Bool = false) {
        capturesTyping = typing
        capture = CaptureModel(context: context)
    }

    private func remember(_ sermon: ReelSermon, _ page: Int) {
        memory.remember(page: page, for: sermon.id)
        UserDefaults.standard.set(memory.stored, forKey: Self.memoryKey)
    }

    private static let memoryKey = "LordsDayStackMemory"

    private func makeGenerator() -> LiveCardsGenerator {
        LiveCardsGenerator(accessToken: { [auth] forceRefresh in
            await auth.accessToken(forceRefresh: forceRefresh)
        })
    }

    /// Finishing a capture starts reading the notes; the landing page shows it, and a tap opens the review.
    private func afterCapture() {
        refresh()
        guard let id = draftAfterCapture else { return }
        draftAfterCapture = nil
        guard let note = try? LordsDayStore(context: context).note(id: id) else { return }
        let model = ReviewModel.session(for: note, context: context, generator: makeGenerator())
        model.startIfNeeded()
        pending = model
    }

    private func openPendingReview() {
        if let pending { review = pending; return }
        guard let first = status.pendingReviews.first else { return }
        openReview(noteId: first.id)
    }

    private func openReview(noteId: UUID) {
        guard let note = try? LordsDayStore(context: context).note(id: noteId) else { return }
        review = ReviewModel.session(for: note, context: context, generator: makeGenerator())
    }

    private func refresh() {
        now = Date()
        status = CaptureStatus(context: context, now: now, calendar: calendar)
        let store = LordsDayStore(context: context)
        reel = (try? LordsDayReel(store: store, today: now, calendar: calendar)) ?? LordsDayReel(testSermonPageCounts: [])
        memory = LordsDayStackMemory(stored: UserDefaults.standard.dictionary(forKey: Self.memoryKey) as? [String: Int] ?? [:])
        if let first = status.pendingReviews.first, let note = try? store.note(id: first.id) {
            pending = ReviewModel.session(for: note, context: context, generator: makeGenerator())
        } else {
            pending = nil
        }
        Task { offline = !(await NetworkConnectivity.shared.isOnline()) }
    }
}

/// Where the reel opens.
private struct ReelOpening: Identifiable {
    let id = UUID()
    let position: ReelPosition
}

private struct PendingReviewItem: Identifiable, Equatable {
    let id: UUID
    let label: String
}

/// What the tab says about notes waiting to be finished or reviewed.
private struct CaptureStatus {
    var resumable = false
    /// All pending reviews, newest first, each addressable by its saved note id so
    /// a newer review (even one with zero cards) never hides an older saved review.
    var pendingReviews: [PendingReviewItem] = []
    var reviewable: Bool { !pendingReviews.isEmpty }
    var savedLine: String?

    init() {}

    @MainActor init(context: ModelContext, now: Date, calendar: Calendar) {
        resumable = (try? CaptureDraft.activeNoteId()) != nil
        let store = LordsDayStore(context: context)
        let pending = (try? store.pendingReviewNotes(activeSessionIds: ReviewModel.activeSessionIds)) ?? []
        pendingReviews = pending.map { note in
            let date = note.serviceDate.formatted(.dateTime.month(.abbreviated).day())
            let heading = SermonHeading(note: note, date: date)
            let label = heading.hasSermonName ? "\(heading.headline) · \(date)" : date
            return PendingReviewItem(id: note.id, label: label)
        }
        guard let note = pending.first ?? (try? store.currentWeek(on: now, calendar: calendar)) else { return }
        let pages = CaptureDraft.savedPageCount(noteId: note.id)
        let what = pages > 0 ? "\(pages) page\(pages == 1 ? "" : "s")" : "typed notes"
        let date = note.serviceDate.formatted(.dateTime.weekday(.wide).day().month())
        let heading = SermonHeading(note: note, date: date)
        savedLine = "Saved: \(heading.hasSermonName ? "\(heading.headline), \(date)" : date) · \(what)."
    }
}
