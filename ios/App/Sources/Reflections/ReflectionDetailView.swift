// A single reflection's reading page — mirrors
// src/app/(column)/reflections/[slug]/page.tsx: series/part eyebrow, title,
// subtitle, author/date, a quote-card back to the source confession/
// catechism entry, the markdown body, then prev/next (within the series if
// part of one, else by reverse chronological order across all essays).
//
// Reachable from two different NavigationStacks (the Reflections tab's own,
// and Library's via a "† Commentary" link), so navigation is a plain
// `path.removeLast()`/`path.append(ReflectionsRoute.detail(...))` rather
// than anything tied to one specific stack's root.
import SwiftUI
import DomainKit

struct ReflectionDetailView: View {
    let slug: String
    @Binding var path: NavigationPath

    private var post: Reflection? { getReflectionBySlug(slug) }

    private var entryPage: EntryPage? {
        guard let post else { return nil }
        guard let prefix = post.entryId.split(separator: "-").first,
              let docSlug = slugByDocumentId[String(prefix)] else { return nil }
        return getEntryPage(docSlug, entryId: post.entryId)
    }

    private var siblings: [Reflection] {
        guard let post else { return [] }
        let all = loadReflections()
        if let series = post.series {
            return all.filter { $0.series == series }.sorted { ($0.part ?? 0) < ($1.part ?? 0) }
        }
        return all.reversed() // oldest -> newest for prev/next reading order
    }

    private var prev: Reflection? {
        guard let post, let i = siblings.firstIndex(where: { $0.slug == post.slug }), i > 0 else { return nil }
        return siblings[i - 1]
    }

    private var next: Reflection? {
        guard let post, let i = siblings.firstIndex(where: { $0.slug == post.slug }), i + 1 < siblings.count else { return nil }
        return siblings[i + 1]
    }

    var body: some View {
        ScrollView {
            if let post {
                VStack(spacing: 0) {
                    backBar

                    VStack(spacing: 6) {
                        if let series = post.series {
                            Text(post.part.map { "Series: \(series) \u{00B7} Part \($0) of \(siblings.count)" } ?? "Series: \(series)")
                                .labelCaps(size: 9.5, color: .ccInk3)
                        }
                        Text(post.title).headingPage().multilineTextAlignment(.center)
                        if let subtitle = post.subtitle {
                            Text(subtitle)
                                .font(.ccBody(13.5))
                                .italic()
                                .foregroundStyle(.ccInk2)
                                .multilineTextAlignment(.center)
                        }
                        Text(
                            [post.author, formatDate(post.date)]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " \u{00B7} ")
                        )
                        .labelCaps(size: 10, tracking: 0.14, color: .ccInk3)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                    if let entryPage {
                        quoteCard(entryPage)
                    }

                    MarkdownText(source: post.body)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    HStack {
                        pagingLink(prev, isNext: false)
                        Spacer()
                        pagingLink(next, isNext: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 100)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.ccHairline).frame(height: 1)
                    }
                }
            }
        }
        .background(Color.ccCard)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var backBar: some View {
        HStack {
            Button {
                if !path.isEmpty { path.removeLast() }
            } label: {
                Text("\u{2039} Back").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3).dottedUnderline(.ccInk3)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    @ViewBuilder
    private func quoteCard(_ page: EntryPage) -> some View {
        VStack(spacing: 10) {
            Text("\(page.documentTitle) \u{00B7} \(entryPageLabel(page.item))")
                .labelCaps(size: 9.5, tracking: 0.1)
            VStack(spacing: 4) {
                ForEach(Array(entryQuoteLines(page.item).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.ccBody(15.5))
                        .italic()
                        .foregroundStyle(.ccInk)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.ccFill)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    @ViewBuilder
    private func pagingLink(_ sibling: Reflection?, isNext: Bool) -> some View {
        if let sibling {
            Button {
                path.append(ReflectionsRoute.detail(slug: sibling.slug))
            } label: {
                let label = sibling.part.map { "Part \($0)" } ?? sibling.title
                Text(isNext ? "\(label) \u{2192}" : "\u{2190} \(label)")
                    .labelCaps(size: 10, tracking: 0.1, color: .ccInk)
                    .dottedUnderline(.ccInk)
            }
            .buttonStyle(.plain)
        } else {
            Text(isNext ? "Next \u{2192}" : "\u{2190} Prev")
                .labelCaps(size: 10, tracking: 0.1, color: .ccMuted)
        }
    }
}
