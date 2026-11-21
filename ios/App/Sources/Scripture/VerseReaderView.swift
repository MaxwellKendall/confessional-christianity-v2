import SwiftUI
import DomainKit

struct VerseReaderView: View {
    private enum Passage {
        case loading
        case verses([ReaderVerse])
        case bundled(String)
        case unavailable
    }

    let source: ReaderSource

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var settings = ReaderSettings.load()
    @State private var passage = Passage.loading
    @State private var attempt = 0
    @State private var showsSettings = false
    @State private var contextChapter: String?
    #if DEBUG
    private var fixtureStart: Int?
    #endif

    init(source: ReaderSource) {
        self.source = source
    }

    private var osis: String {
        switch source {
        case let .sermonText(osis, _, _, _, _), let .proofText(_, _, _, _, osis):
            osis
        }
    }

    private var title: String { parseOsisBibleReference(osis) }
    private var dark: Bool { settings.dark || colorScheme == .dark }
    private var paper: Palette { palette(.paper) }

    private func palette(_ token: ChapelPalette) -> Palette {
        dark ? token.dark : token.light
    }
    private var gilt: Color { Color(hex: dark ? 0xd3a654 : 0xa67a2c) }
    private var chapel: Color { Color(hex: dark ? 0xa8c6b6 : 0x2e4a3e) }
    private var onChapel: Color { Color(hex: dark ? 0x102019 : 0xf2f4ef) }

    var body: some View {
        GeometryReader { geometry in
            let top = geometry.safeAreaInsets.top
            let bottom = geometry.safeAreaInsets.bottom
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    switch passage {
                    case .loading:
                        screen(paper, top, bottom) { loading }
                    case .unavailable:
                        screen(paper, top, bottom) { offline }
                    case let .bundled(text):
                        screen(paper, top, bottom) {
                            verse(text, reference: title, osis: nil, palette: paper)
                        } footer: { copyright }
                    case let .verses(verses):
                        ForEach(pages(verses), id: \.offset) { index, card in
                            readerPage(card, index: index, verseCount: verses.count, top: top, bottom: bottom)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea()
            .overlay(alignment: .top) { header }
        }
        .background(paper.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .hidesFloatingTabBar()
        .navigationDestination(item: $contextChapter) { chapter in
            ReaderChapterView(chapterOSIS: chapter, passageOSIS: osis, settings: settings)
        }
        .sheet(isPresented: $showsSettings) {
            Text("Reading settings")
                .font(.ccDisplay(19, semibold: true))
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        .task(id: LoadKey(osis: osis, attempt: attempt)) {
            #if DEBUG
            if fixtureStart != nil { return }
            #endif
            passage = .loading
            let verses = await EsvClient.shared.verses(for: osis)
            guard !Task.isCancelled else { return }
            if let verses {
                passage = .verses(verses)
            } else if let bundled = bundledEsvText(for: osis) {
                passage = .bundled(bundled)
            } else {
                passage = .unavailable
            }
        }
    }

    private func pages(_ verses: [ReaderVerse]) -> [(offset: Int, element: ReaderCard)] {
        let pages = Array(readerCards(for: source, verses: verses).enumerated())
        #if DEBUG
        if fixtureStart == nil, let card = UserDefaults.standard.string(forKey: "ProofTextReaderCard") {
            let start = ["verse": 1, "end": pages.count - 1][card] ?? 0
            return Array(pages.dropFirst(start))
        }
        return Array(pages.dropFirst(fixtureStart ?? 0))
        #else
        return Array(pages)
        #endif
    }

    private struct LoadKey: Equatable {
        let osis: String
        let attempt: Int
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Back")
            Text(title)
                .font(.ccDisplay(13))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
            Spacer()
            Button { showsSettings = true } label: {
                Text("Aa").font(.ccBody(18))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Reading settings")
        }
        .buttonStyle(.plain)
        .foregroundStyle(paper.ink)
        .environment(\.colorScheme, dark ? .dark : .light)
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func readerPage(_ card: ReaderCard, index: Int, verseCount: Int, top: CGFloat, bottom: CGFloat) -> some View {
        switch card {
        case .intro:
            let palette = palette(isSermon ? .chapel : .sage)
            screen(palette, top, bottom) {
                intro(verseCount: verseCount, palette: palette)
            } footer: {
                Label("Swipe up", systemImage: "chevron.up")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
            }
        case let .verse(item):
            let paletteIndex = index % ChapelPalette.rotating.count
            let palette = palette(ChapelPalette.rotating[paletteIndex])
            let sealColor = paletteIndex == 3 && !dark ? Color(hex: 0xd9b46a) : gilt
            let reference = parseOsisBibleReference(item.osis)
            screen(palette, top, bottom) {
                verse(item.text, reference: reference, osis: item.osis, palette: palette)
            } footer: {
                verseActions(item, reference: reference, sealColor: sealColor)
            }
        case let .notes(note):
            let palette = palette(.parchment)
            screen(palette, top, bottom) {
                VStack(spacing: 16) {
                    kicker("From your notes · Sunday", palette: palette)
                    Text("“\(note)”").font(.ccBody(26))
                }
            } footer: {
                ShareLink(item: note) { actionLabel("Share", icon: "square.and.arrow.up") }
            }
        case .end:
            let palette = palette(ChapelPalette.rotating[index % ChapelPalette.rotating.count])
            screen(palette, top, bottom) {
                end(palette: palette)
            } footer: { copyright }
        }
    }

    private var isSermon: Bool {
        if case .sermonText = source { return true }
        return false
    }

    private func screen<Content: View, Footer: View>(
        _ palette: Palette, _ top: CGFloat, _ bottom: CGFloat,
        @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: 12) {
            content()
                .frame(maxWidth: 420, maxHeight: .infinity)
            footer()
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.ink)
        .buttonStyle(.plain)
        .padding(.horizontal, 32)
        .padding(.top, top + 54)
        .padding(.bottom, bottom + 12)
        .containerRelativeFrame([.horizontal, .vertical])
        .background(palette.paper)
    }

    private func screen<Content: View>(
        _ palette: Palette, _ top: CGFloat, _ bottom: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        screen(palette, top, bottom, content: content) { EmptyView() }
    }

    @ViewBuilder
    private func intro(verseCount: Int, palette: Palette) -> some View {
        VStack(spacing: 14) {
            switch source {
            case let .sermonText(_, weekday, dayIndex, daysInWeek, _):
                kicker("This week’s sermon text · \(weekday)", palette: palette)
                Text(title).font(.ccBody(30))
                Text("\(verseCount) \(verseCount == 1 ? "verse" : "verses"). Read slowly, then swipe up.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 8) {
                    ForEach(0..<max(0, daysInWeek), id: \.self) { day in
                        Circle().strokeBorder(palette.secondary)
                            .background(day < dayIndex ? palette.secondary : .clear, in: Circle())
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 4)
                .accessibilityLabel("Day \(dayIndex) of \(daysInWeek)")
                .accessibilityElement(children: .ignore)
            case let .proofText(slug, number, question, _, _):
                kicker(catechismLabel(slug, number: number), palette: palette)
                Text(question).font(.ccBody(24))
                Text("The proof text. Read it aloud, slowly.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private func catechismLabel(_ slug: String, number: Int) -> String {
        "\(readerCatechismName(for: slug)) · Q. \(number)"
    }

    private func verse(_ text: String, reference: String, osis: String?, palette: Palette) -> some View {
        VStack(spacing: 24) {
            Text(text)
                .font(.ccBody(readerVerseFontSize(textLength: text.count, textSize: settings.textSize)))
                .lineSpacing(5)
                .minimumScaleFactor(0.55)
            kicker(reference, palette: palette)
            if osis == nil {
                ShareLink(item: "\(text)\n— \(reference)") { actionLabel("Share", icon: "square.and.arrow.up") }
            }
        }
    }

    private func verseActions(_ verse: ReaderVerse, reference: String, sealColor: Color) -> some View {
        let count = settings.showConfessionMarks ? citingEntries(forVerse: verse.osis).count : 0
        return HStack(spacing: 28) {
            if count > 0 {
                Button {} label: {
                    VStack(spacing: 5) {
                        Text("\(count)").font(.ccDisplay(12, semibold: true))
                            .frame(width: 30, height: 30)
                            .overlay { Circle().strokeBorder(lineWidth: 1.5) }
                        Text("Confessions").font(.caption2)
                    }
                    .foregroundStyle(sealColor)
                    .frame(minWidth: 44, minHeight: 48)
                }
                .accessibilityLabel("Confessions, \(count) citations")
            }
            if let chapter = ReaderChapter.chapterOSIS(for: verse.osis) {
                Button { contextChapter = chapter } label: {
                    actionLabel("In context", icon: "text.alignleft")
                }
            }
            ShareLink(item: "\(verse.text)\n— \(reference)") { actionLabel("Share", icon: "square.and.arrow.up") }
        }
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 20)).frame(height: 30)
            Text(title).font(.caption2)
        }
        .frame(minWidth: 44, minHeight: 48)
    }

    private func kicker(_ title: String, palette: Palette) -> some View {
        Text(title.uppercased()).font(.ccDisplay(11))
            .tracking(2)
            .foregroundStyle(palette.secondary)
    }

    private func end(palette: Palette) -> some View {
        VStack(spacing: 14) {
            switch source {
            case let .sermonText(_, _, dayIndex, daysInWeek, _):
                kicker("This week’s sermon text", palette: palette)
                Text("That’s the passage.").font(.ccBody(30))
                Text("Day \(dayIndex) of \(daysInWeek) · come back tomorrow and sit with it again.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
                primaryButton("Done for today") { dismiss() }
                if let chapter = ReaderChapter.chapterOSIS(for: osis) {
                    Button { contextChapter = chapter } label: {
                        Text("Read all of \(parseOsisBibleReference(chapter))")
                            .padding(10)
                            .overlay { Capsule().strokeBorder() }
                    }
                }
            case let .proofText(slug, number, _, answer, _):
                kicker(catechismLabel(slug, number: number), palette: palette)
                Text("Now say the answer together.").font(.ccBody(30))
                Text(answer).font(.ccBody(16)).foregroundStyle(palette.secondary)
                primaryButton("Back to Q. \(number)") { dismiss() }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 22)
                .frame(minHeight: 44)
                .background(chapel, in: Capsule())
                .foregroundStyle(onChapel)
        }
    }

    private var copyright: some View {
        Text(EsvClient.copyrightNotice)
            .font(.caption2)
            .padding(.bottom, 4)
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ForEach([280.0, 252.0, 196.0], id: \.self) { width in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: dark ? 0x232823 : 0xecede7))
                    .frame(maxWidth: width)
                    .frame(height: 22)
            }
            .accessibilityHidden(true)
            kicker(title, palette: paper).padding(.top, 14)
            Text("Loading passage").font(.caption).foregroundStyle(paper.secondary)
        }
    }

    private var offline: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash").font(.title)
            Text("The text can’t load right now.").font(.ccBody(24))
            Text(title).font(.subheadline).foregroundStyle(paper.secondary)
            primaryButton("Try again") { attempt += 1 }
        }
    }

    private struct Palette {
        let paper: Color
        let ink: Color
        let secondary: Color

        init(_ paper: UInt32, _ ink: UInt32, _ secondary: UInt32) {
            self.paper = Color(hex: paper)
            self.ink = Color(hex: ink)
            self.secondary = Color(hex: secondary)
        }

    }

    private struct ChapelPalette {
        let light: Palette
        let dark: Palette

        static let paper = Self(light: Palette(0xf5f5f1, 0x1c1f1c, 0x858b83), dark: Palette(0x121513, 0xebece6, 0x7d847c))
        static let sage = Self(light: Palette(0xe6ece6, 0x1f3329, 0x5d7366), dark: Palette(0x16201b, 0xdfe9e2, 0x8aa395))
        static let parchment = Self(light: Palette(0xf2ebdd, 0x3a2e1a, 0x8a7652), dark: Palette(0x1f1b14, 0xefe5d2, 0xa8946f))
        static let chapel = Self(light: Palette(0x2e4a3e, 0xf2f4ef, 0xa9bdb2), dark: Palette(0x0d1813, 0xe6efe9, 0x8fae9f))
        static let dusk = Self(light: Palette(0xe9e6ee, 0x2a2633, 0x77708a), dark: Palette(0x1a1820, 0xe7e3ee, 0x9790a8))
        static let rotating = [paper, sage, parchment, chapel, dusk]
    }

    #if DEBUG
    static func fixture(_ scene: String) -> Self {
        let verses = [
            ReaderVerse(osis: "Rom.8.28", verse: 28, text: "And we know that all things work together for good to them that love God, to them who are the called according to his purpose."),
            ReaderVerse(osis: "Rom.8.29", verse: 29, text: "For whom he did foreknow, he also did predestinate to be conformed to the image of his Son."),
            ReaderVerse(osis: "Rom.8.30", verse: 30, text: "Moreover whom he did predestinate, them he also called: and whom he called, them he also justified.")
        ]
        var view = Self(source: .sermonText(
            passageOsis: "Rom.8.28-Rom.8.30", weekday: "Wednesday", dayIndex: 3,
            daysInWeek: 6, notesKeyPoint: "Every link in the chain is God’s."
        ))
        view.fixtureStart = ["verse": 1, "notes": 4, "end": 5][scene] ?? 0
        switch scene {
        case "loading": view._passage = State(initialValue: .loading)
        case "error": view._passage = State(initialValue: .unavailable)
        default:
            view._passage = State(initialValue: .verses(verses))
        }
        return view
    }
    #endif
}
