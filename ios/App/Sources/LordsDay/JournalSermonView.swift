// One sermon in the journal (TKL-944): the summary face (date, passage,
// title, key lines from its kept cards) with the week's cards in a strip.
// Previous and next walk the list as filtered when it was opened, so you never
// lose your place. Read-only; the fair copy face is TKL-1058.
import SwiftUI
import SwiftData
import DomainKit

struct JournalSermonView: View {
    let journal: LordsDayJournal
    /// Newest first: the journal's filtered list when the sermon was opened.
    let list: [UUID]
    let whereLabel: String
    let query: String
    @State var current: UUID
    var onDetailsUpdated: () -> Void = {}
    @State private var editingNote: LordsDayNote?
    @Environment(\.modelContext) private var context
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var entries: [JournalEntry] { list.compactMap(journal.entry(id:)) }

    var body: some View {
        let entries = entries
        let index = entries.firstIndex { $0.id == current } ?? 0
        VStack(spacing: 0) {
            topBar(position: index + 1, of: entries.count)
            if entries.indices.contains(index) {
                ScrollView {
                    page(entries[index])
                        .padding(.horizontal, ChapelSpace.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .id(current)
                bottomBar(entries: entries, index: index)
            }
        }
        .background(Color.ccPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesFloatingTabBar()
        .sheet(item: $editingNote) { note in
            EditSermonDetailsSheet(initial: SermonDetailsEdit(note: note)) { edit in
                try sync.lordsDayStore(in: context).updateDetails(edit, for: note)
                onDetailsUpdated()
            }
        }
    }

    private func topBar(position: Int, of count: Int) -> some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Text("Journal").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.ccChapel)
            }
            .accessibilityIdentifier("journal.sermon.back")
            Text("\(whereLabel) · \(position) of \(count)")
                .font(.system(size: 12))
                .foregroundStyle(Color.ccInk3)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("journal.sermon.where")
            Button {
                if let note = try? sync.lordsDayStore(in: context).note(id: current) {
                    editingNote = note
                }
            } label: {
                Text("Edit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ccChapel)
            }
            .frame(minWidth: 70, alignment: .trailing)
            .accessibilityLabel("Edit sermon details")
            .accessibilityIdentifier("journal.sermon.editDetails")
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder private func page(_ entry: JournalEntry) -> some View {
        summary(entry)
        Text("\(entry.cards.count) card\(entry.cards.count == 1 ? "" : "s") from this Lord's Day")
            .chapelCaps()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16).padding(.bottom, 8)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(entry.cards.enumerated()), id: \.offset) { i, card in
                    JournalMiniCard(card: card, palette: LordsDayFeed.palette(card.palette(at: i), dark: scheme == .dark), passage: entry.passage)
                }
            }
            .padding(.horizontal, ChapelSpace.gutter)
        }
        .padding(.horizontal, -ChapelSpace.gutter)
        .accessibilityIdentifier("journal.sermon.strip")
        let again = journal.entries.filter { $0.id != entry.id && $0.bookIndex != nil && $0.bookIndex == entry.bookIndex && $0.chapter == entry.chapter }
        ForEach(again.prefix(2)) { other in
            Button { current = other.id } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also preached").font(.ccDisplay(9.5)).tracking(1.3).textCase(.uppercase).foregroundStyle(Color.ccGilt)
                    Text("\(other.passage ?? "") on \(other.serviceDate.journalDate)\(other.title.map { ": \($0)" } ?? "")")
                        .font(.system(size: 13.5)).foregroundStyle(Color.ccInk).multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 13).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ccFill, in: RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .disabled(!list.contains(other.id) && !journal.entries.contains { $0.id == other.id })
        }
    }

    private func summary(_ entry: JournalEntry) -> some View {
        let band = LordsDayFeed.palette(entry.cards.first?.palette(at: 0) ?? LordsDayFeed.rotation[0], dark: scheme == .dark)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(entry.serviceDate.journalDate) · The Lord's Day").chapelCaps()
            // Named by the sermon (TKL-1061): title, else passage, else the date.
            let heading = SermonHeading(title: entry.title, passage: entry.passage, preacher: entry.preacher, date: entry.serviceDate.journalDate)
            Text(heading.headline).font(.ccDisplay(21, semibold: true)).foregroundStyle(Color.ccInk).padding(.top, 6)
                .accessibilityIdentifier("journal.sermon.passage")
            if let byline = heading.byline {
                Text(byline).font(.ccBody(17)).foregroundStyle(Color.ccInk2).padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entry.keyLines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(i + 1)").font(.ccDisplay(12)).foregroundStyle(Color.ccGilt).frame(width: 24, alignment: .leading)
                        Text(highlighted(line)).font(.ccBody(14.5)).lineSpacing(3).foregroundStyle(Color.ccInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Color.ccLine).frame(height: 1) }
                }
            }
            .padding(.top, 14)
            if let verse = entry.keyVerse {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verse.bundledVerseText ?? verse.reference ?? "").font(.ccBody(16)).lineSpacing(3).foregroundStyle(Color.ccInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if verse.bundledVerseText != nil, let ref = verse.reference { Text(ref).chapelCaps() }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 14)
            }
            if !entry.references.isEmpty {
                Text(entry.references.joined(separator: " · "))
                    .font(.system(size: 12.5)).foregroundStyle(Color.ccChapel)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 18).padding(.top, 25).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ccSurface)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: band.field)).frame(height: 5) }
        .clipShape(RoundedRectangle(cornerRadius: ChapelRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ChapelRadius.sheet, style: .continuous).strokeBorder(Color.ccLine))
        .accessibilityIdentifier("journal.sermon.summary")
    }

    private func bottomBar(entries: [JournalEntry], index: Int) -> some View {
        let earlier = entries.indices.contains(index + 1) ? entries[index + 1] : nil
        let later = index > 0 ? entries[index - 1] : nil
        return HStack(spacing: 8) {
            navButton("‹ \(earlier?.serviceDate.journalDate ?? "Earlier")", target: earlier, id: "earlier")
            navButton("\(later?.serviceDate.journalDate ?? "Later") ›", target: later, id: "later")
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 10).padding(.bottom, 10)
        .background(Color.ccPaper)
        .overlay(alignment: .top) { Rectangle().fill(Color.ccLine).frame(height: 1) }
    }

    private func navButton(_ label: String, target: JournalEntry?, id: String) -> some View {
        Button { if let target { current = target.id } } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ccInk)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.ccFill, in: RoundedRectangle(cornerRadius: ChapelRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .opacity(target == nil ? 0.35 : 1)
        .accessibilityIdentifier("journal.sermon.\(id)")
    }

    private func highlighted(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        for word in query.split(whereSeparator: \.isWhitespace) {
            var start = out.startIndex
            while start < out.endIndex, let range = out[start...].range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive]) {
                out[range].backgroundColor = Color.ccGilt.opacity(0.25)
                start = range.upperBound
            }
        }
        return out
    }
}

/// A kept card in miniature: the feed's palette, a drop cap, its source.
private struct JournalMiniCard: View {
    let card: JournalCard
    let palette: QuoteCardPalette
    let passage: String?

    var body: some View {
        let text = card.kind == .verse ? (card.bundledVerseText ?? card.reference ?? "") : card.body
        let label = card.kind == .verse ? (card.reference ?? "") : card.kind == .quote ? (card.attribution ?? passage ?? "") : (passage ?? "")
        VStack(alignment: .leading, spacing: 8) {
            (Text(String(text.prefix(1))).font(.ccDisplay(17)) + Text(String(text.dropFirst())).font(.ccBody(10.5)))
                .lineSpacing(1)
                .lineLimit(7)
            Text(label).font(.ccDisplay(6.5)).tracking(0.9).textCase(.uppercase).lineLimit(1)
        }
        .foregroundStyle(Color(hex: palette.ink))
        .padding(.horizontal, 10).padding(.vertical, 12)
        .frame(width: 118, height: 147.5, alignment: .leading)
        .background(Color(hex: palette.field), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(hex: palette.ink).opacity(0.2)).padding(4))
        .accessibilityElement(children: .combine)
    }
}
