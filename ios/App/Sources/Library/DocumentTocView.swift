// A document's table of contents — mirrors
// src/app/(column)/library/[confession]/page.tsx: section headers for
// parent (chapter/head-of-doctrine) entries, rows for every leaf entry in
// canonical document order.
import SwiftUI
import DomainKit

struct DocumentTocView: View {
    let slug: String
    @Binding var path: NavigationPath

    @Environment(\.dismiss) private var dismiss

    private var doc: LibraryDocument? { getLibraryDocument(slug) }
    private var entries: [ConfessionEntry] { getOrderedEntries(slug) }

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
                                path.append(LibraryRoute.entry(slug: slug, entryId: entry.id))
                            } label: {
                                Text(tocRowTitle(entry))
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
            .padding(.bottom, 32)
        }
        .background(Color.ccCanvas)
        .toolbar(.hidden, for: .navigationBar)
    }
}
