// The Lord's Day tab (pillar two, TKL-825). With cards for this week it is the
// week's card feed (TKL-862), read from the local store only. Without them it
// is the empty state from TKL-885's prototype (TKL-868 replaces it), with the
// way into photographing Sunday's notes (TKL-860). Finishing a capture opens
// the review of the drafted cards (TKL-863), which can be left and reopened
// from here until the week is kept. The header opens the sermon journal of
// every kept Lord's Day (TKL-944); back returns to the feed where it was.
import SwiftUI
import SwiftData
import DomainKit

struct LordsDayTabView: View {
    @Binding var path: NavigationPath
    /// Every tab stays mounted from launch; only an on-screen feed may fetch verse text.
    var isActive = true
    @Binding var startsCapture: Bool
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @State private var capture: CaptureModel?
    @State private var status = CaptureStatus()
    @State private var feed: LordsDayFeed?
    @State private var review: ReviewModel?
    /// Set by the capture's Done, so its cover's dismissal opens the review.
    @State private var reviewAfterCapture: UUID?
    @State private var feedDay: Date?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let feed {
                    LordsDayFeedView(feed: feed, allowsNetwork: isActive && scenePhase == .active) { palette in
                        feedHeaderControls(palette: palette)
                    }
                    .id(feedDay)
                } else {
                    emptyState
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
            .navigationDestination(for: JournalRoute.self) { _ in
                JournalView(onCapture: {
                    path = NavigationPath()
                    capture = CaptureModel(context: context)
                })
            }
        }
        .tint(.ccInk)
        .fullScreenCover(item: $capture, onDismiss: afterCapture) { model in
            CaptureView(model: model, onClose: { capture = nil }, onFinish: {
                reviewAfterCapture = model.noteId
                capture = nil
            })
        }
        .fullScreenCover(item: $review, onDismiss: refresh) { model in
            ReviewView(model: model, onClose: { review = nil }, onFinish: { review = nil })
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
            capture = CaptureModel(context: context)
            startsCapture = false
        }
        .onChange(of: isActive) { _, active in
            if active { refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refresh()
        }
    }

    @ViewBuilder
    private func feedHeaderControls(palette: QuoteCardPalette) -> some View {
        let ink = Color(hex: palette.ink)
        HStack(spacing: 8) {
            if status.reviewable { reviewButton(ink: ink) }
            journalButton(ink: ink)
            captureButton(ink: ink)
        }
    }

    /// The sermon journal: every kept Lord's Day (TKL-944).
    private func journalButton(ink: Color) -> some View {
        Button { path.append(JournalRoute.journal) } label: {
            LordsDayHeaderCameraLabel(ink: ink, systemImage: "book.closed")
        }
        .accessibilityLabel("Journal")
        .accessibilityIdentifier("lordsDay.journal")
    }

    /// Until the Sunday cover card (TKL-864) carries it, the way back to the camera.
    private func captureButton(ink: Color) -> some View {
        Button { capture = CaptureModel(context: context) } label: {
            LordsDayHeaderCameraLabel(ink: ink)
        }
        .accessibilityLabel(status.resumable ? "Continue Sunday's notes" : "Photograph Sunday's notes")
        .accessibilityIdentifier("lordsDay.capture")
    }

    @ViewBuilder
    private func reviewButton(ink: Color) -> some View {
        if status.pendingReviews.count == 1, let only = status.pendingReviews.first {
            Button { openReview(noteId: only.id) } label: {
                LordsDayHeaderPillLabel(title: "Review cards", systemImage: "rectangle.stack", ink: ink)
            }
            .accessibilityIdentifier("lordsDay.review")
        } else {
            Menu {
                ForEach(status.pendingReviews) { item in
                    Button(item.label) { openReview(noteId: item.id) }
                        .accessibilityIdentifier("lordsDay.review.\(item.id.uuidString)")
                }
            } label: {
                LordsDayHeaderPillLabel(title: "Review cards (\(status.pendingReviews.count))", systemImage: "rectangle.stack", ink: ink)
            }
            .accessibilityIdentifier("lordsDay.review")
        }
    }

    private var emptyState: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Pillar two")
                                .labelCaps(size: 10.5, tracking: 0.16)
                                .padding(.top, 16)
                            Text("The Lord's Day")
                                .font(.ccDisplay(25, semibold: true))
                                .foregroundStyle(.ccInk)
                                .padding(.top, 4)
                        }
                        Spacer()
                        Button { path.append(JournalRoute.journal) } label: {
                            Label("Journal", systemImage: "book.closed")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ccChapel)
                        }
                        .accessibilityIdentifier("lordsDay.journal")
                    }
                    .padding(.bottom, 16)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Keep Sunday's sermon")
                            .font(.ccDisplay(19, semibold: true))
                            .foregroundStyle(.ccInk)
                            .padding(.bottom, 8)
                        Text("Take notes on Sunday's sermon and photograph them after church. The app turns them into a card for each day of the week: a key point, a verse, a quote, and a prayer for the Sunday ahead.")
                            .font(.ccBody(15.5))
                            .lineSpacing(3)
                            .foregroundStyle(.ccInk2)
                            .fixedSize(horizontal: false, vertical: true)
                        if status.pendingReviews.count == 1, let only = status.pendingReviews.first {
                            Button { openReview(noteId: only.id) } label: {
                                Label("Review your cards", systemImage: "rectangle.stack")
                                    .font(.system(size: 15.5, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .foregroundStyle(Color.ccOnChapel)
                            }
                            .accessibilityIdentifier("lordsDay.review")
                            .padding(.top, 16)
                        } else if status.pendingReviews.count > 1 {
                            VStack(spacing: 8) {
                                ForEach(status.pendingReviews) { item in
                                    Button { openReview(noteId: item.id) } label: {
                                        Label("Review · \(item.label)", systemImage: "rectangle.stack")
                                            .font(.system(size: 15, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .foregroundStyle(Color.ccOnChapel)
                                    }
                                    .accessibilityIdentifier("lordsDay.review.\(item.id.uuidString)")
                                }
                            }
                            .padding(.top, 16)
                        }
                        Button { capture = CaptureModel(context: context) } label: {
                            Label(status.resumable ? "Continue Sunday's notes" : "Photograph Sunday's notes", systemImage: "camera")
                                .font(.system(size: 15.5, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(Color.ccOnChapel)
                        }
                        .accessibilityIdentifier("lordsDay.capture")
                        .padding(.top, 16)
                        if let saved = status.savedLine {
                            Text(saved)
                                .font(.system(size: 13))
                                .foregroundStyle(.ccInk3)
                                .padding(.top, 10)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ccHairline, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .frame(maxWidth: 704)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ccCard)
    }

    private func makeGenerator() -> LiveCardsGenerator {
        LiveCardsGenerator(accessToken: { [auth] forceRefresh in
            await auth.accessToken(forceRefresh: forceRefresh)
        })
    }

    private func afterCapture() {
        refresh()
        guard let id = reviewAfterCapture else { return }
        reviewAfterCapture = nil
        if let note = try? LordsDayStore(context: context).note(id: id) {
            review = ReviewModel.session(for: note, context: context, generator: makeGenerator())
        }
    }

    private func openReview(noteId: UUID) {
        guard let note = try? LordsDayStore(context: context).note(id: noteId) else { return }
        review = ReviewModel.session(for: note, context: context, generator: makeGenerator())
    }

    private func refresh() {
        let now = Date()
        let calendar = Calendar.current
        status = CaptureStatus(context: context, now: now, calendar: calendar)
        feed = try? LordsDayFeed(store: LordsDayStore(context: context), today: now, calendar: calendar)
        feedDay = calendar.startOfDay(for: now)
    }
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
            let passage = normalizedNoteField(note.passageRef)
            let label = passage.map { "\($0) · \(date)" } ?? date
            return PendingReviewItem(id: note.id, label: label)
        }
        guard let note = pending.first ?? (try? store.currentWeek(on: now, calendar: calendar)) else { return }
        let pages = CaptureDraft.savedPageCount(noteId: note.id)
        let what = pages > 0 ? "\(pages) page\(pages == 1 ? "" : "s")" : "typed notes"
        savedLine = "Saved: \(note.serviceDate.formatted(.dateTime.weekday(.wide).day().month())) · \(what)."
    }
}
