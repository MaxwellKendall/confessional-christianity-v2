// A simple wrapping flow layout (word-by-word), used to reflow the question
// answer as natural prose while keeping each footnote clause independently
// tappable — mirrors QuestionCard.tsx's inline clickable clause spans.
import SwiftUI
import DomainKit

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + verticalSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        y += lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                y += lineHeight + verticalSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Renders `prefix` (e.g. "A. ") followed by tappable, word-wrapped clause
/// segments. The active clause (whichever footnote marker is currently
/// selected) is highlighted in ochre; every other clause reads muted —
/// exactly QuestionCard.tsx's inline citation-switcher.
struct FlowText: View {
    let prefix: String
    let segments: [TextSegment]
    let activeMarker: String?
    let onTapMarker: (String) -> Void

    private struct Word: Identifiable {
        let id: Int
        let text: String
        let marker: String?
        let isLastInSegment: Bool
    }

    private var words: [Word] {
        var result: [Word] = []
        var counter = 0
        for segment in segments {
            let parts = segment.text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            for (i, part) in parts.enumerated() {
                result.append(Word(id: counter, text: part, marker: segment.marker, isLastInSegment: i == parts.count - 1))
                counter += 1
            }
        }
        return result
    }

    var body: some View {
        FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
            wordView(Word(id: -1, text: prefix.trimmingCharacters(in: .whitespaces), marker: nil, isLastInSegment: false))
            ForEach(words) { word in
                wordView(word)
            }
        }
    }

    @ViewBuilder
    private func wordView(_ word: Word) -> some View {
        let isActive = word.marker != nil && word.marker == activeMarker
        let color: Color = word.marker == nil ? .ccInk : (isActive ? .ccInk : .ccInk3)

        HStack(alignment: .top, spacing: 1) {
            Text(word.text)
            if word.isLastInSegment, let marker = word.marker {
                Text(marker)
                    .font(.ccDisplay(10))
                    .foregroundStyle(.ccOchre)
                    .baselineOffset(7)
            }
        }
        .font(.ccBody(18))
        .italic()
        .foregroundStyle(color)
        .padding(.horizontal, isActive ? 3 : 0)
        .background(isActive ? Color.ccOchre.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(alignment: .bottom) {
            if word.marker != nil {
                Rectangle()
                    .fill(isActive ? Color.ccOchre : Color.ccInk3)
                    .frame(height: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let marker = word.marker { onTapMarker(marker) }
        }
    }
}
