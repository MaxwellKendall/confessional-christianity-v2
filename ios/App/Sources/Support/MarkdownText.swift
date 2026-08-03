// A small block-level markdown renderer for reflections' authored essays —
// headings, blockquotes, bullet lists, and paragraphs, with inline
// bold/italic handled by AttributedString(markdown:). Mirrors the web's
// reading-prose treatment (src/components/Markdown.tsx + globals.css)
// without a full CommonMark implementation, since the authored content only
// uses this small subset (see content/commentary/*.md).
import SwiftUI

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case blockquote(String)
    case list([String])
    case paragraph(String)
}

private func parseMarkdownBlocks(_ source: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraphLines: [String] = []
    var listItems: [String] = []

    func flushParagraph() {
        guard !paragraphLines.isEmpty else { return }
        blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        paragraphLines = []
    }
    func flushList() {
        guard !listItems.isEmpty else { return }
        blocks.append(.list(listItems))
        listItems = []
    }

    for rawLine in source.components(separatedBy: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            flushParagraph()
            flushList()
        } else if line.hasPrefix("### ") {
            flushParagraph(); flushList()
            blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
        } else if line.hasPrefix("## ") {
            flushParagraph(); flushList()
            blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
        } else if line.hasPrefix("# ") {
            flushParagraph(); flushList()
            blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
        } else if line.hasPrefix("> ") {
            flushParagraph(); flushList()
            blocks.append(.blockquote(String(line.dropFirst(2))))
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            flushParagraph()
            listItems.append(String(line.dropFirst(2)))
        } else {
            flushList()
            paragraphLines.append(line)
        }
    }
    flushParagraph()
    flushList()
    return blocks
}

private func inline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(parseMarkdownBlocks(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.ccDisplay(level <= 2 ? 15 : 13.5, semibold: true))
                .foregroundStyle(.ccInk)
                .fixedSize(horizontal: false, vertical: true)
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(Color.ccMuted).frame(width: 2)
                Text(inline(text))
                    .font(.ccBody(14.5))
                    .italic()
                    .foregroundStyle(.ccInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\u{2022}").font(.ccBody(14)).foregroundStyle(.ccInk3)
                        Text(inline(item))
                            .font(.ccBody(14.5))
                            .foregroundStyle(.ccInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .paragraph(let text):
            Text(inline(text))
                .font(.ccBody(15))
                .foregroundStyle(.ccInk)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
