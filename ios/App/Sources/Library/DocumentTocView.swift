// A document's table of contents — mirrors
// src/app/(column)/library/[confession]/page.tsx: section headers for
// parent (chapter/head-of-doctrine) entries, rows for every leaf entry in
// canonical document order.
//
// For the catechisms that also have a real practice session (WSC/WLC/HC —
// CFYC isn't part of the Library surface), a leaf row deep-links into that
// SessionView at the tapped question rather than opening a second, read-only
// copy of the same Q&A — one reading experience, not two.
//
// A row is prefixed "†" when a reflection essay exists for that entry,
// mirroring the web TOC's commentary marker (PRD §10).
import SwiftUI
import DomainKit

struct DocumentTocView: View {
    let slug: String
    @Binding var path: NavigationPath

    @Environment(\.dismiss) private var dismiss

    private var doc: LibraryDocument? { getLibraryDocument(slug) }
    private var entries: [ConfessionEntry] { getOrderedEntries(slug) }
    private var linkedProgram: ProgramDefinition? { doc.flatMap { programForContentId($0.documentId) } }
    private var commentaryIds: Set<String> { listCommentaryIds() }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Text("Library")
                            .labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
                            .dottedUnderline(.ccInk3)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 20)

                if let doc {
                    VStack(spacing: 6) {
                        Text(doc.name).headingPage().multilineTextAlignment(.center)
                        Text(doc.blurb)
                            .font(.ccBody(12.5))
                            .italic()
                            .foregroundStyle(.ccInk2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }

                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                        if entry.isParent {
                            Text(entry.title ?? entry.id)
                                .labelCaps(size: 9.5, tracking: 0.1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, i == 0 ? 18 : 26)
                                .padding(.bottom, 6)
                                .overlay(alignment: .top) {
                                    Rectangle().fill(Color.ccHairline).frame(height: 1)
                                }
                        } else {
                            Button {
                                if let linkedProgram, let number = questionNumber(linkedProgram, entryId: entry.id) {
                                    path.append(LibraryRoute.session(programSlug: linkedProgram.slug, questionNumber: number))
                                } else {
                                    path.append(LibraryRoute.entry(slug: slug, entryId: entry.id))
                                }
                            } label: {
                                Text(commentaryIds.contains(entry.id) ? "\u{2020} \(tocRowTitle(entry))" : tocRowTitle(entry))
                                    .font(.ccDisplay(13.5, semibold: true))
                                    .foregroundStyle(.ccInk)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 11)
                                    .overlay(alignment: .top) {
                                        Rectangle().fill(Color.ccHairline).frame(height: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Color.ccCanvas)
        .toolbar(.hidden, for: .navigationBar)
    }
}
