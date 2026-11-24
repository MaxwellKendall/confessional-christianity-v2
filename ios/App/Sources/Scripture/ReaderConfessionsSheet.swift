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

    @Environment(\.dismiss) private var dismiss
    @State private var document: String?
    @State private var page = 0
    @State private var clause: ScriptureCitingEntry?
    @State private var detent: PresentationDetent = .height(505)
    @ScaledMetric(relativeTo: .body) private var cardHeight = 270.0

    private var documents: [LibraryDocument] {
        LIBRARY_DOCUMENTS.filter { doc in entries.contains { $0.documentSlug == doc.slug } }
    }

    private var filtered: [ScriptureCitingEntry] {
        entries.filter { document == nil || $0.documentSlug == document }
    }

    var body: some View {
        Group {
            if let clause {
                clauseScreen(clause)
            } else {
                citations
            }
        }
        .foregroundStyle(ink)
        .presentationBackground(paper)
        .presentationDetents([.height(505), .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private var citations: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("\(entries.count)")
                        .font(.ccDisplay(19, semibold: true))
                        .frame(width: 48, height: 48)
                        .overlay { Circle().strokeBorder(lineWidth: 2) }
                        .overlay { Circle().strokeBorder(lineWidth: 0.5).padding(4) }
                        .foregroundStyle(gilt)
                        .accessibilityHidden(true)
                    Text("CITED IN THE CONFESSIONS").font(.ccDisplay(14, semibold: true)).tracking(1.5)
                    Text("\(reference) is a proof text for \(entries.count) \(entries.count == 1 ? "clause" : "clauses").")
                        .font(.ccBody(16))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

                if documents.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            filter("All", slug: nil)
                            ForEach(documents, id: \.slug) { doc in
                                filter(abbreviation(doc), slug: doc.slug)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                }

                TabView(selection: $page) {
                    ForEach(Array(filtered.enumerated()), id: \.element.entryId) { index, entry in
                        Button {
                            clause = entry
                            detent = .large
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                clauseHeading(entry)
                                Text(clauseText(entry))
                                    .font(.ccBody(16))
                                    .lineLimit(3)
                                    .foregroundStyle(ink.opacity(0.82))
                                Spacer(minLength: 0)
                                Text("Read the clause →")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(chapel)
                            }
                            .multilineTextAlignment(.leading)
                            .padding(18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(ink.opacity(0.18)) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reader-clause-\(entry.entryId)")
                        .padding(.horizontal, 20)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: cardHeight)

                HStack(spacing: 5) {
                    ForEach(filtered.indices, id: \.self) { index in
                        Circle()
                            .fill(index == page ? chapel : ink.opacity(0.22))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Clause \(page + 1) of \(filtered.count)")
            }
            .padding(.vertical, 22)
        }
    }

    private func filter(_ title: String, slug: String?) -> some View {
        let active = document == slug
        return Button {
            page = 0
            document = slug
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 13)
                .frame(minHeight: 38)
                .foregroundStyle(active ? onChapel : ink)
                .background(active ? chapel : ink.opacity(0.07), in: Capsule())
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

    private func clauseText(_ entry: ScriptureCitingEntry) -> String {
        // A few bundled proof texts have a citation without an inline marker.
        entry.clause.isEmpty ? stripFootnoteMarkers(libraryEntry(entry)?.text ?? "") : entry.clause
    }

    private func clauseHeading(_ entry: ScriptureCitingEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.documentTitle.uppercased())
                .font(.ccDisplay(11, semibold: true))
                .tracking(1)
                .foregroundStyle(chapel)
            Text(entry.entryLabel).font(.subheadline).foregroundStyle(ink.opacity(0.82))
            if entry.entryLabel.hasPrefix("Q. "),
               let title = libraryEntry(entry)?.title,
               let separator = title.firstIndex(of: ":") {
                Text(title[title.index(after: separator)...].trimmingCharacters(in: .whitespaces))
                    .font(.ccBody(20))
            }
        }
    }

    private func clauseScreen(_ entry: ScriptureCitingEntry) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back to verse")
                Spacer()
                Text(entry.entryLabel).font(.ccDisplay(13))
                Spacer()
                ShareLink(item: "\(entry.documentTitle) · \(entry.entryLabel)\n\n\(clauseText(entry))") {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Share")
                .accessibilityIdentifier("reader-clause-share")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    clauseHeading(entry)
                    Text(clauseText(entry)).font(.ccBody(21)).lineSpacing(5)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("You came from \(reference)").font(.subheadline.weight(.semibold))
                        Text("“\(verseText)”").font(.ccBody(17)).italic()
                        Button("Back to the verse") { dismiss() }
                            .buttonStyle(.bordered)
                            .tint(chapel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(ink.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxWidth: 540, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
