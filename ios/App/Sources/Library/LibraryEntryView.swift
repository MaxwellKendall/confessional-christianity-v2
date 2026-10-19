// A single confession/catechism entry's reading page — mirrors
// src/app/(column)/library/[confession]/[entry]/page.tsx, but for the
// proof-texts panel follows QuestionCardView's catechism-session pattern
// rather than web's per-citation click-to-expand list: one clause is
// "active" at a time (tap any footnote-marked clause to switch), its group's
// verses are fetched live through EsvClient and shown automatically. Each
// citation links out to that reference's canonical cross-reference page
// (ScriptureView, mirroring web's /scripture/[osis]).
//
// Paging also responds to a horizontal swipe (left = next, right = prev,
// the standard iOS carousel convention), not just the Prev/Next links —
// `.simultaneousGesture` so it doesn't fight the ScrollView's own vertical
// drag; only acts when the gesture is clearly horizontal and past a
// deliberate-swipe threshold.
import SwiftUI
import DomainKit

struct LibraryEntryView: View {
    let slug: String
    let entryId: String
    @Binding var path: NavigationPath

    @State private var activeMarker: String?
    @State private var verseTexts: [String: String?] = [:]

    private var page: EntryPage? { getEntryPage(slug, entryId: entryId) }
    private var groups: [ProofTextGroup] { page.map { proofTextGroups($0.item) } ?? [] }
    private var activeGroup: ProofTextGroup? { groups.first { $0.marker == activeMarker } }
    private var reflection: Reflection? { getReflectionByEntryId(entryId) }

    private var activeSegmentLabel: String? {
        guard let page else { return nil }
        let allSegments = entryQuoteSegments(page.item).flatMap { $0 }
        guard let segment = allSegments.first(where: { $0.marker == activeMarker }) else { return nil }
        return truncateClause(segment.text)
    }

    var body: some View {
        // The prev/next paging row is a pinned footer, not the tail of the
        // ScrollView's content — a short entry (e.g. a single-sentence
        // thesis) would otherwise leave it stranded right under the quote
        // instead of anchored at a consistent position above the tab bar.
        VStack(spacing: 0) {
            ScrollView {
                if let page {
                    VStack(spacing: 0) {
                        breadcrumb(page)

                        VStack(spacing: 10) {
                            Text(entryPageLabel(page.item))
                                .labelCaps(size: 9.5, tracking: 0.1)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(entryQuoteSegments(page.item).enumerated()), id: \.offset) { _, line in
                                    FlowText(prefix: "", segments: line, activeMarker: activeMarker) { marker in
                                        withAnimation(.easeOut(duration: 0.15)) { activeMarker = marker }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 22)

                        shareRow(page)

                        if let reflection {
                            commentaryLink(reflection)
                        }

                        if !groups.isEmpty {
                            scriptureSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }

            if let page {
                HStack {
                    pagingLink(page.prevEntry, symbol: "\u{2190}", isNext: false)
                    Spacer()
                    pagingLink(page.nextEntry, symbol: "\u{2192}", isNext: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.ccHairline).frame(height: 1)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ccCard)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { activeMarker = groups.first?.marker }
        .task(id: "\(entryId)|\(activeMarker ?? "")") {
            await loadVerseTexts()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical), abs(horizontal) > 60, let page else { return }
                    if horizontal < 0, let next = page.nextEntry {
                        navigate(to: next.entryId)
                    } else if horizontal > 0, let prev = page.prevEntry {
                        navigate(to: prev.entryId)
                    }
                }
        )
    }

    private func navigate(to entryId: String) {
        path.removeLast()
        path.append(LibraryRoute.entry(slug: slug, entryId: entryId))
    }

    /// Share the clause being shown (with its Scripture) or the whole entry.
    /// One button, not the former pair of 9.5pt text links: those were under
    /// the 44pt target, wore the same dotted underline as the citations and
    /// the breadcrumb, and named neither the clause nor what would be sent.
    /// The sheet shows the quote card first, so the choice is visible.
    @ViewBuilder
    private func shareRow(_ page: EntryPage) -> some View {
        HStack(spacing: 0) {
            Spacer()
            ShareEntryButton(quote: shareQuote(page))
        }
        .padding(.top, 4)
        .padding(.trailing, -10)
    }

    private func shareQuote(_ page: EntryPage) -> ShareQuote {
        ShareQuote(
            documentTitle: page.documentTitle,
            entryLabel: entryPageLabel(page.item),
            slug: slug,
            entryId: entryId,
            clauseMarker: clauseMarker,
            clauseText: clauseMarker.map { clauseForMarker(page.item, marker: $0) },
            entryText: entryQuoteSegments(page.item).flatMap { $0 }.map(\.text).joined(),
            clauseRefCount: activeGroup?.refs.count ?? 0,
            entryRefCount: groups.reduce(0) { $0 + $1.refs.count }
        )
    }

    /// The clause the sheet may offer: only when one is active and the entry
    /// has more than one, so "this clause" never silently means all of it.
    private var clauseMarker: String? {
        guard let activeMarker, groups.count > 1 else { return nil }
        return activeMarker
    }

    @ViewBuilder
    private func commentaryLink(_ reflection: Reflection) -> some View {
        Button {
            path.append(ReflectionsRoute.detail(slug: reflection.slug))
        } label: {
            Text("\u{2020} Commentary \u{2014} \(reflection.title)")
                .labelCaps(size: 9.5, tracking: 0.1, color: .ccInk)
                .dottedUnderline(.ccInk)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private var scriptureSection: some View {
        VStack(spacing: 12) {
            Text("Proof Texts").labelCaps(size: 9.5, tracking: 0.1)

            if groups.count > 1, let label = activeSegmentLabel {
                HStack(spacing: 6) {
                    Circle().fill(Color.ccOchre).frame(width: 6, height: 6)
                    Text("Now Showing \u{2014} \u{201C}\(label)\u{201D}")
                        .labelCaps(size: 9, tracking: 0.1, color: .ccOchre)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.ccOchre.opacity(0.1)))
            }

            VStack(spacing: 14) {
                ForEach(activeGroup?.refs ?? [], id: \.osis) { ref in
                    VStack(spacing: 4) {
                        Text(resolvedVerseText(ref))
                            .font(.ccBody(15))
                            .italic()
                            .foregroundStyle(.ccInk)
                            .multilineTextAlignment(.center)
                        Button {
                            path.append(ScriptureRoute.detail(osis: ref.osis))
                        } label: {
                            Text(ref.citation)
                                .labelCaps(size: 9, tracking: 0.1, color: .ccInk3)
                                .dottedUnderline(.ccInk3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 70)

            if groups.count > 1 {
                Text("Tap the other phrase above to see its verse")
                    .font(.ccBody(11))
                    .italic()
                    .foregroundStyle(.ccMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
        }
    }

    private func resolvedVerseText(_ ref: ProofTextRef) -> String {
        guard let stored = verseTexts[ref.osis] else { return "\u{2026}" }
        return stored ?? ref.citation
    }

    private func loadVerseTexts() async {
        guard let group = activeGroup else { return }
        await withTaskGroup(of: (String, String?).self) { taskGroup in
            for ref in group.refs where verseTexts[ref.osis] == nil {
                taskGroup.addTask { (ref.osis, await EsvClient.shared.text(for: ref.osis)) }
            }
            for await (osis, text) in taskGroup {
                verseTexts.updateValue(text, forKey: osis)
            }
        }
    }

    @ViewBuilder
    private func breadcrumb(_ page: EntryPage) -> some View {
        HStack(spacing: 4) {
            Button {
                path.removeLast(path.count)
            } label: {
                Text("Library").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3).dottedUnderline(.ccInk3)
            }
            .buttonStyle(.plain)
            Text("/").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
            Button {
                path.removeLast()
            } label: {
                Text(page.documentTitle).labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    @ViewBuilder
    private func pagingLink(_ adjacent: AdjacentEntry?, symbol: String, isNext: Bool) -> some View {
        if let adjacent {
            Button {
                navigate(to: adjacent.entryId)
            } label: {
                Text(isNext ? "\(adjacent.title) \(symbol)" : "\(symbol) \(adjacent.title)")
                    .labelCaps(size: 10, tracking: 0.1, color: .ccInk)
                    .dottedUnderline(.ccInk)
            }
            .buttonStyle(.plain)
        } else {
            Text(isNext ? "Next \(symbol)" : "\(symbol) Prev")
                .labelCaps(size: 10, tracking: 0.1, color: .ccMuted)
        }
    }
}

// Links from the app into the web app — today, share links. One host for
// every outbound web URL, the same deployment EsvClient talks to; switch it
// here when the custom domain points at v2. (Lives in this file rather than
// its own so the committed XcodeGen project needs no regeneration.)
enum WebLinks {
    static let base = URL(string: "https://confessional-christianity-v2.vercel.app")!

    /// /share/<document slug>/<entry segment>[?c=<marker>] — mirrors
    /// sharePath in src/lib/share.ts. The page unfurls into a preview image
    /// of the quote and its Scripture wherever the link is pasted.
    static func share(slug: String, entryId: String, marker: String?) -> URL {
        let documentId = String(entryId.split(separator: "-").first ?? "")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = "/share/\(slug)/\(entryIdToPathSegment(entryId, documentId))"
        if let marker {
            components.queryItems = [URLQueryItem(name: "c", value: marker)]
        }
        return components.url!
    }
}

/// What a share carries: the active clause, or the entry entire.
enum ShareScope {
    case clause
    case article
}

/// Everything a share needs about one entry, so the sheet serves both the
/// Library's reading page and the catechism session card without knowing
/// which it is standing in.
struct ShareQuote {
    let documentTitle: String
    /// "Article 1", "Question 2" — the entry's own heading.
    let entryLabel: String
    let slug: String
    let entryId: String
    /// nil when there is no clause worth distinguishing from the whole.
    let clauseMarker: String?
    let clauseText: String?
    let entryText: String
    let clauseRefCount: Int
    let entryRefCount: Int

    var source: String { "\(documentTitle), \(entryLabel)" }

    /// "article", "question" — taken from the entry's own heading, so the
    /// catechisms don't get called articles.
    var entryNoun: String {
        let head = entryLabel.split(separator: " ").first.map(String.init)?.lowercased() ?? "entry"
        return head.hasPrefix("q") ? "question" : head
    }

    func quote(_ scope: ShareScope) -> String {
        if scope == .clause, let clauseText { return truncateShareQuote(clauseText) }
        return truncateShareQuote(entryText)
    }

    /// Markers are uppercase in the confessions and lowercase in the
    /// catechisms; the shared text reads as one voice either way.
    func sourceLine(_ scope: ShareScope) -> String {
        guard scope == .clause, let clauseMarker else { return source }
        return "\(source) \u{00B7} Clause \(clauseMarker.uppercased())"
    }

    func refCount(_ scope: ShareScope) -> Int {
        scope == .clause && clauseMarker != nil ? clauseRefCount : entryRefCount
    }

    func url(_ scope: ShareScope) -> URL {
        WebLinks.share(slug: slug, entryId: entryId, marker: scope == .clause ? clauseMarker : nil)
    }

    func text(_ scope: ShareScope) -> String {
        "\u{201C}\(quote(scope))\u{201D} \u{2014} \(sourceLine(scope))\n\(url(scope).absoluteString)"
    }
}

/// The share affordance both reading screens use: a bare glyph, sized small
/// but padded out to a 44pt target, opening the sheet that shows the quote
/// card. Replaces the former pair of 9.5pt text links, which were under the
/// minimum target, wore the same dotted underline as the citations and the
/// breadcrumb, and named neither the clause nor what would be sent.
struct ShareEntryButton: View {
    let quote: ShareQuote

    @State private var isSharing = false
    @State private var scope: ShareScope = .clause

    var body: some View {
        Button {
            scope = quote.clauseMarker == nil ? .article : .clause
            isSharing = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15))
                .foregroundStyle(.ccInk2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
        .sheet(isPresented: $isSharing) {
            ShareQuoteSheet(quote: quote, scope: $scope)
                .presentationDetents([.fraction(0.64), .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// The quote about to be shared, shown before anything is sent — the same
/// card /share renders as its preview image. Copy text and the rendered
/// image carry the quote on their own, which matters wherever a pasted link
/// never unfurls (and everywhere, until /share is deployed).
private struct ShareQuoteSheet: View {
    let quote: ShareQuote
    @Binding var scope: ShareScope

    @Environment(\.dismiss) private var dismiss
    @State private var cardImage: Image?
    @State private var didCopy = false

    private var sourceLine: String { quote.sourceLine(scope) }
    private var shareURL: URL { quote.url(scope) }
    private var shareText: String { quote.text(scope) }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Share").labelCaps(size: 11, tracking: 0.14, color: .ccInk)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.ccInk2)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.ccFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if let clauseMarker = quote.clauseMarker {
                scopePicker(clauseMarker)
            }

            SharePreviewCard(
                quote: quote.quote(scope),
                source: sourceLine,
                refCount: quote.refCount(scope)
            )

            ShareLink(item: shareURL, subject: Text(quote.source), message: Text(shareText)) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                    Text("Send link").labelCaps(size: 10.5, tracking: 0.12, color: .ccCard)
                }
                .foregroundStyle(.ccCard)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.ccInk))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = shareText
                    withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
                } label: {
                    secondaryLabel(didCopy ? "Copied" : "Copy text")
                }
                .buttonStyle(.plain)

                if let cardImage {
                    ShareLink(item: cardImage, preview: SharePreview(sourceLine, image: cardImage)) {
                        secondaryLabel("Share image")
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Whoever opens the link lands on this quote.")
                .font(.ccBody(12))
                .italic()
                .foregroundStyle(.ccInk3)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(Color.ccCard)
        .onAppear { cardImage = renderCard() }
        .onChange(of: scope) { _, _ in
            didCopy = false
            cardImage = renderCard()
        }
    }

    @ViewBuilder
    private func scopePicker(_ marker: String) -> some View {
        HStack(spacing: 4) {
            scopeTab("Clause \(marker)", isOn: scope == .clause) { scope = .clause }
            scopeTab("Whole \(quote.entryNoun)", isOn: scope == .article) { scope = .article }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.ccFill))
    }

    private func scopeTab(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .labelCaps(size: 9.5, tracking: 0.1, color: isOn ? .ccCard : .ccInk2)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Color.ccInk : .clear))
        }
        .buttonStyle(.plain)
    }

    private func secondaryLabel(_ title: String) -> some View {
        Text(title)
            .labelCaps(size: 9.5, tracking: 0.1, color: .ccInk)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ccHairline, lineWidth: 1))
    }

    /// The card as a flat image, for the chats that take a picture but never
    /// fetch a link preview.
    @MainActor
    private func renderCard() -> Image? {
        let renderer = ImageRenderer(
            content: ShareCardImage(
                documentTitle: quote.documentTitle,
                quote: quote.quote(scope),
                source: sourceLine
            )
        )
        renderer.scale = 2
        return renderer.uiImage.map(Image.init(uiImage:))
    }
}

private struct SharePreviewCard: View {
    let quote: String
    let source: String
    let refCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Color.ccOchre).frame(width: 34, height: 2)
            Text("\u{201C}\(quote)\u{201D}")
                .font(.ccBody(16))
                .foregroundStyle(.ccInk)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            Text(source).labelCaps(size: 9, tracking: 0.12, color: .ccInk2)
            Rectangle().fill(Color.ccHairline2).frame(height: 1)
            HStack {
                Text("confessionalchristianity.com").labelCaps(size: 8.5, tracking: 0.1)
                Spacer()
                Text(refCount == 1 ? "1 proof text" : "\(refCount) proof texts")
                    .labelCaps(size: 8.5, tracking: 0.1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ccFill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ccHairline2, lineWidth: 1))
    }
}

/// 1200x630, the size link previews crop to.
private struct ShareCardImage: View {
    let documentTitle: String
    let quote: String
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.ccOchre).frame(height: 6)
            VStack(alignment: .leading, spacing: 30) {
                Text(documentTitle).labelCaps(size: 17, tracking: 0.18, color: .ccOchre)
                Text("\u{201C}\(quote)\u{201D}")
                    .font(.ccBody(50))
                    .foregroundStyle(.ccInk)
                    .lineSpacing(16)
                    .lineLimit(6)
                    .minimumScaleFactor(0.45)
                Spacer(minLength: 0)
                Rectangle().fill(Color.ccHairline).frame(height: 1)
                HStack(alignment: .bottom) {
                    Text(source).labelCaps(size: 20, tracking: 0.1, color: .ccInk)
                    Spacer()
                    Text("confessionalchristianity.com").labelCaps(size: 15, tracking: 0.12, color: .ccInk2)
                }
            }
            .padding(.horizontal, 88)
            .padding(.vertical, 76)
        }
        .frame(width: 1200, height: 630)
        .background(Color.ccFill)
    }
}

private let maxShareQuoteLength = 420

/// Mirrors MAX_QUOTE_CHARS in src/lib/share.ts: past this a quote stops
/// reading as a quote, so it is cut at a word boundary. Leading punctuation
/// belongs to the clause before it (the session card's segments arrive
/// unstripped, unlike clauseForMarker's), so it is shed first.
private func truncateShareQuote(_ text: String) -> String {
    let trimmed = text
        .replacingOccurrences(of: "^[\\s,;:.]+", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= maxShareQuoteLength { return trimmed }
    let cut = String(trimmed.prefix(maxShareQuoteLength))
    if let lastSpace = cut.range(of: " ", options: .backwards) {
        return String(cut[..<lastSpace.lowerBound]) + "\u{2026}"
    }
    return cut + "\u{2026}"
}
