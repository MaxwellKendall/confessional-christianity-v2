// One page of a sermon's stack (TKL-1063, design TKL-1062): a binding row
// naming the sermon with "N of M", the cover or a card's words, and a footer
// row inside the card with Read (verse cards) and Share. The same view draws
// the landing page's stack (compact) and each page of the reel (large).
import SwiftUI
import DomainKit
import UniformTypeIdentifiers

struct SermonCardBinding {
    /// Nil on the cover, which reads "THE LORD'S DAY".
    var title: String?
    var meta: String?
    var count: String
}

struct SermonCover {
    var dateCaps: String
    var title: String
    var passage: String?
    var who: String?

    init(dateCaps: String, title: String, passage: String?, who: String?) {
        self.dateCaps = dateCaps; self.title = title; self.passage = passage; self.who = who
    }

    init(sermon: ReelSermon) {
        dateCaps = "SUNDAY · \(sermon.dateCaps)"
        title = sermon.title
        // The passage under the title, unless it already is the title.
        passage = sermon.title == sermon.passage ? nil : sermon.passage
        let who = [sermon.preacher, sermon.church].compactMap { $0 }
        self.who = who.isEmpty ? nil : who.joined(separator: " · ")
    }
}

enum SermonPage {
    case cover(SermonCover)
    case card(LordsDayFeedCard)
}

struct SermonCardView<Footer: View>: View {
    let page: SermonPage
    let binding: SermonCardBinding
    /// The light palette; dark mode swaps it here.
    let palette: QuoteCardPalette
    var large = false
    var hint: String?
    var allowsNetwork = false
    var readerSource: ReaderSource?
    /// What Share sends for the cover (TKL-942): its quote-card content and message.
    var coverShare: (content: QuoteCardContent, message: String)?
    /// The kept note whose photos the cover shows as thumbnails.
    var photosNoteId: UUID?
    /// Edit on kept cards (the reel only).
    var onEdit: ((LordsDayFeedCard) -> Void)?
    /// Replaces Read and Share (the draft cover's Review button).
    let footerOverride: Footer?
    @State private var verseText: String?
    @State private var shareSubject: ShareSubject?
    @State private var photos: [UIImage] = []
    @State private var openPhoto: PhotoOpening?
    #if DEBUG
    /// Screenshot hook (TKL-942): "share" or "photo" opens it once this page appears.
    var debugOpens: String?
    #endif
    @Environment(\.colorScheme) private var colorScheme

    init(page: SermonPage, binding: SermonCardBinding, palette: QuoteCardPalette, large: Bool = false, hint: String? = nil,
         allowsNetwork: Bool = false, readerSource: ReaderSource? = nil,
         coverShare: (content: QuoteCardContent, message: String)? = nil, photosNoteId: UUID? = nil,
         onEdit: ((LordsDayFeedCard) -> Void)? = nil, @ViewBuilder footer: () -> Footer) {
        self.page = page; self.binding = binding; self.palette = palette; self.large = large; self.hint = hint
        self.allowsNetwork = allowsNetwork; self.readerSource = readerSource; self.coverShare = coverShare
        self.photosNoteId = photosNoteId; self.onEdit = onEdit
        self.footerOverride = footer()
        if case .card(let card) = page {
            _verseText = State(initialValue: card.verseOsis.flatMap(bundledEsvText).flatMap(Self.nonEmpty))
        }
    }

    private var p: QuoteCardPalette { LordsDayFeed.palette(palette, dark: colorScheme == .dark) }
    private var field: Color { Color(hex: p.field) }
    private var ink: Color { Color(hex: p.ink) }
    private var accent: Color { Color(hex: p.accent) }
    private var muted: Color { Color(hex: p.muted) }
    private var frame: Color { Color(hex: p.frame) }
    private var card: LordsDayFeedCard? { if case .card(let c) = page { c } else { nil } }

    var body: some View {
        VStack(spacing: 0) {
            bindingRow
            Rectangle().fill(frame).frame(height: 1)
            bodyBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: card == nil ? .bottomLeading : .leading)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, card == nil ? 26 : 18)
            Rectangle().fill(frame).frame(height: 1)
            footerRow
        }
        .foregroundStyle(ink)
        .background(field)
        .clipShape(RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous))
        .task(id: VerseRequest(osis: card?.verseOsis, active: allowsNetwork)) {
            guard allowsNetwork, verseText == nil, let osis = card?.verseOsis else { return }
            let text = Self.nonEmpty(await EsvClient.shared.text(for: osis))
            guard !Task.isCancelled else { return }
            verseText = text
        }
        .task(id: card == nil ? photosNoteId : nil) {
            // The cover's note photos stay on the device after keeping (TKL-863); read them off the main thread.
            guard card == nil, let id = photosNoteId else { return }
            let loaded = await Task.detached(priority: .utility) {
                CaptureDraft.savedPages(noteId: id).compactMap(UIImage.init(data:))
            }.value
            guard !Task.isCancelled else { return }
            photos = loaded
            #if DEBUG
            if debugOpens == "photo", !loaded.isEmpty { openPhoto = PhotoOpening(index: 0) }
            #endif
        }
        #if DEBUG
        .task {
            guard debugOpens == "share" else { return }
            try? await Task.sleep(for: .milliseconds(600))
            openShare()
        }
        #endif
        .sheet(item: $shareSubject) { LordsDayShareSheet(subject: $0) }
        .fullScreenCover(item: $openPhoto) { opening in
            NotePhotosView(photos: photos, start: opening.index) { openPhoto = nil }
        }
    }

    private struct VerseRequest: Equatable { let osis: String?; let active: Bool }
    private struct PhotoOpening: Identifiable { let index: Int; var id: Int { index } }

    // MARK: binding

    private var bindingRow: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                if let title = binding.title {
                    Text(title).font(.ccDisplay(15, semibold: true)).lineLimit(1)
                    if let meta = binding.meta {
                        Text(meta).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
                    }
                } else {
                    Text("THE LORD'S DAY").font(.ccDisplay(12)).tracking(12 * 0.16).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(binding.count).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
                .accessibilityIdentifier("lordsDay.cardCount")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
    }

    // MARK: body

    @ViewBuilder private var bodyBlock: some View {
        switch page {
        case .cover(let cover):
            VStack(alignment: .leading, spacing: 0) {
                Text(cover.dateCaps).font(.ccDisplay(11)).tracking(11 * 0.2).foregroundStyle(accent)
                Text(cover.title)
                    .font(.ccDisplay(large ? 34 : 30, semibold: true))
                    .lineLimit(4).minimumScaleFactor(0.6)
                    .padding(.top, 10).padding(.bottom, 12)
                if let passage = cover.passage { Text(passage).font(.ccBody(18)) }
                if let who = cover.who { Text(who).font(.system(size: 13)).foregroundStyle(muted).padding(.top, 6) }
                if !photos.isEmpty {
                    NoteThumbnails(photos: photos) { openPhoto = PhotoOpening(index: $0) }.padding(.top, 18)
                }
            }
        case .card(let card):
            VStack(alignment: .leading, spacing: 0) {
                kindLabel(card.kind).padding(.bottom, 16)
                content(card)
            }
        }
    }

    private func kindLabel(_ kind: CardKind) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(accent).frame(width: 22, height: 1)
            Text(kind.label).font(.ccDisplay(11)).tracking(11 * 0.24).textCase(.uppercase).foregroundStyle(accent)
            Rectangle().fill(accent).frame(width: 22, height: 1)
        }
    }

    private var textSize: CGFloat { large ? 28 : 25 }

    @ViewBuilder private func content(_ card: LordsDayFeedCard) -> some View {
        switch card.kind {
        case .keyPoint:
            words(card.body)
            attribution(card.attributionLine)
        case .quote:
            Text("\u{201C}").font(.ccBody(42)).foregroundStyle(accent).frame(height: 22, alignment: .top)
            words(card.body)
            attribution(card.attributionLine)
        case .verse:
            if let verseText {
                let parts = verseLead(verseText)
                (Text(parts.lead.isEmpty ? "" : parts.lead + " ").font(.ccDisplay(textSize * 0.92)).foregroundColor(accent)
                    + Text(parts.rest).font(.ccBody(textSize)))
                    .lineSpacing(textSize * 0.32 - 6)
                    .lineLimit(large ? 12 : 7).minimumScaleFactor(0.5)
                if let ref = card.reference {
                    Text(ref).font(.ccDisplay(12)).tracking(12 * 0.14).textCase(.uppercase).foregroundStyle(accent).padding(.top, 14)
                }
            } else {
                // No text yet (offline, or a reference that doesn't parse): the reference carries the card.
                words(card.reference ?? "")
                Text(card.verseOsis == nil ? "Open it in your Bible." : "The verse appears when you're online.")
                    .font(.system(size: 13)).foregroundStyle(muted).padding(.top, 14)
            }
        }
    }

    private func words(_ text: String) -> some View {
        Text(text).font(.ccBody(textSize)).lineSpacing(textSize * 0.32 - 6)
            .lineLimit(large ? 14 : 8).minimumScaleFactor(0.5)
    }

    @ViewBuilder private func attribution(_ line: String?) -> some View {
        if let line { Text(line).font(.system(size: 13)).foregroundStyle(muted).padding(.top, 14).lineLimit(2) }
    }

    // MARK: footer

    private var footerRow: some View {
        HStack(spacing: 10) {
            if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8) }
            Spacer(minLength: 0)
            if let footerOverride, !(footerOverride is EmptyView) {
                footerOverride
            } else {
                HStack(spacing: 6) {
                    // Share comes first on every page, cover included (TKL-942).
                    shareButton
                    if let readerSource {
                        NavigationLink(value: ScriptureRoute.reader(readerSource)) { pill("Read", systemImage: "book") }
                            .accessibilityIdentifier("lordsDay.read")
                    }
                    if let onEdit, let card {
                        Button { onEdit(card) } label: { pill("Edit", systemImage: "pencil") }
                            .accessibilityLabel("Edit this card")
                            .accessibilityIdentifier("lordsDay.edit")
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 12))
    }

    func pill(_ title: String, systemImage: String) -> some View {
        SermonPill(title: title, systemImage: systemImage, ink: ink)
    }

    @ViewBuilder private var shareButton: some View {
        if card != nil || coverShare != nil {
            Button(action: openShare) { pill("Share", systemImage: "square.and.arrow.up") }
                .accessibilityLabel(card == nil ? "Share this sermon" : "Share this card")
                .accessibilityIdentifier("lordsDay.share")
        }
    }

    /// The share sheet starts in the palette on screen; the image follows the palette picked there.
    private func openShare() {
        if let card {
            shareSubject = ShareSubject(content: card.quoteCardContent(verseText: verseText), palette: p,
                                        label: card.kind.label, message: card.shareText(verseText: verseText),
                                        onShare: { LoopCounter.record(.cardShared(kind: card.kind)) })
        } else if let coverShare {
            shareSubject = ShareSubject(content: coverShare.content, palette: p, label: "The Lord's Day",
                                        message: coverShare.message)
        }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

extension SermonCardView where Footer == EmptyView {
    init(page: SermonPage, binding: SermonCardBinding, palette: QuoteCardPalette, large: Bool = false, hint: String? = nil,
         allowsNetwork: Bool = false, readerSource: ReaderSource? = nil,
         coverShare: (content: QuoteCardContent, message: String)? = nil, photosNoteId: UUID? = nil,
         onEdit: ((LordsDayFeedCard) -> Void)? = nil) {
        self.init(page: page, binding: binding, palette: palette, large: large, hint: hint, allowsNetwork: allowsNetwork,
                  readerSource: readerSource, coverShare: coverShare, photosNoteId: photosNoteId, onEdit: onEdit) { EmptyView() }
    }
}

extension SermonCardView where Footer == EmptyView {
    /// Page `page` of a kept sermon.
    init(sermon: ReelSermon, page: Int, large: Bool = false, hint: String? = nil, allowsNetwork: Bool = false,
         onEdit: ((LordsDayFeedCard) -> Void)? = nil) {
        let card = sermon.card(atPage: page)
        let count = page == 0 ? "\(sermon.pageCount) cards" : "\(page + 1) of \(sermon.pageCount)"
        self.init(
            page: card.map(SermonPage.card) ?? .cover(SermonCover(sermon: sermon)),
            binding: SermonCardBinding(title: page == 0 ? nil : sermon.title, meta: sermon.meta, count: count),
            palette: sermon.palette(atPage: page), large: large, hint: hint, allowsNetwork: allowsNetwork,
            readerSource: card.flatMap(sermon.readerSource(for:)),
            coverShare: page == 0
                ? (sermon.coverQuoteCardContent, [sermon.title, sermon.meta].compactMap { $0 }.joined(separator: "\n"))
                : nil,
            photosNoteId: page == 0 ? sermon.id : nil,
            onEdit: onEdit
        )
    }
}

struct SermonPill: View {
    let title: String
    let systemImage: String
    let ink: Color
    var solid = false
    var field: Color = .clear

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(solid ? field : ink)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(solid ? ink : ink.opacity(0.10), in: Capsule())
        .contentShape(Capsule())
    }
}

/// The card's PNG for the share sheet (TKL-1060).
struct SermonShareImage: Transferable {
    let png: Data
    let preview: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("Confessional Christianity.png")
    }
}
