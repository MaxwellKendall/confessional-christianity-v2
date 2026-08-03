// Searches the existing Algolia indices — `aggregate` (confession text) and
// `citations` (scripture) — reused from web with no re-indexing, mirroring
// src/lib/algolia.ts. Called directly from the app with the public
// search-only key (same trust boundary as a browser — see the plan's note
// that Algolia's search-only key is safe to ship client-side, unlike the
// ESV key, which stays behind the /api/esv proxy). One query per index, run
// concurrently, rather than Algolia's own multi-query batching — simpler to
// decode than a single heterogeneous-hit response for two extra round trips
// on the same host.
import Foundation
import DomainKit

struct HighlightValue: Decodable, Sendable {
    let value: String
    let matchedWords: [String]
}

struct AggregateHit: Decodable, Identifiable, Sendable {
    struct Highlights: Decodable, Sendable {
        let title: HighlightValue?
        let text: HighlightValue?
    }

    let objectID: String
    let id: String
    let document: String
    let title: String
    let text: String
    let _highlightResult: Highlights?
}

struct CitationHit: Decodable, Identifiable, Sendable {
    struct Highlights: Decodable, Sendable {
        let citation: HighlightValue?
        let bibleText: HighlightValue?
    }

    let objectID: String
    let citation: String
    let bibleText: String
    let citedBy: [String]?
    let _highlightResult: Highlights?

    var id: String { objectID }
}

struct SearchOutcome: Sendable {
    var confessionHits: [AggregateHit]
    var bibleHits: [CitationHit]
    var totalConfession: Int
    var totalBible: Int
    var hasMore: Bool
}

actor AlgoliaClient {
    static let shared = AlgoliaClient()

    static let hitsPerPage = 25

    private static let appId = "GJWQ8595QX"
    private static let searchKey = "6bf914c6ec39cfdf56d5f649401c39bc"

    private struct QueryResult<Hit: Decodable & Sendable>: Decodable, Sendable {
        let hits: [Hit]
        let nbHits: Int
        let nbPages: Int
    }

    func search(_ input: String, page: Int = 0) async -> SearchOutcome {
        let facetFilters = parseFacets(input)
        let freeText = removeFacetSyntax(input)
        let facetFiltersJSON = Self.encodeFacetFilters(facetFilters)

        async let confession = Self.query(
            index: "aggregate", freeText: freeText, facetFiltersJSON: facetFiltersJSON,
            highlightAttributes: ["text", "title"], page: page, as: AggregateHit.self
        )
        async let bible = Self.query(
            index: "citations", freeText: freeText, facetFiltersJSON: facetFiltersJSON,
            highlightAttributes: ["citation", "bibleText"], page: page, as: CitationHit.self
        )
        let (confessionResult, bibleResult) = await (confession, bible)

        let hasMore = [confessionResult?.nbPages, bibleResult?.nbPages].contains { nbPages in
            guard let nbPages else { return false }
            return page < nbPages - 1
        }

        return SearchOutcome(
            confessionHits: confessionResult?.hits ?? [],
            bibleHits: bibleResult?.hits ?? [],
            totalConfession: confessionResult?.nbHits ?? 0,
            totalBible: bibleResult?.nbHits ?? 0,
            hasMore: hasMore
        )
    }

    private static func query<Hit: Decodable & Sendable>(
        index: String, freeText: String, facetFiltersJSON: String?,
        highlightAttributes: [String], page: Int, as hitType: Hit.Type
    ) async -> QueryResult<Hit>? {
        guard let url = URL(string: "https://\(appId)-dsn.algolia.net/1/indexes/\(index)/query") else { return nil }

        var params = "query=\(encode(freeText))&page=\(page)&hitsPerPage=\(hitsPerPage)"
        if let facetFiltersJSON { params += "&facetFilters=\(encode(facetFiltersJSON))" }
        let highlightJSON = "[" + highlightAttributes.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        params += "&attributesToHighlight=\(encode(highlightJSON))"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appId, forHTTPHeaderField: "X-Algolia-Application-Id")
        request.setValue(searchKey, forHTTPHeaderField: "X-Algolia-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["params": params])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(QueryResult<Hit>.self, from: data)
        } catch {
            return nil
        }
    }

    private static func encode(_ str: String) -> String {
        str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? str
    }

    /// Encodes FacetFilters (an AND list where each element is either a bare
    /// string or an OR array of strings) as the JSON Algolia expects for its
    /// `facetFilters` query param.
    private static func encodeFacetFilters(_ filters: FacetFilters) -> String? {
        guard !filters.isEmpty else { return nil }
        let elements: [Any] = filters.map { filter in
            switch filter {
            case .and(let value): return value
            case .or(let values): return values
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: elements),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
