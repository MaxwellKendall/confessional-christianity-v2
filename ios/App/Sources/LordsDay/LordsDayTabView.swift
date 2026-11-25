// The Lord's Day tab (pillar two, TKL-825). With cards for this week it is the
// week's card feed (TKL-862), read from the local store only. Without them it
// is the empty state from TKL-885's prototype (TKL-868 replaces it), with the
// way into photographing Sunday's notes (TKL-860). Finishing a capture opens
// the review of the drafted cards (TKL-863), which can be left and reopened
// from here until the week is kept. The archive is TKL-865.
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
                    LordsDayFeedView(feed: feed, allowsNetwork: isActive && scenePhase == .active)
                        .id(feedDay)
                        .overlay(alignment: .topTrailing) {
                            HStack(spacing: 8) {
                                if status.reviewable { reviewButton }
                                captureButton
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 40)
                        }
                } else {
                    emptyState
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
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

    /// Until the Sunday cover card (TKL-864) carries it, the way back to the camera.
    private var captureButton: some View {
        Button { capture = CaptureModel(context: context) } label: {
            Image(systemName: "camera")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(status.resumable ? "Continue Sunday's notes" : "Photograph Sunday's notes")
        .accessibilityIdentifier("lordsDay.capture")
    }

    private var reviewButton: some View {
        Button(action: openReview) {
            Label("Review cards", systemImage: "rectangle.stack")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityIdentifier("lordsDay.review")
    }

    private var emptyState: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pillar two")
                        .labelCaps(size: 10.5, tracking: 0.16)
                        .padding(.top, 16)
                    Text("The Lord's Day")
                        .font(.ccDisplay(25, semibold: true))
                        .foregroundStyle(.ccInk)
                        .padding(.top, 4)
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
                        if status.reviewable {
                            Button(action: openReview) {
                                Label("Review your cards", systemImage: "rectangle.stack")
                                    .font(.system(size: 15.5, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .foregroundStyle(Color.ccOnChapel)
                            }
                            .accessibilityIdentifier("lordsDay.review")
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

    private func openReview() {
        guard let id = status.pendingReviewNoteId,
              let note = try? LordsDayStore(context: context).note(id: id) else { return }
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

/// What the tab says about notes waiting to be finished or reviewed.
private struct CaptureStatus {
    var resumable = false
    /// Saved note id of the newest pending review (independent of service date / current week).
    var pendingReviewNoteId: UUID?
    var reviewable: Bool { pendingReviewNoteId != nil }
    var savedLine: String?

    init() {}

    @MainActor init(context: ModelContext, now: Date, calendar: Calendar) {
        resumable = (try? CaptureDraft.activeNoteId()) != nil
        let store = LordsDayStore(context: context)
        let pending = (try? store.pendingReviewNotes(activeSessionIds: ReviewModel.activeSessionIds))?.first
        pendingReviewNoteId = pending?.id
        guard let note = pending ?? (try? store.currentWeek(on: now, calendar: calendar)) else { return }
        let pages = CaptureDraft.savedPageCount(noteId: note.id)
        let what = pages > 0 ? "\(pages) page\(pages == 1 ? "" : "s")" : "typed notes"
        savedLine = "Saved: \(note.serviceDate.formatted(.dateTime.weekday(.wide).day().month())) · \(what)."
    }
}
