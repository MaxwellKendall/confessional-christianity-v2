// The Lord's Day tab (pillar two, TKL-825). The week's card feed (TKL-862)
// and the archive (TKL-865) are separate tickets; until they land this is the
// tab's empty state from TKL-885's prototype, saying what the pillar does, with
// the way into photographing Sunday's notes (TKL-860).
import SwiftUI
import SwiftData
import DomainKit

struct LordsDayTabView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @State private var capture: CaptureModel?
    @State private var status = CaptureStatus()

    var body: some View {
        NavigationStack(path: $path) {
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
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
        }
        .tint(.ccInk)
        .fullScreenCover(item: $capture, onDismiss: refresh) { model in
            CaptureView(model: model, onClose: { capture = nil })
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        status = CaptureStatus(context: context)
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
