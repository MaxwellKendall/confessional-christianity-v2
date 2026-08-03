// A single confession/catechism entry's reading page — mirrors
// src/app/(column)/library/[confession]/[entry]/page.tsx: the quoted text
// with footnote markers, its proof texts, and Prev/Next paging through the
// document. Reflection cross-links and ESV live-fetch aren't ported yet
// (Reflections/ESV are separate, not-yet-started phases) — proof texts show
// as plain citations rather than expandable ESV text.
import SwiftUI
import DomainKit

struct LibraryEntryView: View {
    let slug: String
    let entryId: String
    @Binding var path: NavigationPath

    @Environment(\.dismiss) private var dismiss

    private var page: EntryPage? { getEntryPage(slug, entryId: entryId) }

    var body: some View {
        ScrollView {
            if let page {
                VStack(spacing: 0) {
                    breadcrumb(page)

                    VStack(spacing: 12) {
                        Text(entryPageLabel(page.item))
                            .labelCaps(size: 9.5, tracking: 0.1)
                        VStack(spacing: 2) {
                            ForEach(Array(entryQuoteSegments(page.item).enumerated()), id: \.offset) { _, segments in
                                quoteLine(segments)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                    let groups = proofTextGroups(page.item)
                    if !groups.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Proof Texts").labelCaps(size: 9.5, tracking: 0.1)
                            ForEach(groups, id: \.marker) { group in
                                proofTextRow(group)
                            }
                        }
                        .padding(.top, 28)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.ccHairline).frame(height: 1)
                        }
                    }

                    HStack {
                        pagingLink(page.prevEntry, symbol: "\u{2190}", isNext: false)
                        Spacer()
                        pagingLink(page.nextEntry, symbol: "\u{2192}", isNext: true)
                    }
                    .padding(.top, 28)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.ccHairline).frame(height: 1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color.ccCanvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func breadcrumb(_ page: EntryPage) -> some View {
        HStack(spacing: 4) {
            Button {
                path.removeLast(path.count)
            } label: {
                Text("Library").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3).dottedUnderline(.ccInk3)
            }
            .buttonStyle(.plain)
            Text("/").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
            Button {
                path.removeLast()
            } label: {
                Text(page.documentTitle).labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    @ViewBuilder
    private func quoteLine(_ segments: [TextSegment]) -> some View {
        segments.enumerated().reduce(Text("")) { acc, pair in
            let (_, segment) = pair
            var line = acc + Text(segment.text).font(.ccBody(17)).italic().foregroundStyle(.ccInk)
            if let marker = segment.marker {
                line = line + Text(marker).font(.ccBody(11)).baselineOffset(6).foregroundStyle(.ccInk3)
            }
            return line
        }
        .multilineTextAlignment(.center)
        .lineSpacing(6)
    }

    @ViewBuilder
    private func proofTextRow(_ group: ProofTextGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(group.marker)
                .font(.ccBody(11))
                .foregroundStyle(.ccInk3)
                .frame(width: 16, alignment: .trailing)
            Text(group.refs.map(\.citation).joined(separator: " \u{00B7} "))
                .font(.ccBody(13))
                .foregroundStyle(.ccInk2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func pagingLink(_ adjacent: AdjacentEntry?, symbol: String, isNext: Bool) -> some View {
        if let adjacent {
            Button {
                path.removeLast()
                path.append(LibraryRoute.entry(slug: slug, entryId: adjacent.entryId))
            } label: {
                Text(isNext ? "\(adjacent.title) \(symbol)" : "\(symbol) \(adjacent.title)")
                    .labelCaps(size: 10, tracking: 0.1, color: .ccInk)
                    .dottedUnderline(.ccInk)
            }
            .buttonStyle(.plain)
        } else {
            Text(isNext ? "Next \(symbol)" : "\(symbol) Prev")
                .labelCaps(size: 10, tracking: 0.1, color: .ccMuted)
        }
    }
}
