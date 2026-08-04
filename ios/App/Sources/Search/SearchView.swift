// The /search surface — mirrors src/components/SearchClient.tsx: a debounced
// query field, confession-text rows and scripture-citation rows fanned out
// from the two Algolia indices, a "Cited by" line of links back into the
// Library, and a "More Results" pager. Per the web PRD, this is the only
// screen that shows match counts or the literal query; rows are short
// excerpts that link away to canonical pages.
import SwiftUI
import DomainKit

/// Algolia highlight values arrive as HTML with <em> markers around matches
/// (attributesToHighlight); they originate from our own indexed confession
/// text, so a bare <em>/</em> scan is all that's needed — no general HTML
/// parsing. Matches render bold and non-italic in full ink, mirroring
/// globals.css's `.search-excerpt em` rule.
private func attributedHighlight(_ html: String?, fallback: String, size: CGFloat) -> AttributedString {
    guard let html else { return AttributedString(fallback) }
    var result = AttributedString()
    var remaining = Substring(html)
    while let openRange = remaining.range(of: "<em>") {
        result += AttributedString(String(remaining[remaining.startIndex..<openRange.lowerBound]))
        remaining = remaining[openRange.upperBound...]
        guard let closeRange = remaining.range(of: "</em>") else {
            result += AttributedString(String(remaining))
            return result
        }
        var emphasized = AttributedString(String(remaining[remaining.startIndex..<closeRange.lowerBound]))
        emphasized.font = .system(size: size, weight: .bold)
        emphasized.foregroundColor = .ccInk
        result += emphasized
        remaining = remaining[closeRange.upperBound...]
    }
    result += AttributedString(String(remaining))
    return result
}

struct SearchView: View {
    @Binding var path: NavigationPath

    @State private var input = ""
    @State private var outcome: SearchOutcome?
    @State private var page = 0
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                backBar
                header
                if let outcome {
                    resultsList(outcome)
                } else if !isLoading {
                    Text(
                        "Search by keyword, the text of Scripture, a citation like John 3:16, "
                        + "or a reference like WSC.1 or WCF.1.2."
                    )
                    .font(.ccBody(13))
                    .italic()
                    .foregroundStyle(.ccInk2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                }
            }
            .padding(.bottom, 100)
        }
        .background(Color.ccCard)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { searchTask?.cancel() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search").labelCaps(size: 9.5, tracking: 0.14)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.ccInk)
                    .font(.system(size: 13))
                TextField("Keyword, citation, or WSC.1", text: $input)
                    .font(.ccBody(15))
                    .italic()
                    .foregroundStyle(.ccInk)
                    .autocorrectionDisabled()
                    .onChange(of: input) { _, newValue in scheduleSearch(newValue) }
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ccInk).frame(height: 1)
            }

            if let outcome {
                let shown = outcome.confessionHits.count + outcome.bibleHits.count
                let total = outcome.totalConfession + outcome.totalBible
                Text(isLoading ? "Searching\u{2026}" : "Showing \(min(shown, total)) of \(total) total matches")
                    .labelCaps(size: 9.5, tracking: 0.1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func resultsList(_ outcome: SearchOutcome) -> some View {
        VStack(spacing: 0) {
            ForEach(outcome.confessionHits) { hit in
                ConfessionRow(hit: hit, path: $path)
            }
            ForEach(outcome.bibleHits, id: \.objectID) { hit in
                CitationRow(hit: hit, path: $path)
            }
            if outcome.hasMore {
                Button {
                    loadMore()
                } label: {
                    Text(isLoading ? "Loading\u{2026}" : "More Results")
                        .labelCaps(size: 10, tracking: 0.1, color: .ccInk)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        page = 0
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            outcome = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(trimmed, page: 0)
        }
    }

    private func runSearch(_ query: String, page: Int) async {
        isLoading = true
        let result = await AlgoliaClient.shared.search(query, page: page)
        guard !Task.isCancelled else { return }
        if page > 0, let prev = outcome {
            outcome = SearchOutcome(
                confessionHits: prev.confessionHits + result.confessionHits,
                bibleHits: prev.bibleHits + result.bibleHits,
                totalConfession: result.totalConfession,
                totalBible: result.totalBible,
                hasMore: result.hasMore
            )
        } else {
            outcome = result
        }
        isLoading = false
    }

    private func loadMore() {
        let nextPage = page + 1
        page = nextPage
        let query = input.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        Task { await runSearch(query, page: nextPage) }
    }
}

private struct ConfessionRow: View {
    let hit: AggregateHit
    @Binding var path: NavigationPath

    var body: some View {
        Group {
            if let route = libraryEntryRoute(for: hit.id) {
                Button {
                    path.append(LibraryRoute.entry(slug: route.slug, entryId: route.entryId))
                } label: { content }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.document).labelCaps(size: 9, tracking: 0.1)
            Text(attributedHighlight(hit._highlightResult?.title?.value, fallback: hit.title, size: 14))
                .font(.ccDisplay(14, semibold: true))
                .foregroundStyle(.ccInk)
            Text(attributedHighlight(hit._highlightResult?.text?.value, fallback: hit.text, size: 12.5))
                .font(.ccBody(12.5))
                .italic()
                .foregroundStyle(.ccInk2)
                .lineLimit(4)
        }
    }
}

private struct CitationRow: View {
    let hit: CitationHit
    @Binding var path: NavigationPath

    private var osis: String? { citationToOsis(hit.citation) }

    // one link per citing entry, marker suffixes collapsed — the same entry
    // can cite a verse under several footnotes.
    private var citedBy: [CitedByEntry] {
        var seen = Set<String>()
        var result: [CitedByEntry] = []
        for id in hit.citedBy ?? [] {
            let cited = parseCitedById(id)
            guard !seen.contains(cited.entryId) else { continue }
            seen.insert(cited.entryId)
            result.append(cited)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Scripture").labelCaps(size: 9, tracking: 0.1)

            Group {
                if let osis {
                    Button {
                        path.append(ScriptureRoute.detail(osis: osis))
                    } label: {
                        Text(attributedHighlight(hit._highlightResult?.citation?.value, fallback: hit.citation, size: 14))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(attributedHighlight(hit._highlightResult?.citation?.value, fallback: hit.citation, size: 14))
                }
            }
            .font(.ccDisplay(14, semibold: true))
            .foregroundStyle(.ccInk)

            Text(attributedHighlight(hit._highlightResult?.bibleText?.value, fallback: hit.bibleText, size: 12.5))
                .font(.ccBody(12.5))
                .italic()
                .foregroundStyle(.ccInk2)
                .lineLimit(4)

            if !citedBy.isEmpty {
                citedByLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
        }
    }

    private static let citedByShown = 4

    private var citedByLine: some View {
        let shown = Array(citedBy.prefix(Self.citedByShown))
        let remainder = citedBy.count - shown.count
        return FlowLayout(horizontalSpacing: 4, verticalSpacing: 2) {
            Text("Cited by").font(.ccBody(11)).foregroundStyle(.ccInk3)
            ForEach(shown, id: \.entryId) { cited in
                citedByButton(label: cited.label) {
                    if let route = libraryEntryRoute(for: cited.entryId) {
                        path.append(LibraryRoute.entry(slug: route.slug, entryId: route.entryId))
                    }
                }
            }
            if remainder > 0, let osis {
                citedByButton(label: "\(remainder) more") {
                    path.append(ScriptureRoute.detail(osis: osis))
                }
            }
        }
        .padding(.top, 2)
    }

    private func citedByButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.ccBody(11)).foregroundStyle(.ccInk).dottedUnderline(.ccInk3, offset: 2)
        }
        .buttonStyle(.plain)
    }
}
