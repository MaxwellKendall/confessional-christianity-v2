// The Lord's Day tab (pillar two, TKL-825). With cards for this week it is the
// week's card feed (TKL-862), read from the local store only. Without them it
// is the empty state from TKL-885's prototype (TKL-868 replaces it), with the
// way into photographing Sunday's notes (TKL-860). The archive is TKL-865.
import SwiftUI
import SwiftData
import DomainKit

struct LordsDayTabView: View {
    @Binding var path: NavigationPath
    /// Every tab stays mounted from launch; only an on-screen feed may fetch verse text.
    var isActive = true
    @Environment(\.modelContext) private var context
    @State private var capture: CaptureModel?
    @State private var status = CaptureStatus()
    @State private var feed: LordsDayFeed?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let feed {
                    LordsDayFeedView(feed: feed, allowsNetwork: isActive)
                        .overlay(alignment: .topTrailing) { captureButton }
                } else {
                    emptyState
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
        }
        .tint(.ccInk)
        .fullScreenCover(item: $capture, onDismiss: refresh) { model in
            CaptureView(model: model, onClose: { capture = nil })
        }
        .onAppear(perform: refresh)
    }

    /// Until the Sunday cover card (TKL-864) carries it, the way back to the camera.
    private var captureButton: some View {
        Button { capture = CaptureModel(context: context) } label: {
            Image(systemName: "camera")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.trailing, 16)
        .padding(.top, 40)
        .accessibilityLabel(status.resumable ? "Continue Sunday's notes" : "Photograph Sunday's notes")
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
                        Button { capture = CaptureModel(context: context) } label: {
                            Label(status.resumable ? "Continue Sunday's notes" : "Photograph Sunday's notes", systemImage: "camera")
                                .font(.system(size: 15.5, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(Color.ccOnChapel)
                        }
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

    private func refresh() {
        status = CaptureStatus(context: context)
        let store = LordsDayStore(context: context)
        if let note = try? store.currentWeek(), let cards = try? store.cards(for: note), !cards.isEmpty {
            feed = LordsDayFeed(note: note, cards: cards)
        } else {
            feed = nil
        }
    }
}

/// What the tab says about this week's notes until the feed (TKL-862) shows them.
private struct CaptureStatus {
    var resumable = false
    var savedLine: String?

    init() {}

    @MainActor init(context: ModelContext) {
        resumable = (try? CaptureDraft.activeNoteId()) != nil
        guard !resumable, let note = try? LordsDayStore(context: context).currentWeek() else { return }
        let pages = (try? CaptureDraft(noteId: note.id))?.pages.count ?? 0
        let what = pages > 0 ? "\(pages) page\(pages == 1 ? "" : "s")" : "typed notes"
        savedLine = "Saved: \(note.serviceDate.formatted(.dateTime.weekday(.wide).day().month())) · \(what). Cards from your notes arrive in the next update."
    }
}
