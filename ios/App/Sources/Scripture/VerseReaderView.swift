import SwiftUI
import DomainKit

struct VerseReaderView: View {
    private enum Passage {
        case loading
        case verses([ReaderVerse])
        case bundled(String)
        case unavailable
    }

    private struct CitationSelection: Identifiable {
        let id: String
        let text: String
        let reference: String
        let entries: [ScriptureCitingEntry]
        var initialClause: ScriptureCitingEntry? = nil
    }

    let source: ReaderSource

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var settings = ReaderSettings.load()
    @State private var passage = Passage.loading
    @State private var attempt = 0
    @State private var showsSettings = false
    @State private var citation: CitationSelection?
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

    private var passageReference: String { parseOsisBibleReference(osis) }
    private var headerTitle: String { readerHeaderTitle(for: source) }
    private var dark: Bool { readerEffectiveDark(settings: settings, systemIsDark: colorScheme == .dark) }
    private var paper: Palette { palette(.paper) }

    private func palette(_ token: ChapelPalette) -> Palette {
        dark ? token.dark : token.light
    }
    private var gilt: Color { Color(hex: dark ? 0xd3a654 : 0xa67a2c) }
    private var chapel: Color { Color(hex: dark ? 0xa8c6b6 : 0x2e4a3e) }
    private var onChapel: Color { Color(hex: dark ? 0x102019 : 0xf2f4ef) }
    private var surfaceFill: Color { Color(hex: dark ? 0x1a1e1b : 0xfcfcfa).opacity(0.75) }

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
                            VStack(spacing: 28) {
                                verse(text, reference: passageReference, palette: paper)
                                HStack(spacing: 34) {
                                    confessionsSeal(osis: osis, text: text, reference: passageReference, color: gilt)
                                    ShareLink(item: "\(text)\n— \(passageReference)") {
                                        actionLabel("Share", icon: "square.and.arrow.up")
                                    }
                                }
                            }
                        } footer: { copyright(palette: paper) }
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
            ReaderChapterView(chapterOSIS: chapter, passageOSIS: osis, settings: $settings)
        }
        .sheet(isPresented: $showsSettings) {
            ReaderSettingsSheet(settings: $settings)
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        .onChange(of: settings) { _, new in new.save() }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.bool(forKey: "ReaderSettingsSheet") { showsSettings = true }
            if UserDefaults.standard.bool(forKey: "ReaderConfessionsSheet")
                || UserDefaults.standard.bool(forKey: "ReaderConfessionsClause") {
                openFixtureConfessions(openClause: UserDefaults.standard.bool(forKey: "ReaderConfessionsClause"))
            }
        }
        #endif
        .sheet(item: $citation) { selection in
            ReaderConfessionsSheet(
                verseText: selection.text, reference: selection.reference, entries: selection.entries,
                paper: paper.paper, ink: paper.ink, gilt: gilt, chapel: chapel, onChapel: onChapel,
                initialClause: selection.initialClause
            )
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
            let start = ["verse": 1, "notes": max(0, pages.count - 2), "end": pages.count - 1][card] ?? 0
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(surfaceFill, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            Text(headerTitle)
                .font(.ccDisplay(13))
                .tracking(1.04)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(surfaceFill, in: Capsule())
            Spacer()
            Button { showsSettings = true } label: {
                Text("Aa")
                    .font(.ccUI(16, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(surfaceFill, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Reading settings")
        }
        .buttonStyle(.plain)
        .foregroundStyle(paper.ink)
        .environment(\.colorScheme, dark ? .dark : .light)
        .padding(.horizontal, 14)
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
                Text("Swipe up")
                    .font(.ccUI(11))
                    .tracking(0.55)
                    .foregroundStyle(palette.ink.opacity(0.55))
                    .padding(.bottom, 16)
            }
        case let .verse(item):
            let paletteIndex = index % ChapelPalette.rotating.count
            let palette = palette(ChapelPalette.rotating[paletteIndex])
            let sealColor = paletteIndex == 3 && !dark ? Color(hex: 0xd9b46a) : gilt
            let reference = parseOsisBibleReference(item.osis)
            screen(palette, top, bottom) {
                verse(item.text, reference: reference, palette: palette)
            } footer: {
                verseActions(item, reference: reference, sealColor: sealColor)
            }
        case let .notes(note):
            let palette = palette(.parchment)
            screen(palette, top, bottom) {
                VStack(spacing: 16) {
                    kicker("From your notes · Sunday", palette: palette)
                    Text(readerQuoted(note)).chapelReading(size: 26, lineHeight: 1.25)
                }
            } footer: {
                ShareLink(item: note) { actionLabel("Share", icon: "square.and.arrow.up") }
            }
        case .end:
            let paletteIndex = index % ChapelPalette.rotating.count
            let palette = palette(ChapelPalette.rotating[paletteIndex])
            screen(palette, top, bottom) {
                end(palette: palette, onChapelCard: paletteIndex == 3)
            } footer: { copyright(palette: palette) }
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
        .padding(.horizontal, 34)
        .padding(.top, top + 54)
        .padding(.bottom, bottom + 14)
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
        VStack(spacing: 12) {
            switch source {
            case let .sermonText(_, weekday, dayIndex, daysInWeek, _):
                kicker("This week’s sermon text · \(weekday)", palette: palette)
                Text(passageReference)
                    .chapelReading(size: 30, lineHeight: 1.25)
                    .padding(.top, 4)
                Text("\(verseCount) \(verseCount == 1 ? "verse" : "verses"). Read slowly, then swipe up.")
                    .font(.ccUI(14))
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: 270)
                HStack(spacing: 8) {
                    ForEach(0..<max(0, daysInWeek), id: \.self) { day in
                        Circle().strokeBorder(palette.secondary)
                            .background(day < dayIndex ? palette.secondary : .clear, in: Circle())
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 6)
                .accessibilityLabel("Day \(dayIndex) of \(daysInWeek)")
                .accessibilityElement(children: .ignore)
            case let .proofText(slug, number, question, _, _):
                kicker(catechismLabel(slug, number: number), palette: palette)
                Text(question)
                    .chapelReading(size: 24, lineHeight: 1.25)
                    .padding(.top, 4)
                Text("The proof text. Read it aloud, slowly.")
                    .font(.ccUI(14))
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: 280)
            }
        }
    }

    private func catechismLabel(_ slug: String, number: Int) -> String {
        "\(readerCatechismName(for: slug)) · Q. \(number)"
    }

    private func verse(_ text: String, reference: String, palette: Palette) -> some View {
        let size = readerVerseFontSize(textLength: text.count, textSize: settings.textSize)
        return VStack(spacing: 28) {
            Text(text)
                .font(.ccBody(size))
                .lineSpacing(size * (1.42 - 1.254))
                .minimumScaleFactor(0.55)
                .frame(maxWidth: 310)
            Text(reference.uppercased())
                .font(.ccDisplay(12))
                .tracking(2.64)
                .foregroundStyle(palette.secondary)
        }
    }

    private func verseActions(_ verse: ReaderVerse, reference: String, sealColor: Color) -> some View {
        HStack(spacing: 34) {
            confessionsSeal(osis: verse.osis, text: verse.text, reference: reference, color: sealColor)
            if let chapter = ReaderChapter.chapterOSIS(for: verse.osis) {
                Button { contextChapter = chapter } label: {
                    actionLabel("In context", icon: "text.alignleft")
                }
            }
            ShareLink(item: "\(verse.text)\n— \(reference)") { actionLabel("Share", icon: "square.and.arrow.up") }
        }
    }

    @ViewBuilder
    private func confessionsSeal(osis: String, text: String, reference: String, color: Color) -> some View {
        let entries = readerVisibleCitations(forVerse: osis, settings: settings)
        if !entries.isEmpty {
            Button {
                citation = CitationSelection(id: osis, text: text, reference: reference, entries: entries)
            } label: {
                VStack(spacing: 5) {
                    Text("\(entries.count)")
                        .font(.ccDisplay(12, semibold: true))
                        .frame(width: 30, height: 30)
                        .overlay { Circle().strokeBorder(lineWidth: 1.5) }
                    Text("Confessions")
                        .font(.ccUI(10))
                        .tracking(0.4)
                }
                .foregroundStyle(color)
                .frame(minWidth: 44, minHeight: 48)
            }
            .accessibilityLabel("Confessions, \(entries.count) \(entries.count == 1 ? "citation" : "citations")")
        }
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .frame(height: 30)
            Text(title)
                .font(.ccUI(10))
                .tracking(0.4)
        }
        .opacity(0.8)
        .frame(minWidth: 44, minHeight: 48)
    }

    private func kicker(_ title: String, palette: Palette) -> some View {
        Text(title.uppercased())
            .font(.ccDisplay(11))
            .tracking(2.64)
            .foregroundStyle(palette.secondary)
    }

    private func end(palette: Palette, onChapelCard: Bool) -> some View {
        VStack(spacing: 12) {
            switch source {
            case let .sermonText(_, _, dayIndex, daysInWeek, _):
                kicker("This week’s sermon text", palette: palette)
                Text("That’s the passage.")
                    .chapelReading(size: 30, lineHeight: 1.25)
                    .padding(.top, 4)
                Text("Day \(dayIndex) of \(daysInWeek) · come back tomorrow and sit with it again.")
                    .font(.ccUI(14))
                    .foregroundStyle(palette.secondary)
                VStack(spacing: 10) {
                    primaryButton("Done for today", onChapelCard: onChapelCard) { dismiss() }
                    if let chapter = ReaderChapter.chapterOSIS(for: osis) {
                        Button { contextChapter = chapter } label: {
                            Text("Read all of \(parseOsisBibleReference(chapter))")
                                .font(.ccUI(15, weight: .medium))
                                .padding(.horizontal, 22)
                                .frame(minHeight: 44)
                                .overlay { Capsule().strokeBorder(palette.ink.opacity(0.8)) }
                        }
                    }
                }
                .padding(.top, 14)
            case let .proofText(slug, number, _, answer, _):
                kicker(catechismLabel(slug, number: number), palette: palette)
                Text("Now say the answer together.")
                    .chapelReading(size: 30, lineHeight: 1.25)
                    .padding(.top, 4)
                Text(readerQuoted(answer))
                    .font(.ccUI(14))
                    .lineSpacing(3)
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: 280)
                primaryButton("Back to Q. \(number)", onChapelCard: onChapelCard) { dismiss() }
                    .padding(.top, 14)
            }
        }
    }

    private func primaryButton(_ title: String, onChapelCard: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ccUI(15, weight: .semibold))
                .padding(.horizontal, 22)
                .frame(minHeight: 44)
                .background(onChapelCard ? onChapel : chapel, in: Capsule())
                .foregroundStyle(onChapelCard ? Color(hex: 0x2e4a3e) : onChapel)
        }
    }

    private func copyright(palette: Palette) -> some View {
        Text(EsvClient.copyrightNotice)
            .font(.ccUI(10))
            .foregroundStyle(palette.secondary)
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
            Text(passageReference.uppercased())
                .font(.ccDisplay(12))
                .tracking(2.64)
                .foregroundStyle(paper.secondary)
                .padding(.top, 14)
            Text("Loading passage")
                .font(.ccUI(12))
                .foregroundStyle(paper.secondary)
                .padding(.top, 16)
        }
    }

    private var offline: some View {
        let offlineCitations = readerVisibleCitations(forPassage: osis, settings: settings)
        let firstRef = String(osis.prefix { $0 != "-" && $0 != "," }).trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color(hex: dark ? 0xec8a7c : 0x9b3328))
            Text("The text can’t load right now.")
                .chapelReading(size: 24, lineHeight: 1.25)
                .padding(.top, 4)
            Text("You’re offline. Your sermon notes and the confessions are saved on this phone.")
                .font(.ccUI(14))
                .lineSpacing(3)
                .foregroundStyle(paper.secondary)
                .frame(maxWidth: 280)
            VStack(spacing: 10) {
                primaryButton("Try again") { attempt += 1 }
                if !offlineCitations.isEmpty {
                    Button {
                        citation = CitationSelection(
                            id: firstRef,
                            text: bundledEsvText(for: firstRef) ?? "",
                            reference: parseOsisBibleReference(firstRef),
                            entries: offlineCitations
                        )
                    } label: {
                        Text("What the confessions say")
                            .font(.ccUI(15, weight: .medium))
                            .padding(.horizontal, 22)
                            .frame(minHeight: 44)
                            .overlay { Capsule().strokeBorder(paper.ink.opacity(0.75)) }
                    }
                }
            }
            .padding(.top, 14)
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
    private func openFixtureConfessions(openClause: Bool) {
        guard case let .verses(verses) = passage, let first = verses.first else { return }
        let entries = citingEntries(forVerse: first.osis)
        guard !entries.isEmpty else { return }
        citation = CitationSelection(
            id: first.osis,
            text: first.text,
            reference: parseOsisBibleReference(first.osis),
            entries: entries,
            initialClause: openClause ? entries.first : nil
        )
    }

    static func fixture(_ scene: String) -> Self {
        if scene == "bundled-citations" {
            let osis = "Prov.31.23"
            return Self(source: .sermonText(
                passageOsis: osis, weekday: "Wednesday", dayIndex: 3, daysInWeek: 6, notesKeyPoint: nil
            ))
        }

        if scene == "long" {
            let verse = ReaderVerse(
                osis: "Rom.8.11",
                verse: 11,
                text: "If the Spirit of him who raised Jesus from the dead dwells in you, he who raised Christ Jesus from the dead will also give life to your mortal bodies through his Spirit who dwells in you."
            )
            var view = Self(source: .sermonText(
                passageOsis: verse.osis, weekday: "Wednesday", dayIndex: 3, daysInWeek: 6, notesKeyPoint: nil
            ))
            view.fixtureStart = 1
            view._passage = State(initialValue: .verses([verse]))
            return view
        }

        if scene == "citations" || scene == "uncited" {
            let cited = scene == "citations"
            let verse = cited
                ? ReaderVerse(osis: "Rom.8.16", verse: 16, text: "The Spirit himself bears witness with our spirit that we are children of God,")
                : ReaderVerse(osis: "Rom.16.24", verse: 24, text: "The grace of our Lord Jesus Christ be with you all. Amen.")
            var view = Self(source: .sermonText(
                passageOsis: verse.osis, weekday: "Wednesday", dayIndex: 3, daysInWeek: 6, notesKeyPoint: nil
            ))
            view.fixtureStart = 1
            view._passage = State(initialValue: .verses([verse]))
            return view
        }

        let verses = [
            ReaderVerse(osis: "Rom.8.28", verse: 28, text: "And we know that for those who love God all things work together for good, for those who are called according to his purpose."),
            ReaderVerse(osis: "Rom.8.29", verse: 29, text: "For those whom he foreknew he also predestined to be conformed to the image of his Son, in order that he might be the firstborn among many brothers."),
            ReaderVerse(osis: "Rom.8.30", verse: 30, text: "And those whom he predestined he also called, and those whom he called he also justified, and those whom he justified he also glorified.")
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
