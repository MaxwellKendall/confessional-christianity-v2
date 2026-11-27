import SwiftUI
import UIKit
import DomainKit

struct ReaderChapterView: View {
    let chapterOSIS: String
    let passageOSIS: String
    @Binding var settings: ReaderSettings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var chapter: ReaderChapter?
    @State private var isLoading = true
    @State private var attempt = 0
    @State private var citation: Citation?
    @State private var showsSettings = false

    private var title: String { parseOsisBibleReference(chapterOSIS) }
    private var dark: Bool { readerEffectiveDark(settings: settings, systemIsDark: colorScheme == .dark) }
    private var ink: Color { Color(hex: dark ? 0xebece6 : 0x1c1f1c) }
    private var ink3: Color { Color(hex: dark ? 0x7d847c : 0x858b83) }
    private var gilt: Color { Color(hex: dark ? 0xd3a654 : 0xa67a2c) }
    private var paper: Color { Color(hex: dark ? 0x121513 : 0xf5f5f1) }
    private var surface: Color { Color(hex: dark ? 0x1a1e1b : 0xfcfcfa) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title.uppercased())
                    .font(.ccDisplay(20))
                    .tracking(2.8)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                if let chapter {
                    ChapterText(chapter: chapter, passageOSIS: passageOSIS, settings: settings,
                                ink: UIColor(ink), ink3: UIColor(ink3), gilt: UIColor(gilt)) { verse in
                        citation = Citation(osis: verse)
                    }
                    Text(EsvClient.copyrightNotice)
                        .font(.ccUI(11))
                        .foregroundStyle(ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else if isLoading {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach([1.0, 0.96, 0.91, 0.98, 0.59, 0.94, 0.90, 0.45], id: \.self) { fraction in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: dark ? 0x232823 : 0xecede7))
                                .containerRelativeFrame(.horizontal) { width, _ in max(0, width - 60) * fraction }
                                .frame(height: 16)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading chapter")
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.ccDanger)
                            .accessibilityHidden(true)
                        Text("This chapter isn’t saved on this phone.")
                            .font(.ccUI(15))
                            .foregroundStyle(.ccInk2)
                        Button { attempt += 1 } label: {
                            Text("Try again")
                                .font(.ccUI(15, weight: .semibold))
                                .padding(.horizontal, 22)
                                .frame(minHeight: 44)
                                .background(.ccChapel, in: Capsule())
                                .foregroundStyle(.ccOnChapel)
                        }
                        .buttonStyle(.plain)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 25)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 8)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(paper.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(surface.opacity(0.75), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("chapter-back")
                Spacer()
                Text(title)
                    .font(.ccDisplay(13))
                    .tracking(1.04)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(surface.opacity(0.75), in: Capsule())
                Spacer()
                Button { showsSettings = true } label: {
                    Text("Aa")
                        .font(.ccUI(16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(surface.opacity(0.75), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reading settings")
                .accessibilityIdentifier("chapter-settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .foregroundStyle(ink)
            .background(paper.opacity(0.92))
        }
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .environment(\.colorScheme, dark ? .dark : .light)
        .onChange(of: settings) { _, new in new.save() }
        .sheet(isPresented: $showsSettings) {
            ReaderSettingsSheet(settings: $settings)
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        .sheet(item: $citation) { selection in
            ReaderConfessionsSheet(
                verseText: verseText(selection.osis), reference: parseOsisBibleReference(selection.osis),
                entries: citingEntries(forVerse: selection.osis),
                paper: paper, ink: ink, gilt: gilt,
                chapel: Color(hex: dark ? 0xa8c6b6 : 0x2e4a3e), onChapel: Color(hex: dark ? 0x102019 : 0xf2f4ef)
            )
            .environment(\.colorScheme, dark ? .dark : .light)
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.bool(forKey: "ReaderSettingsSheet") { showsSettings = true }
        }
        #endif
        .task(id: attempt) {
            isLoading = true
            let result = await EsvClient.shared.chapter(for: chapterOSIS)
            guard !Task.isCancelled else { return }
            chapter = result
            isLoading = false
        }
    }

    /// The tapped verse's words from the loaded chapter, for the sheet's "You came from" line.
    private func verseText(_ osis: String) -> String {
        guard let chapter, let verse = chapter.verses.first(where: { $0.osis == osis }) else { return "" }
        return (chapter.text as NSString).substring(with: verse.range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Citation: Identifiable {
        let osis: String
        var id: String { osis }
    }
}

#if DEBUG
/// `-ReaderChapterReference`: the chapter view on its own, with saved settings
/// (`-ReaderSettingsSheet YES` opens the reading sheet on top).
struct ReaderChapterFixture: View {
    let chapterOSIS: String
    let passageOSIS: String
    @State private var settings = ReaderSettings.load()

    var body: some View {
        NavigationStack {
            ReaderChapterView(chapterOSIS: chapterOSIS, passageOSIS: passageOSIS, settings: $settings)
        }
        .onChange(of: settings) { _, new in new.save() }
    }
}
#endif

private struct ChapterText: UIViewRepresentable {
    let chapter: ReaderChapter
    let passageOSIS: String
    let settings: ReaderSettings
    let ink: UIColor
    let ink3: UIColor
    let gilt: UIColor
    let openCitation: (String) -> Void

    /// Dynamic Type scale: 20 at the default size, so the design's steps hold.
    @ScaledMetric(relativeTo: .body) private var baseSize = 20.0

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.openCitation = openCitation
        // Empty attributes keep each character's own foreground colour inside
        // link ranges so verse text stays ink while the trailing • mark stays gilt.
        view.linkTextAttributes = [:]
        view.attributedText = formattedText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator { Coordinator(openCitation: openCitation) }

    private func formattedText() -> NSAttributedString {
        let size = readerChapterFontSize(textSize: settings.textSize) * baseSize / 20
        let font = UIFont(name: "Marcellus-Regular", size: size) ?? .systemFont(ofSize: size)
        let body: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let verseNumber: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size * 0.55),
            .baselineOffset: size * 0.35,
            .foregroundColor: ink3,
        ]
        let citationMark: [NSAttributedString.Key: Any] = [
            .font: font.withSize(size * 0.6),
            .baselineOffset: size * 0.38,
            .foregroundColor: gilt,
        ]
        let output = NSMutableAttributedString(string: chapter.text, attributes: body)
        for verse in chapter.verses.reversed() {
            if ReaderChapter.contains(verse.osis, in: passageOSIS) {
                output.addAttributes([
                    .backgroundColor: gilt.withAlphaComponent(0.16),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: gilt,
                ], range: verse.range)
            }
            if !readerVisibleCitations(forVerse: verse.osis, settings: settings).isEmpty,
               let url = URL(string: "chapter-citation:\(verse.osis)") {
                let end = NSMaxRange(verse.range)
                let mark = NSAttributedString(string: "\u{2009}•", attributes: citationMark)
                output.insert(mark, at: end)
                output.addAttribute(.link, value: url, range: NSRange(
                    location: verse.range.location, length: verse.range.length + mark.length
                ))
            }
            if settings.showVerseNumbers {
                output.insert(NSAttributedString(string: "\(verse.number)\u{2009}", attributes: verseNumber),
                              at: verse.range.location)
            }
        }

        let lines = output.string as NSString
        var paragraphs: [(NSRange, Int)] = []
        lines.enumerateSubstrings(in: NSRange(location: 0, length: lines.length), options: .byLines) {
            line, _, enclosing, _ in
            paragraphs.append((enclosing, line?.prefix { $0 == " " }.count ?? 0))
        }
        for (range, spaces) in paragraphs.reversed() {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = size * (1.7 - 1.254)
            style.firstLineHeadIndent = CGFloat(spaces) * size * 0.24
            style.headIndent = style.firstLineHeadIndent + (spaces > 0 ? size : 0)
            output.addAttribute(.paragraphStyle, value: style, range: range)
            output.deleteCharacters(in: NSRange(location: range.location, length: spaces))
        }
        return output
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var openCitation: (String) -> Void

        init(openCitation: @escaping (String) -> Void) {
            self.openCitation = openCitation
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            guard case let .link(url) = textItem.content, url.scheme == "chapter-citation" else { return nil }
            let osis = String(url.absoluteString.dropFirst("chapter-citation:".count))
            return UIAction { [weak self] _ in self?.openCitation(osis) }
        }
    }
}
