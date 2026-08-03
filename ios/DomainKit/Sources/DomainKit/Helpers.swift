// Pure domain helpers, ported from src/lib/helpers.ts.
import Foundation

private let footnoteMarkerRegex = try! NSRegularExpression(pattern: "\\[[a-zA-Z0-9]+\\]")

/// Strips ESV/proof-text footnote markers (e.g. "[a]", "[12]") out of
/// confession text.
public func stripFootnoteMarkers(_ text: String = "") -> String {
    let range = NSRange(text.startIndex..., in: text)
    let stripped = footnoteMarkerRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    return stripped
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Orders two entry ids in canonical document order, comparing the
/// dash-delimited fragments after the document prefix numerically where
/// both sides are numbers (chapter/question numbers), lexically otherwise
/// (e.g. Canons of Dort's "articles" sorts before "rejections").
public func compareEntryIds(_ aId: String, _ bId: String) -> Bool {
    let a = aId.split(separator: "-").dropFirst().map(String.init)
    let b = bId.split(separator: "-").dropFirst().map(String.init)
    let len = max(a.count, b.count)
    for i in 0..<len {
        guard i < a.count else { return true }
        guard i < b.count else { return false }
        let (av, bv) = (a[i], b[i])
        if let aNum = Int(av), let bNum = Int(bv) {
            if aNum != bNum { return aNum < bNum }
        } else if av != bv {
            return av < bv
        }
    }
    return false
}

// returns doc id excluding of/the, so not WCoF --> WCF. This is confusing tech debt.
public func getConciseDocId(_ docTitle: String) -> String {
    docTitle
        .uppercased()
        .split(separator: " ")
        .map(String.init)
        .filter { !excludedWordsInDocumentId.contains($0) }
        .reduce(into: "") { acc, word in
            if let first = word.first { acc.append(first) }
        }
}

public func getCanonicalDocId(_ docTitleOrId: String) -> String {
    let arr = docTitleOrId.split(separator: " ", omittingEmptySubsequences: false)
    if arr.count == 1 {
        guard let citation = confessionCitationByIndex[docTitleOrId.uppercased()]?.first else { return "" }
        return getConciseDocId(citation)
    }
    return getConciseDocId(docTitleOrId)
}

/// strips the leading "<documentId>-" prefix off an entry id, leaving the
/// dash-joined path segment used by /library/[confession]/[entry].
public func entryIdToPathSegment(_ id: String, _ documentId: String) -> String {
    String(id.dropFirst(documentId.count + 1))
}

/// generates a /search?q= link for a confession id, the v2 equivalent of
/// v1's query-string search route. Canons of Dort keeps its rejection/
/// article disambiguation in the query grammar (CD.1.r2).
public func generateSearchLink(_ confessionId: String) -> String {
    let idAsArr = confessionId.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    let id = idAsArr.first ?? ""
    let chapterOrQuestion = idAsArr.count > 1 ? idAsArr[1] : ""
    let docId = getCanonicalDocId(id)
    let query: String
    if docId == "CD" {
        if idAsArr.count < 4 {
            query = "\(docId).\(chapterOrQuestion)"
        } else if idAsArr[2] == "rejections" {
            query = "\(docId).\(chapterOrQuestion).r\(idAsArr[3])"
        } else {
            query = "\(docId).\(chapterOrQuestion).\(idAsArr[3])"
        }
    } else if idAsArr.count == 2 {
        query = "\(docId).\(chapterOrQuestion)"
    } else {
        let article = idAsArr.count > 2 ? idAsArr[2] : ""
        query = "\(docId).\(chapterOrQuestion).\(article)"
    }
    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    return "/search?q=\(encoded)"
}

/// resolves a confession id (e.g. "WCoF-1-2") to its canonical per-entry
/// page URL, e.g. "/library/westminster-confession-of-faith/1-2". Returns
/// nil when no per-entry page exists for the id's document.
public func generateCanonicalEntryLink(_ confessionId: String) -> String? {
    let parts = confessionId.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    guard let id = parts.first else { return nil }
    let rest = Array(parts.dropFirst())
    let trueDocId = parentIdByAbbreviation[getCanonicalDocId(id)]
    let slug = trueDocId.flatMap { slugByDocumentId[$0] }
    guard let slug, !rest.isEmpty else { return nil }
    return "/library/\(slug)/\(rest.joined(separator: "-"))"
}

/// resolves a confession id to the (documentSlug, entryId) pair
/// LibraryRoute.entry needs to push straight to that entry's reading page —
/// the same resolution generateCanonicalEntryLink does, without round-
/// tripping through a URL string. Nil for the same cases
/// generateCanonicalEntryLink returns nil for.
public func libraryEntryRoute(for confessionId: String) -> (slug: String, entryId: String)? {
    let parts = confessionId.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    guard let id = parts.first, parts.count > 1 else { return nil }
    let trueDocId = parentIdByAbbreviation[getCanonicalDocId(id)]
    guard let slug = trueDocId.flatMap({ slugByDocumentId[$0] }) else { return nil }
    return (slug, confessionId)
}

/// prefers the canonical per-entry URL over the query-string search link
/// when the target id is a real leaf entry with its own static page.
public func generateNavLink(_ confessionId: String, _ entries: ContentById) -> String {
    if let target = entries[confessionId], !target.isParent,
       let canonicalHref = generateCanonicalEntryLink(confessionId) {
        return canonicalHref
    }
    return generateSearchLink(confessionId)
}

/// Renders a pretty version of a confession id, e.g. "HC-12-45" ->
/// "Heidelberg Catechism LORD's Day 12 Question and Answer 45 ".
public func parseConfessionId(_ id: String) -> String {
    let fragments = id.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    guard let docKey = fragments.first, let labels = confessionCitationByIndex[docKey] else { return "" }
    var acc = ""
    for (i, frag) in fragments.enumerated() {
        let label = i < labels.count ? labels[i] : ""
        acc += i == 0 ? "\(label) " : "\(label) \(frag) "
    }
    return acc
}

private let shortDocumentNameById: [String: String] = [
    "WCF": "Westminster Confession",
    "WCoF": "Westminster Confession",
    "WCOF": "Westminster Confession",
    "WSC": "Shorter Catechism",
    "WLC": "Larger Catechism",
    "HC": "Heidelberg Catechism",
]

public struct CitedByEntry: Equatable, Sendable {
    public let entryId: String
    public let label: String
}

/// The citations index stores `citedBy` ids with a trailing footnote marker
/// ("WLC-50-2", "HC-6-17-d", "WCoF-10-3-a"). How many locator fragments
/// belong to the entry itself is fixed per document grammar (WSC/WLC one,
/// WCoF/HC two); anything beyond that is the marker and is dropped to reach
/// the entry.
public func parseCitedById(_ citedById: String) -> CitedByEntry {
    let parts = citedById.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    let docId = parts.first ?? ""
    let rest = Array(parts.dropFirst())
    let locatorCount = max(1, (confessionCitationByIndex[docId]?.count ?? 3) - 2)
    let locators = Array(rest.prefix(locatorCount))
    let entryId = ([docId] + locators).joined(separator: "-")
    guard let shortName = shortDocumentNameById[docId] else {
        return CitedByEntry(entryId: entryId, label: parseConfessionId(entryId))
    }
    let label: String
    if locators.count == 1 {
        label = "\(shortName) Q. \(locators[0])"
    } else if docId == "HC" {
        label = "\(shortName) Q&A \(locators.count > 1 ? locators[1] : "")"
    } else {
        label = "\(shortName) \(locators.joined(separator: "."))"
    }
    return CitedByEntry(entryId: entryId, label: label)
}

// MARK: - Facet grammar (parseFacets)
//
// The web implementation exploits a JavaScript-only regex quirk (a
// backreference to a capturing group that didn't participate in the current
// match attempt matches the empty string) to reuse one alternation for
// three purposes. That quirk doesn't hold in ICU/NSRegularExpression, so
// this is a from-scratch reimplementation of the same *observable*
// behavior, verified against the same fixtures as src/lib/helpers.ts's
// vitest suite (see docs/DOMAIN.md) rather than a literal regex port.

private let docAliasesInOrder: [String] = [
    "catechism for young children", "cfyc", "wcf", "Westminster Confession of Faith",
    "hc", "Heidelberg Catechism", "WSC", "Westminster Shorter Catechism",
    "WLC", "Westminster Larger Catechism", "39A", "Thirty Nine Articles", "39 Articles",
    "tar", "bcf", "bc", "Belgic Confession of Faith", "Belgic Confession",
    "COD", "CD", "Canons of Dordt", "95T", "95 Theses", "Ninety Five Theses", "ML9T", "*",
]

private let keywordPhrasesInOrder: [String] = [
    "westminster standards", "three forms of unity", "3 forms of unity",
    "six forms of unity", "6 forms of unity",
]

private let bibleBookNamesInOrder: [String] = [
    "genesis", "exodus", "leviticus", "numbers", "deuteronomy", "joshua", "judges", "ruth",
    "1 samuel", "2 samuel", "1 kings", "2 kings", "1 chronicles", "2 chronicles", "ezra", "nehemiah",
    "esther", "job", "psalms", "psalm", "proverbs", "ecclesiastes", "song of solomon", "isaiah",
    "jeremiah", "lamentations", "ezekiel", "daniel", "hosea", "joel", "amos", "obadiah", "jonah",
    "micah", "nahum", "habakkuk", "zephaniah", "haggai", "zechariah", "malachi", "testament",
    "matthew", "mark", "luke", "john", "acts", "romans", "1 corinthians", "2 corinthians",
    "galatians", "ephesians", "philippians", "colossians", "1 thessalonians", "2 thessalonians",
    "1 timothy", "2 timothy", "titus", "philemon", "hebrews", "james", "1 peter", "2 peter",
    "1 john", "2 john", "3 john", "jude", "revelation",
]

private let allCanonicalDocIdsInOrder = ["WCoF", "HC", "WLC", "WSC", "CoD", "TBCoF", "TAoR", "ML9t", "CfYC"]

/// Finds the earliest (leftmost) case-insensitive occurrence of any phrase
/// in `phrases`, breaking position ties by the phrase's order in the list —
/// mirrors how a regex alternation picks among alternatives that match at
/// the same starting position.
private func findEarliestPhrase(_ phrases: [String], in str: String) -> (text: String, range: Range<String.Index>)? {
    var best: (text: String, range: Range<String.Index>)?
    for phrase in phrases {
        guard let r = str.range(of: phrase, options: [.caseInsensitive]) else { continue }
        if best == nil || r.lowerBound < best!.range.lowerBound {
            best = (String(str[r]), r)
        }
    }
    return best
}

/// Finds the first "." (optionally followed by "r"/"R") + digits run at or
/// after `start` — the facet grammar's chapter/article/rejection locator.
private func firstDotDigits(in str: String, from start: String.Index) -> (raw: String, range: Range<String.Index>)? {
    var i = start
    while i < str.endIndex {
        if str[i] == "." {
            var j = str.index(after: i)
            if j < str.endIndex, str[j] == "r" || str[j] == "R" {
                j = str.index(after: j)
            }
            let digitsStart = j
            while j < str.endIndex, str[j].isNumber {
                j = str.index(after: j)
            }
            if j > digitsStart {
                return (String(str[i..<j]), i..<j)
            }
        }
        i = str.index(after: i)
    }
    return nil
}

private func removeDot(_ str: String) -> String { str.replacingOccurrences(of: ".", with: "") }

private func stripAllOccurrences(of phrases: [String], in str: String) -> String {
    var result = str
    for phrase in phrases {
        while let r = result.range(of: phrase, options: [.caseInsensitive]) {
            result.removeSubrange(r)
        }
    }
    return result
}

private func stripAllFacetTokens(_ str: String) -> String {
    var result = stripAllOccurrences(of: docAliasesInOrder, in: str)
    while let m = firstDotDigits(in: result, from: result.startIndex) {
        result.removeSubrange(m.range)
    }
    return result
}

/// True when the whole string is "consumed" by a document alias plus its
/// chapter/article locators, with nothing else left over — the search-box
/// equivalent of "the user searched for an entire confession/chapter".
public func isEmptyKeywordSearch(_ search: String) -> Bool {
    stripAllFacetTokens(search).isEmpty
}

private func keywordBundleFacets(_ str: String) -> FacetFilters? {
    guard let match = findEarliestPhrase(keywordPhrasesInOrder, in: str) else { return nil }
    let phrase = match.text
    let lower = phrase.lowercased()
    func title(_ key: String) -> String { confessionCitationByIndex[key]?.first ?? "" }
    if lower.hasPrefix("west") {
        return [.or(["document:\(title("WSC"))", "document:\(title("WLC"))", "document:\(title("WCF"))"])]
    }
    if phrase.hasPrefix("3") || lower.hasPrefix("three") {
        return [.or(["document:\(title("HC"))", "document:\(title("COD"))", "document:\(title("BC"))"])]
    }
    if phrase.hasPrefix("6") || lower.hasPrefix("six") {
        return [.or([
            "document:\(title("HC"))", "document:\(title("COD"))", "document:\(title("BC"))",
            "document:\(title("WSC"))", "document:\(title("WLC"))", "document:\(title("WCF"))",
        ])]
    }
    return nil
}

private let bibleCitationTailRegex = try! NSRegularExpression(
    pattern: #"(\d+)(?::(\d+))?(?:-(?:(\d+):)?(\d+))?$"#
)

private func bibleFacets(_ str: String) -> FacetFilters {
    guard let bookMatch = findEarliestPhrase(bibleBookNamesInOrder, in: str) else { return [] }
    let book = toOsis(bookMatch.text) ?? ""
    let rest = String(str[bookMatch.range.upperBound...])
    let nsrange = NSRange(rest.startIndex..., in: rest)
    guard let m = bibleCitationTailRegex.firstMatch(in: rest, range: nsrange) else {
        return [.and("book:\(book)")]
    }
    func group(_ i: Int) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: rest) else { return nil }
        return String(rest[r])
    }
    let startChapter = group(1) ?? ""
    let startVerse = group(2)
    let endChapter = group(3)
    let endVerse = group(4)

    var facets: FacetFilters = [.and("book:\(book)"), .and("startChapter:\(startChapter)")]
    if let startVerse { facets.append(.and("startVerse:\(startVerse)")) }
    if let endVerse {
        if let endChapter { facets.append(.and("endChapter:\(endChapter)")) }
        facets.append(.and("endVerse:\(endVerse)"))
    }
    return facets
}

/// Parses a search string into Algolia facetFilters, mirroring src/lib/
/// helpers.ts's parseFacets (see the MARK above on why this isn't a literal
/// regex transliteration).
public func parseFacets(_ str: String) -> FacetFilters {
    if let bundle = keywordBundleFacets(str) { return bundle }
    if str.contains("*") {
        return [.or(allCanonicalDocIdsInOrder.map { "document:\(confessionCitationByIndex[$0.uppercased()]?.first ?? "")" })]
    }

    let docMatch = findEarliestPhrase(docAliasesInOrder, in: str)
    let chapMatch = docMatch.flatMap { firstDotDigits(in: str, from: $0.range.upperBound) }
    let artMatch = chapMatch.flatMap { firstDotDigits(in: str, from: $0.range.upperBound) }

    let document: String? = docMatch.map { m in
        let words = m.text.uppercased().split(separator: " ").map(String.init)
            .filter { !excludedWordsInDocumentId.contains($0) }
        if words.count == 1 { return words[0] }
        return words.compactMap { $0.first.map(String.init) }.joined()
    }
    let documentId = document.map(getCanonicalDocId)
    let chapter = chapMatch.map { removeDot($0.raw) }
    let article = artMatch.map { removeDot($0.raw) }

    func parentId(_ doc: String) -> String { parentIdByAbbreviation[doc] ?? "" }

    if documentId == "CD", let chapter, let document {
        if let article, article.lowercased().contains("r") {
            return [.and("id:\(parentId(document))-\(chapter)-rejections-\(String(article.dropFirst()))")]
        }
        if let article {
            return [.and("id:\(parentId(document))-\(chapter)-articles-\(article)")]
        }
        return [.or([
            "parent:\(parentId(document))-\(chapter)-articles",
            "parent:\(parentId(document))-\(chapter)-rejections",
        ])]
    }
    if let document, let chapter, let documentId, documentsWithoutArticles.contains(documentId) {
        return [.and("id:\(parentId(document))-\(chapter)")]
    }
    if let document, let chapter, let article {
        return [.and("id:\(parentId(document))-\(chapter)-\(article)")]
    }
    if let document, let chapter {
        return [.and("parent:\(parentId(document))-\(chapter)")]
    }
    // new UX: when searching an entire confession, just return the first
    // chapter — users iterate via next/previous buttons.
    if let document, isEmptyKeywordSearch(str) {
        if let documentId, documentsWithoutArticles.contains(documentId) {
            return [.and("id:\(parentId(document))-1")]
        }
        if documentId == "CD" {
            return [.or(["parent:\(parentId(document))-1-articles", "parent:\(parentId(document))-1-rejections"])]
        }
        return [.and("parent:\(parentId(document))-1")]
    }
    if let document {
        return [.and("document:\(confessionCitationByIndex[document]?.first ?? "")")]
    }
    return bibleFacets(str)
}

/// strips the facet grammar out of a search string, leaving the free-text
/// keyword query that goes to Algolia as `query`.
public func removeFacetSyntax(_ search: String) -> String {
    var result = stripAllFacetTokens(search)
    result = stripAllOccurrences(of: bibleBookNamesInOrder, in: result)
    result = stripAllOccurrences(of: keywordPhrasesInOrder, in: result)
    return result.trimmingCharacters(in: .whitespaces)
}
