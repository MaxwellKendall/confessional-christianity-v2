// The Lord's Day loop's sheets (TKL-942, the TKL-836 prototype): Share opens a
// live preview of the image in a palette you pick, then the system share
// sheet; Edit changes a kept card's words or kind, or hides it; the cover's
// note photos open full screen.
import SwiftUI
import DomainKit

/// What the share sheet sends: one card's (or the cover's) quote-card content.
struct ShareSubject: Identifiable {
    let id = UUID()
    let content: QuoteCardContent
    /// The palette on screen (dark mode already applied), selected first.
    let palette: QuoteCardPalette
    let label: String
    /// The text that travels with the image.
    let message: String
    var onShare: () -> Void = {}
}

struct LordsDayShareSheet: View {
    let subject: ShareSubject
    @State private var palette: QuoteCardPalette
    @State private var image: SermonShareImage?

    init(subject: ShareSubject) {
        self.subject = subject
        _palette = State(initialValue: subject.palette)
    }

    /// The house palettes, plus the one on screen when it isn't one of them.
    private var palettes: [QuoteCardPalette] {
        let house = LordsDayShare.palettes
        return house.contains(subject.palette) ? house : [subject.palette] + house
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
                .padding(.top, 28)
                .padding(.bottom, 20)
            paletteRow.padding(.bottom, 22)
            shareButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.ccSurface)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.ccSurface)
        .task(id: palette.name) {
            let content = subject.content, palette = palette
            let rendered = await Task.detached(priority: .userInitiated) { () -> SermonShareImage? in
                guard let png = LordsDayShare.png(content, palette: palette), let preview = UIImage(data: png) else { return nil }
                return SermonShareImage(png: png, preview: preview)
            }.value
            guard !Task.isCancelled else { return }
            image = rendered
        }
        .accessibilityIdentifier("lordsDay.shareSheet")
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: palette.field))
            if let image {
                Image(uiImage: image.preview).resizable().interpolation(.high).scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(width: 330, height: 330)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        .animation(.easeOut(duration: 0.15), value: image?.png)
        .accessibilityElement()
        .accessibilityLabel("Preview of the \(subject.label) image")
        .accessibilityIdentifier("lordsDay.sharePreview")
    }

    private var paletteRow: some View {
        HStack(spacing: 12) {
            ForEach(palettes, id: \.name) { p in
                Button { palette = p } label: {
                    Circle().fill(Color(hex: p.field))
                        .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1))
                        .frame(width: 30, height: 30)
                        .padding(3)
                        .overlay(Circle().strokeBorder(p == palette ? Color.ccGilt : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.name.capitalized)
                .accessibilityAddTraits(p == palette ? .isSelected : [])
                .accessibilityIdentifier("lordsDay.sharePalette.\(p.name)")
            }
        }
    }

    @ViewBuilder private var shareButton: some View {
        Group {
            if let image {
                ShareLink(item: image, message: Text(subject.message),
                          preview: SharePreview(subject.label, image: Image(uiImage: image.preview))) { shareLabel }
                    .simultaneousGesture(TapGesture().onEnded(subject.onShare))
            } else {
                shareLabel.opacity(0.5)
            }
        }
        .accessibilityIdentifier("lordsDay.shareSend")
    }

    private var shareLabel: some View {
        Label("Share image", systemImage: "square.and.arrow.up")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.ccOnChapel)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Edit

/// Editing a kept card from the reel: the words and kind for a key point or
/// quote; a verse only through the verse picker. Every change goes through the
/// store's validation, so blank words are refused. Hide removes it from the stack.
struct LordsDayCardEditSheet: View {
    let card: LordsDayFeedCard
    let passageOsis: String?
    let onChanged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CardKind
    @State private var text: String
    @State private var verseRef: String?
    @State private var picking = false
    @State private var confirmingHide = false
    @State private var error: String?

    init(card: LordsDayFeedCard, passageOsis: String?, onChanged: @escaping () -> Void) {
        self.card = card; self.passageOsis = passageOsis; self.onChanged = onChanged
        _kind = State(initialValue: card.kind)
        _text = State(initialValue: card.kind == .verse ? "" : card.body)
        _verseRef = State(initialValue: card.verseOsis ?? card.reference)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit card").font(.ccDisplay(20, semibold: true)).foregroundStyle(.ccInk).padding(.bottom, 4)
            Text("Drafted from your notes. Change the words or the kind; it's yours.")
                .font(.system(size: 14)).foregroundStyle(.ccInk2).padding(.bottom, 14)
            kinds.padding(.bottom, 12)
            if kind == .verse { verseField } else { wordsField }
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(.ccDanger).padding(.top, 8)
                    .accessibilityIdentifier("lordsDay.edit.error")
            }
            Spacer(minLength: 14)
            HStack(spacing: 8) {
                Button { confirmingHide = true } label: {
                    Text("Hide card").font(.system(size: 16, weight: .semibold)).foregroundStyle(.ccDanger)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.ccDangerFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityIdentifier("lordsDay.edit.hide")
                Button(action: save) {
                    Text("Done").font(.system(size: 16, weight: .semibold)).foregroundStyle(.ccOnChapel)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityIdentifier("lordsDay.edit.done")
            }
        }
        .padding(EdgeInsets(top: 28, leading: 20, bottom: 12, trailing: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.ccSurface)
        .presentationDetents([.height(440), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.ccSurface)
        .sheet(isPresented: $picking) {
            VersePickerView(startOsis: verseRef.flatMap(citationToOsis) ?? verseRef ?? passageOsis) { osis in
                verseRef = osis
                kind = .verse
                error = nil
            }
        }
        .confirmationDialog("Hide this card?", isPresented: $confirmingHide, titleVisibility: .visible) {
            Button("Hide card", role: .destructive, action: hide)
        } message: {
            Text("It leaves this sermon's stack.")
        }
        .accessibilityIdentifier("lordsDay.editSheet")
    }

    private var kinds: some View {
        HStack(spacing: 8) {
            ForEach(CardKind.allCases, id: \.self) { k in
                Button {
                    // A Verse card is always a reference picked from the Bible, never typed.
                    if k == .verse, verseRef == nil || card.kind != .verse { picking = true } else { kind = k }
                    error = nil
                } label: {
                    Text(k.label).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(kind == k ? Color.ccOnChapel : Color.ccInk)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(kind == k ? Color.ccChapel : Color.ccFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == k ? .isSelected : [])
                .accessibilityIdentifier("lordsDay.edit.kind.\(k.rawValue)")
            }
        }
    }

    private var wordsField: some View {
        TextEditor(text: $text)
            .font(.ccBody(16.5))
            .foregroundStyle(.ccInk)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minHeight: 110, maxHeight: 180)
            .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("lordsDay.edit.text")
    }

    private var verseField: some View {
        Button { picking = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verseRef.map(Self.readable) ?? "Pick a verse").font(.ccBody(18)).foregroundStyle(.ccInk)
                    Text("The words come from the Bible, never typed.").font(.system(size: 13)).foregroundStyle(.ccInk3)
                }
                Spacer()
                Text("Change verse").font(.system(size: 14, weight: .semibold)).foregroundStyle(.ccChapel)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lordsDay.edit.verse")
    }

    private static func readable(_ ref: String) -> String {
        ref.contains(".") ? parseOsisBibleReference(ref) : ref
    }

    private func save() {
        let store = LordsDayStore(context: context)
        do {
            guard let stored = try store.card(id: card.id) else { dismiss(); return }
            if kind == .verse {
                guard let ref = verseRef else { picking = true; return }
                if stored.kind == .verse { try store.changeVerse(of: stored, to: ref) }
                else { try store.switchKind(of: stored, to: .verse, verseRef: ref) }
            } else {
                // Check the words first, so a refused edit leaves the card as it was.
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LordsDayError.emptyBody }
                if stored.kind != kind { try store.switchKind(of: stored, to: kind) }
                try store.editBody(of: stored, body: text)
            }
            onChanged()
            dismiss()
        } catch LordsDayError.emptyBody {
            error = "Write something for the card, or hide it."
        } catch {
            self.error = "That change couldn't be saved."
        }
    }

    private func hide() {
        let store = LordsDayStore(context: context)
        if let stored = try? store.card(id: card.id) { try? store.removeCard(stored) }
        onChanged()
        dismiss()
    }
}

// MARK: - Note photos

/// The cover's note photos, full screen: swipe between pages.
struct NotePhotosView: View {
    let photos: [UIImage]
    let start: Int
    let onClose: () -> Void
    @State private var page: Int

    init(photos: [UIImage], start: Int, onClose: @escaping () -> Void) {
        self.photos = photos; self.start = start; self.onClose = onClose
        _page = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(photos.indices, id: \.self) { i in
                    Image(uiImage: photos[i]).resizable().scaledToFit().tag(i)
                        .accessibilityLabel("Notes page \(i + 1) of \(photos.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .ignoresSafeArea()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Color.white.opacity(0.16), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("lordsDay.photos.close")
        }
        .accessibilityIdentifier("lordsDay.photos")
    }
}

/// The cover's photo thumbnails, two or three slightly turned pages.
struct NoteThumbnails: View {
    let photos: [UIImage]
    let onOpen: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(photos.prefix(3).enumerated()), id: \.offset) { i, photo in
                Button { onOpen(i) } label: {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 46, height: 60).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .rotationEffect(.degrees(i % 2 == 0 ? -3 : 4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open notes page \(i + 1)")
                .accessibilityIdentifier("lordsDay.thumbnail.\(i)")
            }
        }
    }
}
