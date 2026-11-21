import SwiftUI
import UIKit
import DomainKit

struct ReaderChapterView: View {
    let chapterOSIS: String
    let passageOSIS: String
    let settings: ReaderSettings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var chapter: ReaderChapter?
    @State private var isLoading = true
    @State private var attempt = 0
    @State private var citation: Citation?

    private var title: String { parseOsisBibleReference(chapterOSIS) }
    private var dark: Bool { settings.dark || colorScheme == .dark }
    private var ink: Color { Color(hex: dark ? 0xebece6 : 0x1c1f1c) }
    private var gilt: Color { Color(hex: dark ? 0xd3a654 : 0x936b26) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(title)
                    .font(.ccDisplay(22, semibold: true))
                    .accessibilityAddTraits(.isHeader)
                if let chapter {
                    ChapterText(chapter: chapter, passageOSIS: passageOSIS, settings: settings,
                                ink: UIColor(ink), gilt: UIColor(gilt)) { verse in
                        citation = Citation(osis: verse)
                    }
                    Text(EsvClient.copyrightNotice)
                        .font(.caption2)
                        .foregroundStyle(ink.opacity(0.75))
                } else if isLoading {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach([1.0, 0.96, 0.91, 0.98, 0.59, 0.94, 0.90, 0.45], id: \.self) { fraction in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ink.opacity(0.08))
                                .containerRelativeFrame(.horizontal) { width, _ in max(0, width - 44) * fraction }
                                .frame(height: 16)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading chapter")
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: "wifi.slash").font(.title).accessibilityHidden(true)
                        Text("This chapter isn't saved on this phone")
                            .font(.ccBody(20))
                        Button("Try again") { attempt += 1 }
                            .buttonStyle(.bordered)
                            .tint(gilt)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 25)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(Color(hex: dark ? 0x121513 : 0xf5f5f1).ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("chapter-back")
                Spacer()
                Text(title)
                    .font(.ccDisplay(13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                Spacer()
                Color.clear.frame(width: 44, height: 1).accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .foregroundStyle(ink)
            .background(.regularMaterial)
        }
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .environment(\.colorScheme, dark ? .dark : .light)
        .sheet(item: $citation) { selection in
            VStack(spacing: 12) {
                Text("Cited in the Confessions").font(.ccDisplay(19, semibold: true))
                Text(parseOsisBibleReference(selection.osis)).font(.ccBody(18))
                Button("Done") { citation = nil }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .task(id: attempt) {
            isLoading = true
            let result = await EsvClient.shared.chapter(for: chapterOSIS)
            guard !Task.isCancelled else { return }
            chapter = result
            isLoading = false
        }
    }

    private struct Citation: Identifiable {
        let osis: String
        var id: String { osis }
    }
}

private struct ChapterText: UIViewRepresentable {
    let chapter: ReaderChapter
    let passageOSIS: String
    let settings: ReaderSettings
    let ink: UIColor
    let gilt: UIColor
    let openCitation: (String) -> Void

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
        view.linkTextAttributes = [.foregroundColor: ink]
        view.attributedText = formattedText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator { Coordinator(openCitation: openCitation) }

    private func formattedText() -> NSAttributedString {
        let size = baseSize + Double(settings.textSize - ReaderSettings.defaultTextSize) * 2
        let font = UIFont(name: "Marcellus-Regular", size: size) ?? .systemFont(ofSize: size)
        let body: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let superscript: [NSAttributedString.Key: Any] = [
            .font: font.withSize(size * 0.65), .baselineOffset: size * 0.31, .foregroundColor: gilt
        ]
        let output = NSMutableAttributedString(string: chapter.text, attributes: body)
        for verse in chapter.verses.reversed() {
            if ReaderChapter.contains(verse.osis, in: passageOSIS) {
                output.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: gilt
                ], range: verse.range)
            }
            if settings.showConfessionMarks, !citingEntries(forVerse: verse.osis).isEmpty,
               let url = URL(string: "chapter-citation:\(verse.osis)") {
                let end = NSMaxRange(verse.range)
                let mark = NSAttributedString(string: "\u{00a0}•", attributes: superscript)
                output.insert(mark, at: end)
                output.addAttribute(.link, value: url, range: NSRange(
                    location: verse.range.location, length: verse.range.length + mark.length
                ))
            }
            if settings.showVerseNumbers {
                output.insert(NSAttributedString(string: "\(verse.number)\u{00a0}", attributes: superscript),
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
            style.lineSpacing = 5
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
