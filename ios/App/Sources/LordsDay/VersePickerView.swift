// Picking the verse for a Verse card (TKL-863). A Verse card holds only a
// reference the user chose here, reading the real text from the app's Bible
// source, so no Scripture is ever generated or typed. Book, then chapter, then
// tap a verse (tap a second one in the same chapter to take a range).
import SwiftUI
import DomainKit

struct VersePickerView: View {
    /// Where to open: the card's verse, or the sermon's passage.
    let startOsis: String?
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                section("Old Testament", BIBLE_BOOKS.filter { $0.testament == "old" })
                section("New Testament", BIBLE_BOOKS.filter { $0.testament == "new" })
            }
            .navigationTitle("Pick the verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(for: String.self) { value in
                if let book = BIBLE_BOOKS.first(where: { $0.osis == value }) {
                    ChapterGrid(book: book) { path.append("\(book.osis).\($0)") }
                } else {
                    ChapterVerses(chapterOsis: value) { osis in
                        onPick(osis)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard path.isEmpty, let start = startOsis.flatMap(ReaderChapter.chapterOSIS(for:)) else { return }
            path = [String(start.prefix { $0 != "." }), start]
        }
    }

    private func section(_ title: String, _ books: [BibleBook]) -> some View {
        Section(title) {
            ForEach(books, id: \.osis) { book in
                NavigationLink(book.name, value: book.osis)
            }
        }
    }
}

private struct ChapterGrid: View {
    let book: BibleBook
    let open: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(1...book.chapters, id: \.self) { chapter in
                    Button { open(chapter) } label: {
                        Text("\(chapter)")
                            .font(.system(size: 17, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChapterVerses: View {
    let chapterOsis: String
    let pick: (String) -> Void

    @State private var verses: [ReaderVerse]?
    @State private var loaded = false
    @State private var attempt = 0
    @State private var first: ReaderVerse?
    @State private var last: ReaderVerse?

    private var selection: String? {
        guard let first else { return nil }
        guard let last, last.verse != first.verse else { return first.osis }
        let (a, b) = first.verse < last.verse ? (first, last) : (last, first)
        return "\(a.osis)-\(b.osis)"
    }

    var body: some View {
        Group {
            if let verses {
                List(verses, id: \.osis) { verse in
                    Button { tap(verse) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(verse.verse)")
                                .font(.ccDisplay(12))
                                .foregroundStyle(Color.ccGilt)
                                .frame(width: 26, alignment: .trailing)
                            Text(verse.text)
                                .font(.ccBody(17))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(isSelected(verse) ? Color.ccGilt.opacity(0.18) : nil)
                    .accessibilityAddTraits(isSelected(verse) ? .isSelected : [])
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .bottom) { footer }
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.slash").font(.title).accessibilityHidden(true)
                    Text("This chapter isn't saved on this phone").font(.ccBody(19)).multilineTextAlignment(.center)
                    Button("Try again") { attempt += 1 }.buttonStyle(.bordered)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(parseOsisBibleReference(chapterOsis))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) {
            loaded = false
            verses = await EsvClient.shared.verses(for: ReaderChapter.queryOSIS(for: chapterOsis))
            loaded = true
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button {
                if let selection { pick(selection) }
            } label: {
                Text(selection.map { "Use \(parseOsisBibleReference($0))" } ?? "Tap a verse")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color.ccOnChapel)
            }
            .disabled(selection == nil)
            .opacity(selection == nil ? 0.4 : 1)
            Text("Tap a second verse to take a range.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func tap(_ verse: ReaderVerse) {
        if first == nil || last != nil { first = verse; last = nil }
        else if verse.verse == first?.verse { first = nil }
        else { last = verse }
    }

    private func isSelected(_ verse: ReaderVerse) -> Bool {
        guard let first else { return false }
        let end = last ?? first
        return (min(first.verse, end.verse)...max(first.verse, end.verse)).contains(verse.verse)
    }
}
