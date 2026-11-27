import SwiftUI
import DomainKit

struct ReaderConfessionsSheet: View {
    let verseText: String
    let reference: String
    let entries: [ScriptureCitingEntry]
    let paper: Color
    let ink: Color
    let gilt: Color
    let chapel: Color
    let onChapel: Color
    var initialClause: ScriptureCitingEntry? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var document: String?
    @State private var scrolledEntryId: String?
    @State private var clause: ScriptureCitingEntry?
    @State private var detent: PresentationDetent = .height(536)
    @ScaledMetric(relativeTo: .body) private var cardHeight = 272.0

    init(
        verseText: String,
        reference: String,
        entries: [ScriptureCitingEntry],
        paper: Color,
        ink: Color,
        gilt: Color,
        chapel: Color,
        onChapel: Color,
        initialClause: ScriptureCitingEntry? = nil
    ) {
        self.verseText = verseText
        self.reference = reference
        self.entries = entries
        self.paper = paper
        self.ink = ink
        self.gilt = gilt
        self.chapel = chapel
        self.onChapel = onChapel
        self.initialClause = initialClause
        _clause = State(initialValue: initialClause)
        _detent = State(initialValue: initialClause == nil ? .height(536) : .large)
    }

    private var documents: [LibraryDocument] {
        LIBRARY_DOCUMENTS.filter { doc in entries.contains { $0.documentSlug == doc.slug } }
    }

    private var filtered: [ScriptureCitingEntry] {
        entries.filter { document == nil || $0.documentSlug == document }
    }

    private var currentPage: Int {
        guard let scrolledEntryId,
              let index = filtered.firstIndex(where: { $0.entryId == scrolledEntryId }) else { return 0 }
        return index
    }

    var body: some View {
        Group {
            if let clause {
                clauseScreen(clause)
            } else {
                citations
            }
        }
        .foregroundStyle(.ccInk)
        .presentationBackground(clause == nil ? Color.ccSurface : Color.ccPaper)
        .presentationDetents([.height(536), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ChapelRadius.sheet)
    }

    private var citations: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("\(entries.count)")
                        .font(.ccDisplay(22, semibold: true))
                        .frame(width: 56, height: 56)
                        .overlay { Circle().strokeBorder(lineWidth: 2) }
                        .foregroundStyle(.ccGilt)
                        .padding(.bottom, 4)
                        .accessibilityHidden(true)
                    Text("CITED IN THE CONFESSIONS")
                        .font(.ccDisplay(15, semibold: true))
                        .tracking(1.2)
                    Text("\(reference) is a proof text for \(entries.count) \(entries.count == 1 ? "clause" : "clauses"). Swipe through them.")
                        .font(.ccUI(13))
                        .foregroundStyle(.ccInk3)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)

                if documents.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            filter("All", slug: nil)
                            ForEach(documents, id: \.slug) { doc in
                                filter(abbreviation(doc), slug: doc.slug)
                            }
                        }
                        .frame(minWidth: 346)
                        .padding(.horizontal, 22)
                    }
                    .scrollIndicators(.hidden)
                }

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(filtered, id: \.entryId) { entry in
                            citationCard(entry)
                                .id(entry.entryId)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 22, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledEntryId)
                .scrollIndicators(.hidden)
                .frame(height: cardHeight)

                HStack(spacing: 5) {
                    ForEach(filtered.indices, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.ccGilt : Color.ccLine)
                            .frame(width: 5, height: 5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Clause \(currentPage + 1) of \(filtered.count)")
            }
            .padding(.top, 20)
            .padding(.bottom, 26)
        }
    }

    private func citationCard(_ entry: ScriptureCitingEntry) -> some View {
        Button {
            clause = entry
            detent = .large
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.documentTitle.uppercased())
                    .font(.ccDisplay(11, semibold: true))
                    .tracking(1.54)
                    .foregroundStyle(.ccGilt)
                Text(entry.entryLabel)
                    .font(.ccUI(12))
                    .foregroundStyle(.ccInk3)
                    .padding(.top, 2)
                if let heading = readerClauseHeading(for: entry) {
                    Text(heading)
                        .chapelReading(size: 18, lineHeight: 1.3)
                        .foregroundStyle(.ccInk)
                        .lineLimit(2)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                }
                Text(fullClauseText(entry))
                    .font(.ccUI(13))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .foregroundStyle(.ccInk2)
                    .padding(.top, readerClauseHeading(for: entry) == nil ? 10 : 0)
                Spacer(minLength: 8)
                Text("Read the clause →")
                    .font(.ccUI(13, weight: .semibold))
                    .foregroundStyle(.ccChapel)
            }
            .multilineTextAlignment(.leading)
            .padding(20)
            .frame(width: 300, height: cardHeight - 4, alignment: .topLeading)
            .background(.ccPaper, in: RoundedRectangle(cornerRadius: 18, style: .circular))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .circular)
                    .strokeBorder(.ccLine, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader-clause-\(entry.entryId)")
    }

    private func filter(_ title: String, slug: String?) -> some View {
        let active = document == slug
        return Button {
            document = slug
            scrolledEntryId = filtered.first?.entryId
        } label: {
            Text(title)
                .font(.ccUI(12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(active ? Color.ccGilt : Color.ccInk2)
                .background(active ? Color.ccGilt.opacity(0.16) : .clear, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(active ? Color.ccGilt : Color.ccLine, lineWidth: 1)
                }
                .frame(minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func abbreviation(_ document: LibraryDocument) -> String {
        switch document.documentId {
        case "WCoF": "WCF"
        case "HC": "Heidelberg"
        default: document.documentId
        }
    }

    private func libraryEntry(_ entry: ScriptureCitingEntry) -> ConfessionEntry? {
        loadConfessionContent(entry.documentSlug)?.contentById[entry.entryId]
    }

    private func fullClauseText(_ entry: ScriptureCitingEntry) -> String {
        let full = stripFootnoteMarkers(libraryEntry(entry)?.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? entry.clause : full
    }

    private func clauseScreen(_ entry: ScriptureCitingEntry) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if initialClause == nil {
                        clause = nil
                        detent = .height(536)
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.ccSurface.opacity(0.75), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back to citations")
                Spacer()
                Text(readerClauseShortLabel(for: entry))
                    .font(.ccDisplay(13))
                    .tracking(1.3)
                Spacer()
                ShareLink(item: "\(entry.documentTitle) · \(entry.entryLabel)\n\n\(fullClauseText(entry))") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(Color.ccSurface.opacity(0.75), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share")
                .accessibilityIdentifier("reader-clause-share")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.documentTitle.uppercased())
                        .font(.ccDisplay(12, semibold: true))
                        .tracking(1.92)
                        .foregroundStyle(.ccGilt)
                        .padding(.top, 26)
                    Text(entry.entryLabel)
                        .font(.ccUI(13))
                        .foregroundStyle(.ccInk3)
                        .padding(.top, 4)
                    if let heading = readerClauseHeading(for: entry) {
                        Text(heading)
                            .chapelReading(size: 26, lineHeight: 1.25)
                            .foregroundStyle(.ccInk)
                            .padding(.top, 10)
                            .padding(.bottom, 20)
                    }
                    Text(fullClauseText(entry))
                        .chapelReading(size: 18, lineHeight: 1.65)
                        .foregroundStyle(.ccInk)
                        .padding(.top, readerClauseHeading(for: entry) == nil ? 16 : 0)

                    VStack(alignment: .leading, spacing: 12) {
                        (Text("You came from ")
                            + Text(reference).bold().foregroundStyle(.ccGilt)
                            + Text(verseText.isEmpty ? "." : ". “\(verseText)”"))
                            .font(.ccUI(14))
                            .lineSpacing(3)
                            .foregroundStyle(.ccInk2)
                        Button { dismiss() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Back to the verse")
                            }
                            .font(.ccUI(14, weight: .semibold))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 40)
                            .background(.ccChapel, in: Capsule())
                            .foregroundStyle(.ccOnChapel)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.ccGilt.opacity(0.16), in: RoundedRectangle(cornerRadius: ChapelRadius.card, style: .circular))
                    .padding(.top, 32)
                }
                .frame(maxWidth: 540, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .background(.ccPaper)
    }
}
